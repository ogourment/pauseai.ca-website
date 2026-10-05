defmodule PauseAiCaWeb.MailDraftsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.{Mail, Volunteers}
  alias PauseAiCa.Mail.{ContactSource, Render}
  @impl true
  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Volunteers.allowed?(socket.assigns.current_scope) do
      {:ok,
       assign(socket,
         locale: locale,
         page_title: gettext("Emails"),
         batches: [],
         batch: nil,
         anchor: nil,
         draft: nil,
         drafts: [],
         recipients: [],
         results: [],
         query: "",
         form: to_form(%{}, as: "template"),
         draft_form: to_form(%{}, as: "draft"),
         error: nil,
         status: nil
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Organizer access required."))
       |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_params(params, _, socket) do
    scope = socket.assigns.current_scope

    cond do
      params["account_id"] ->
        case Mail.recipient(scope, params["account_id"]) do
          {:ok, contact} -> {:noreply, assign(socket, anchor: contact)}
          _ -> {:noreply, denied(socket)}
        end

      socket.assigns.live_action == :new ->
        case ContactSource.search(scope, "", []) do
          {:ok, results} ->
            {:noreply,
             assign(socket, batch: nil, anchor: nil, draft: nil, query: "", results: results)}

          _ ->
            {:noreply, denied(socket)}
        end

      params["id"] ->
        case Mail.get(scope, params["id"]) do
          {:ok, batch} ->
            socket = load_batch(socket, batch)
            draft = Enum.find(socket.assigns.drafts, &(&1.id == params["draft"]))

            {:noreply,
             assign(socket,
               draft: draft,
               draft_form:
                 to_form(
                   if(draft,
                     do: %{"subject" => draft.subject, "source" => draft.source},
                     else: %{}
                   ),
                   as: "draft"
                 )
             )}

          _ ->
            {:noreply, denied(socket)}
        end

      true ->
        {:noreply, assign(socket, batch: nil, anchor: nil, draft: nil, batches: Mail.list(scope))}
    end
  end

  @impl true
  def handle_event("start-account", %{"id" => id}, socket) do
    start_batch(socket, id)
  end

  def handle_event("start", _, socket) do
    start_batch(socket, socket.assigns.anchor && socket.assigns.anchor.id)
  end

  def handle_event("search", %{"query" => query}, socket) do
    case ContactSource.search(socket.assigns.current_scope, query, []) do
      {:ok, results} -> {:noreply, assign(socket, query: query, results: results)}
      _ -> {:noreply, assign(socket, results: [], error: error_message(:unauthorized))}
    end
  end

  def handle_event("choose", %{"id" => id}, socket) do
    case ContactSource.fetch(socket.assigns.current_scope, id, []) do
      {:ok, contact} ->
        ids = Enum.uniq(socket.assigns.batch.recipient_ids ++ [contact.id])

        if length(ids) <= 5,
          do: {:noreply, save_template(socket, %{"recipient_ids" => ids})},
          else: {:noreply, assign(socket, error: error_message(:batch_size))}

      _ ->
        {:noreply, assign(socket, error: error_message(:unauthorized))}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    ids = Enum.reject(socket.assigns.batch.recipient_ids, &(&1 == id))

    if ids != [],
      do: {:noreply, save_template(socket, %{"recipient_ids" => ids})},
      else: {:noreply, assign(socket, error: error_message(:batch_size))}
  end

  def handle_event("template", %{"template" => attrs}, socket),
    do: {:noreply, save_template(socket, attrs)}

  def handle_event("generate", %{"template" => attrs}, socket),
    do: {:noreply, socket |> save_template(attrs) |> generate()}

  def handle_event("generate", _, socket), do: {:noreply, generate(socket)}

  def handle_event("edit-draft", %{"draft" => attrs}, socket),
    do:
      {:noreply,
       assign(socket, draft_form: to_form(attrs, as: "draft"), status: gettext("Unsaved changes"))}

  def handle_event("save-draft", %{"draft" => attrs}, socket) do
    socket = assign(socket, draft_form: to_form(attrs, as: "draft"))

    case Mail.save_draft(socket.assigns.current_scope, socket.assigns.draft, attrs) do
      {:ok, draft} ->
        {:noreply,
         assign(socket,
           draft: draft,
           draft_form:
             to_form(%{"subject" => draft.subject, "source" => draft.source}, as: "draft"),
           error: nil,
           status: gettext("Saved")
         )}

      {:error, error} ->
        {:noreply,
         assign(socket, error: error_message(error), status: gettext("Unsaved changes"))}
    end
  end

  defp start_batch(socket, id) do
    case Mail.create(socket.assigns.current_scope, id) do
      {:ok, batch} ->
        {:noreply,
         push_navigate(socket, to: ~p"/manage/mail/#{batch.id}?locale=#{socket.assigns.locale}")}

      _ ->
        {:noreply, assign(socket, error: error_message(:unauthorized))}
    end
  end

  @impl true
  def handle_info({:markdown_editor_changed, "mail-template", source}, socket) do
    {:noreply, save_template(socket, %{"source" => source})}
  end

  def handle_info({:markdown_editor_changed, "mail-draft", source}, socket) do
    values = Map.put(socket.assigns.draft_form.params, "source", source)

    {:noreply,
     assign(socket, draft_form: to_form(values, as: "draft"), status: gettext("Unsaved changes"))}
  end

  defp generate(socket) do
    if socket.assigns.error do
      socket
    else
      case Mail.generate(socket.assigns.current_scope, socket.assigns.batch.id) do
        {:ok, _} ->
          {:ok, drafts} = Mail.drafts(socket.assigns.current_scope, socket.assigns.batch.id)
          assign(socket, drafts: drafts, error: nil, status: gettext("Drafts saved"))

        {:error, error} ->
          assign(socket, error: error_message(error))
      end
    end
  end

  defp save_template(socket, attrs) do
    values = Map.merge(socket.assigns.form.params, attrs)
    socket = assign(socket, form: to_form(values, as: "template"))
    # Parent and component change events can report the same source. Avoid redundant revisions.
    changes? =
      Enum.any?(attrs, fn {key, value} ->
        Map.get(Map.from_struct(socket.assigns.batch), existing_key(key)) != value
      end)

    result =
      if changes?,
        do: Mail.save_batch(socket.assigns.current_scope, socket.assigns.batch, attrs),
        else: unchanged_batch(socket)

    case result do
      {:ok, batch} ->
        recipients =
          Enum.map(batch.recipient_ids, fn id ->
            {:ok, contact} = Mail.recipient(socket.assigns.current_scope, id)
            contact
          end)

        assign(socket, batch: batch, recipients: recipients, error: nil, status: gettext("Saved"))

      {:error, error} ->
        assign(socket, error: error_message(error), status: gettext("Unsaved changes"))
    end
  end

  defp unchanged_batch(socket) do
    case Mail.get(socket.assigns.current_scope, socket.assigns.batch.id) do
      {:ok, batch} when batch.revision == socket.assigns.batch.revision -> {:ok, batch}
      {:ok, _} -> {:error, :stale}
      error -> error
    end
  end

  defp existing_key("subject"), do: :subject
  defp existing_key("source"), do: :source
  defp existing_key("recipient_ids"), do: :recipient_ids
  defp existing_key(_), do: nil

  defp load_batch(socket, batch) do
    {:ok, drafts} = Mail.drafts(socket.assigns.current_scope, batch.id)

    recipients =
      Enum.map(batch.recipient_ids, fn id ->
        {:ok, contact} = Mail.recipient(socket.assigns.current_scope, id)
        contact
      end)

    assign(socket,
      batch: batch,
      anchor: nil,
      recipients: recipients,
      drafts: drafts,
      form: to_form(%{"subject" => batch.subject, "source" => batch.source}, as: "template"),
      error: nil,
      status: gettext("Saved")
    )
  end

  defp denied(socket),
    do:
      socket
      |> put_flash(:error, gettext("Draft or account unavailable."))
      |> push_navigate(to: ~p"/manage/accounts?locale=#{socket.assigns.locale}")

  defp error_message({:missing_variables, missing}),
    do: gettext("Resolve missing variables: %{variables}", variables: Enum.join(missing, ", "))

  defp error_message(:batch_size), do: gettext("Choose one to five eligible recipients.")

  defp error_message(:stale),
    do: gettext("This draft changed in another session. Reload before saving.")

  defp error_message(%Ecto.Changeset{}),
    do: gettext("Enter a subject and message within the allowed length.")

  defp error_message(_),
    do: gettext("Current account access or recipient eligibility no longer allows this change.")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.management
      active_tab="mail"
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
    >
      <main class="mx-auto max-w-5xl px-5 py-10 crm-surface">
        <.link
          :if={@batch}
          navigate={~p"/manage/accounts/#{@batch.anchor_user_id}?locale=#{@locale}"}
          class="mb-4 inline-block underline"
        >{gettext("Account and Brevo history")}</.link>
        <h1 class="text-3xl font-bold mb-6">{gettext("Emails")}</h1>
        <p>
          {gettext(
            "Templates save automatically. Individual edits save with Save draft. Drafting does not send email."
          )}
        </p>
        <p :if={@error} id="mail-error" role="alert" class="crm-error">{@error}</p>
        <p :if={@status} id="mail-save-status" role="status" aria-live="polite">{@status}</p>
        <nav aria-label={gettext("Emails")} class="my-5 flex gap-5 border-b border-stone-300 pb-3">
          <.link navigate={~p"/manage/mail?locale=#{@locale}"} aria-current="page" class="font-bold">{gettext(
            "Member emails"
          )}</.link>
          <.link
            :if={Volunteers.superadmin?(@current_scope)}
            navigate={~p"/manage/mail/newsletters?locale=#{@locale}"}
            class="underline"
          >{gettext("Newsletters")}</.link>
        </nav>
        <section :if={@anchor} class="mt-6">
          <p>{@anchor.name} · {@anchor.email}</p><button
            type="button"
            phx-click="start"
            phx-disable-with={gettext("Start draft")}
            class="crm-button"
          >{gettext("Start draft")}</button>
        </section>
        <section
          :if={@live_action == :index and is_nil(@batch) and is_nil(@anchor)}
          id="mail-batches"
          class="mt-6"
        >
          <.link
            id="mail-new-draft"
            navigate={~p"/manage/mail/new?locale=#{@locale}"}
            class="crm-button"
          >{gettext("New draft")}</.link>
          <p :if={@batches == []} class="mt-3 text-stone-600">
            {gettext("No drafts yet. Choose New draft to begin.")}
          </p>
          <ul>
            <li :for={batch <- @batches}>
              <.link navigate={~p"/manage/mail/#{batch.id}?locale=#{@locale}"}>{if batch.subject == "",
                do: gettext("Untitled draft"),
                else: batch.subject}</.link>
            </li>
          </ul>
        </section>
        <section
          :if={@live_action == :new and is_nil(@anchor) and is_nil(@batch)}
          id="mail-new"
          class="mt-6"
        >
          <h2 class="text-xl font-bold">{gettext("New draft")}</h2>
          <p>
            {gettext(
              "Choose an eligible account to start. You can add up to five recipients in the draft."
            )}
          </p>
          <.form
            id="mail-new-search-form"
            for={to_form(%{"query" => @query})}
            phx-change="search"
            phx-submit="search"
          >
            <.input
              type="search"
              id="mail-new-contact-search"
              name="query"
              value={@query}
              label={gettext("Find an eligible account")}
              phx-debounce="250"
            />
          </.form>
          <ul>
            <li :for={contact <- @results} class="flex flex-wrap items-center gap-4 py-3">
              <span>{contact.name} · {contact.email}</span>
              <button
                type="button"
                phx-click="start-account"
                phx-disable-with={gettext("Start draft")}
                phx-value-id={contact.id}
                class="crm-button"
              >{gettext("Start draft")}</button>
            </li>
          </ul>
          <p :if={@results == []} role="status">{gettext("No eligible accounts found.")}</p>
          <.link navigate={~p"/manage/mail?locale=#{@locale}"} class="underline">{gettext("Cancel")}</.link>
        </section>
        <section :if={@batch} id="mail-workspace" class="mt-6 space-y-8">
          <section id="mail-recipients">
            <h2 class="text-xl font-bold">{gettext("Recipients")}</h2><ul>
              <li :for={contact <- @recipients} class="flex flex-wrap gap-4 items-center py-3">
                <span>{contact.name} · {contact.email}</span><button
                  type="button"
                  phx-click="remove"
                  phx-value-id={contact.id}
                  class="crm-button"
                >{gettext("Remove")}</button>
              </li>
            </ul>
            <.form
              id="mail-recipient-search-form"
              for={to_form(%{"query" => @query})}
              phx-change="search"
              phx-submit="search"
            >
              <.input
                type="search"
                id="mail-contact-search"
                name="query"
                value={@query}
                label={gettext("Find an eligible account")}
                phx-debounce="250"
              />
            </.form>
            <ul>
              <li :for={contact <- @results} class="flex flex-wrap gap-4 items-center py-3">
                <span>{contact.name} · {contact.email}</span><button
                  type="button"
                  phx-click="choose"
                  phx-value-id={contact.id}
                  class="crm-button"
                >{gettext("Add recipient")}</button>
              </li>
            </ul>
          </section>
          <.form
            for={@form}
            id="mail-template-form"
            phx-change="template"
            phx-submit="generate"
            class="space-y-4"
          >
            <h2 class="text-xl font-bold">{gettext("Template")}</h2><p>
              {gettext("Available variables: {{name}}, {{email}}, {{city}}.")}
            </p>
            <.input field={@form[:subject]} label={gettext("Subject template")} phx-debounce="250" />
            <.live_component
              module={PhoenixMarkdownEditor.Component}
              id="mail-template"
              source={@form[:source].value || ""}
              name="template[source]"
              label={gettext("Message template · Markdown")}
              preview_label={gettext("Preview ↗")}
              preview_title={gettext("Template preview")}
              popup_blocked_message={gettext("Allow the preview window, then try again.")}
              preview_open_message={gettext("Preview opened")}
              preview_updated_message={gettext("Preview updated")}
              disconnected_message={gettext("Connection interrupted; text retained in this page.")}
              preview_error_message={gettext("Preview unavailable. Your text is retained.")}
              render_preview={&Render.html/1}
            />
            <button class="crm-button" phx-disable-with={gettext("Generating…")}>{gettext(
              "Generate drafts"
            )}</button>
          </.form>
          <section id="mail-drafts">
            <h2 class="text-xl font-bold">{gettext("Recipient drafts")}</h2><ul>
              <li :for={draft <- @drafts} class="py-3 flex flex-wrap gap-4">
                <span>{draft.name} · {draft.subject}</span><.link patch={
                  ~p"/manage/mail/#{@batch.id}?#{%{locale: @locale, draft: draft.id}}"
                }>{gettext("Edit draft")}</.link>
              </li>
            </ul>
          </section>
          <.form
            :if={@draft}
            for={@draft_form}
            id="mail-draft-form"
            phx-change="edit-draft"
            phx-submit="save-draft"
            class="space-y-4"
          >
            <h2 class="text-xl font-bold">{@draft.email}</h2><.input
              field={@draft_form[:subject]}
              label={gettext("Subject")}
            />
            <.live_component
              module={PhoenixMarkdownEditor.Component}
              id="mail-draft"
              source={@draft_form[:source].value || ""}
              name="draft[source]"
              label={gettext("Message · Markdown")}
              preview_label={gettext("Preview ↗")}
              preview_title={@draft_form[:subject].value}
              popup_blocked_message={gettext("Allow the preview window, then try again.")}
              preview_open_message={gettext("Preview opened")}
              preview_updated_message={gettext("Preview updated")}
              disconnected_message={gettext("Connection interrupted; text retained in this page.")}
              preview_error_message={gettext("Preview unavailable. Your text is retained.")}
              render_preview={&Render.html/1}
            />
            <button class="crm-button" phx-disable-with={gettext("Saving…")}>{gettext("Save draft")}</button>
          </.form>
        </section>
      </main>
    </Layouts.management>
    """
  end
end
