defmodule PauseAiCaWeb.NewsletterDraftLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Newsletters.{Draft, Drafts}

  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    case Drafts.get(socket.assigns.current_scope, params["id"]) do
      {:ok, draft} ->
        {:ok,
         assign(socket,
           locale: locale,
           page_title: gettext("Newsletter draft"),
           draft: draft,
           form: to_form(Draft.changeset(draft, %{}), as: "draft"),
           status: nil,
           error: nil
         )}

      _ ->
        {:ok, denied(socket)}
    end
  end

  def handle_event("edit", %{"draft" => attrs}, socket), do: {:noreply, edit(socket, attrs)}

  def handle_event("save", %{"draft" => attrs}, socket) do
    if PauseAiCa.Volunteers.superadmin?(socket.assigns.current_scope),
      do: save(socket, attrs),
      else: {:noreply, denied(socket)}
  end

  def handle_event("archive", _, socket), do: archive(socket, true)
  def handle_event("restore", _, socket), do: archive(socket, false)

  defp save(socket, attrs) do
    socket = edit(socket, attrs)

    case Drafts.save(socket.assigns.current_scope, socket.assigns.draft, attrs) do
      {:ok, draft} ->
        {:noreply,
         assign(socket,
           draft: draft,
           form: to_form(Draft.changeset(draft, %{}), as: "draft"),
           status: gettext("Saved"),
           error: nil
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "draft"))}

      {:error, :stale} ->
        {:noreply,
         assign(socket,
           error:
             gettext(
               "This draft changed in another tab. Your text is retained here. Copy it before reloading the saved version."
             )
         )}

      _ ->
        {:noreply, denied(socket)}
    end
  end

  def handle_info({:markdown_editor_changed, "newsletter-content", source}, socket) do
    {:noreply, edit(socket, Map.put(socket.assigns.form.params || %{}, "source", source))}
  end

  defp edit(socket, attrs) do
    if PauseAiCa.Volunteers.superadmin?(socket.assigns.current_scope) do
      changeset = Draft.changeset(socket.assigns.draft, attrs)

      assign(socket,
        form: to_form(%{changeset | action: :validate}, as: "draft"),
        status: gettext("Unsaved changes"),
        error: nil
      )
    else
      denied(socket)
    end
  end

  defp archive(socket, archive?) do
    if socket.assigns.status == gettext("Unsaved changes") do
      {:noreply, assign(socket, error: gettext("Save your changes before archiving this draft."))}
    else
      archive_saved(socket, archive?)
    end
  end

  defp archive_saved(socket, archive?) do
    case Drafts.archive(socket.assigns.current_scope, socket.assigns.draft, archive?) do
      {:ok, draft} ->
        {:noreply, assign(socket, draft: draft, status: gettext("Saved"), error: nil)}

      {:error, :stale} ->
        {:noreply,
         assign(socket,
           error:
             gettext(
               "This draft changed in another tab. Reload before archiving or restoring it."
             )
         )}

      _ ->
        {:noreply, denied(socket)}
    end
  end

  defp denied(socket),
    do:
      socket
      |> assign(draft: nil)
      |> put_flash(:error, gettext("Superadmin access required."))
      |> redirect(to: ~p"/dashboard")

  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="mail"
    >
      <section :if={@draft} id="newsletter-draft" class="mx-auto max-w-5xl px-5 py-8">
        <.link navigate={~p"/manage/mail/newsletters?locale=#{@locale}"} class="underline">{gettext(
          "Newsletters"
        )}</.link>
        <h1 class="mt-5 text-3xl font-bold">{gettext("Newsletter draft")}</h1>
        <p class="mt-3">
          {gettext(
            "Saving a draft does not approve or send it. Eligibility is checked from current consent when a batch is prepared."
          )}
        </p>
        <p :if={@status} id="newsletter-save-status" role="status" class="mt-3">{@status}</p>
        <p :if={@error} id="newsletter-draft-error" role="alert" class="mt-3 crm-error">{@error}</p>
        <.form
          :if={is_nil(@draft.archived_at)}
          for={@form}
          id="newsletter-draft-form"
          phx-change="edit"
          phx-submit="save"
          class="mt-6 space-y-5"
        >
          <.input field={@form[:subject]} label={gettext("Subject")} />
          <.input
            field={@form[:region]}
            type="select"
            label={gettext("Audience geography")}
            options={[
              {gettext("All regions"), ""},
              {"Montréal", "Montréal"},
              {"ROQuébec", "ROQuébec"},
              {"ROCanada", "ROCanada"}
            ]}
          />
          <.live_component
            module={PhoenixMarkdownEditor.Component}
            id="newsletter-content"
            source={@form[:source].value || ""}
            name="draft[source]"
            label={gettext("Message · Markdown")}
            preview_label={gettext("Preview ↗")}
            preview_title={gettext("Newsletter preview")}
            popup_blocked_message={gettext("Allow the preview window, then try again.")}
            preview_open_message={gettext("Preview opened")}
            preview_updated_message={gettext("Preview updated")}
            disconnected_message={gettext("Connection interrupted; text retained in this page.")}
            preview_error_message={gettext("Preview unavailable. Your text is retained.")}
            render_preview={&PauseAiCa.Mail.Render.html/1}
          />
          <button type="submit" class="crm-button" phx-disable-with={gettext("Saving…")}>{gettext(
            "Save"
          )}</button>
        </.form>
        <p :if={@draft.archived_at} class="mt-5">{gettext("Archived draft")}</p>
        <button
          :if={is_nil(@draft.archived_at)}
          type="button"
          class="mt-6 underline"
          phx-click="archive"
        >{gettext("Archive")}</button>
        <button :if={@draft.archived_at} type="button" class="mt-6 crm-button" phx-click="restore">{gettext(
          "Restore"
        )}</button>
      </section>
    </Layouts.management>
    """
  end
end
