defmodule PauseAiCaWeb.NewsletterDraftLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Newsletters.{Draft, Drafts, Batches}

  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    case Drafts.get(socket.assigns.current_scope, params["id"]) do
      {:ok, draft} ->
        {:ok,
         assign(socket,
           locale: locale,
           connected: connected?(socket),
           page_title: gettext("Newsletter draft"),
           draft: draft,
           form: to_form(Draft.changeset(draft, %{}), as: "draft"),
           status: nil,
           error: nil,
           audience: nil,
           candidate_page: 1,
           candidate_q: "",
           reviewed: false,
           delivery_state: :idle,
           batch_review: nil,
           batches: [],
           quota: nil
         )}

      _ ->
        {:ok, denied(socket)}
    end
  end

  def handle_params(_, _, socket), do: {:noreply, refresh_audience(socket)}

  def handle_event("edit", %{"draft" => attrs}, socket), do: {:noreply, edit(socket, attrs)}

  def handle_event("save", %{"draft" => attrs}, socket) do
    if PauseAiCa.Volunteers.superadmin?(socket.assigns.current_scope),
      do: save(socket, attrs),
      else: {:noreply, denied(socket)}
  end

  def handle_event("archive", _, socket), do: archive(socket, true)
  def handle_event("restore", _, socket), do: archive(socket, false)

  def handle_event("candidate-page", %{"page" => page}, socket) do
    page =
      case Integer.parse(page) do
        {n, ""} when n > 0 -> n
        _ -> 1
      end

    {:noreply, socket |> assign(candidate_page: page) |> refresh_audience()}
  end

  def handle_event("select-visible", _, socket) do
    keys =
      selected(socket) ++
        Enum.map(Enum.filter(socket.assigns.audience.rows, &(&1.status == :available)), & &1.id)

    attrs = Map.put(socket.assigns.form.params || %{}, "recipient_keys", Enum.uniq(keys))
    {:noreply, edit(socket, attrs)}
  end

  def handle_event("clear-recipients", _, socket) do
    {:noreply, edit(socket, Map.put(socket.assigns.form.params || %{}, "recipient_keys", []))}
  end

  def handle_event("prepare-batch", %{"review" => review}, socket) do
    if dirty?(socket) do
      {:noreply,
       assign(socket,
         error: gettext("Save your content and recipient selection before preparing a batch.")
       )}
    else
      draft = socket.assigns.draft

      case Batches.prepare(
             socket.assigns.current_scope,
             draft,
             draft.recipient_mode,
             draft.recipient_keys,
             review["eligible"] == "true"
           ) do
        {:ok, batch} -> {:noreply, socket |> show_batch(batch.id) |> assign(error: nil)}
        {:error, reason} -> {:noreply, assign(socket, error: batch_error(reason))}
      end
    end
  end

  def handle_event("review-batch", %{"id" => id}, socket), do: {:noreply, show_batch(socket, id)}

  def handle_event("approve-batch", _, socket) do
    if dirty?(socket),
      do: {:noreply, assign(socket, error: batch_error(:stale))},
      else: batch_action(socket, &Batches.approve/2)
  end

  def handle_event("pause-batch", _, socket), do: batch_action(socket, &Batches.pause/2)

  def handle_event("send-batch", _, socket) do
    scope = socket.assigns.current_scope

    if dirty?(socket) or socket.assigns.delivery_state == :sending do
      {:noreply, assign(socket, error: batch_error(:stale))}
    else
      with %{batch: %{id: id}} <- socket.assigns.batch_review,
           {:ok, %{batch: batch}} <- Batches.get(scope, id),
           true <- batch.state in ["approved", "sending"] do
        Process.send_after(self(), :batch_progress, 500)

        {:noreply,
         socket
         |> assign(delivery_state: :sending, error: nil)
         |> start_async(:send_batch, fn -> Batches.dispatch(scope, id) end)}
      else
        _ -> {:noreply, assign(socket, error: batch_error(:not_approved))}
      end
    end
  end

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
         )
         |> refresh_audience()}

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

  def handle_info(:batch_progress, socket) do
    socket =
      if socket.assigns.batch_review,
        do: show_batch(socket, socket.assigns.batch_review.batch.id),
        else: socket

    if socket.assigns.delivery_state == :sending,
      do: Process.send_after(self(), :batch_progress, 500)

    {:noreply, socket}
  end

  defp edit(socket, attrs) do
    if PauseAiCa.Volunteers.superadmin?(socket.assigns.current_scope) do
      mode_changed? =
        attrs["recipient_mode"] &&
          attrs["recipient_mode"] != socket.assigns.form[:recipient_mode].value

      attrs = if mode_changed?, do: Map.put(attrs, "recipient_keys", []), else: attrs
      socket = if mode_changed?, do: assign(socket, candidate_page: 1), else: socket
      changeset = Draft.changeset(socket.assigns.draft, attrs)
      socket = assign(socket, candidate_q: attrs["candidate_q"] || socket.assigns.candidate_q)

      assign(socket,
        form: to_form(%{changeset | action: :validate}, as: "draft"),
        status: gettext("Unsaved changes"),
        error: nil,
        reviewed: false,
        batch_review: nil
      )
      |> refresh_audience()
    else
      denied(socket)
    end
  end

  def handle_async(:send_batch, {:ok, {:ok, result}}, socket) do
    socket =
      socket |> assign(delivery_state: result) |> show_batch(socket.assigns.batch_review.batch.id)

    {:noreply, socket}
  end

  def handle_async(:send_batch, _, socket),
    do:
      {:noreply,
       assign(socket,
         delivery_state: :failed,
         error: gettext("Delivery stopped. Review the durable receipt before trying again.")
       )}

  defp batch_action(socket, action) do
    case socket.assigns.batch_review do
      %{batch: %{id: id}} ->
        case action.(socket.assigns.current_scope, id) do
          {:ok, _} -> {:noreply, socket |> show_batch(id) |> assign(error: nil)}
          {:error, reason} -> {:noreply, assign(socket, error: batch_error(reason))}
        end

      _ ->
        {:noreply, assign(socket, error: batch_error(:not_approved))}
    end
  end

  defp show_batch(socket, id) do
    case Batches.get(socket.assigns.current_scope, id) do
      {:ok, review} ->
        {:ok, quota} = Batches.quota(socket.assigns.current_scope)

        assign(socket,
          batch_review: review,
          quota: quota,
          delivery_state:
            if(review.batch.state == "completed",
              do: :completed,
              else: socket.assigns.delivery_state
            )
        )

      _ ->
        denied(socket)
    end
  end

  defp refresh_audience(%{assigns: %{draft: nil}} = socket), do: socket

  defp refresh_audience(socket) do
    params = %{
      "page" => to_string(socket.assigns.candidate_page),
      "q" => socket.assigns.candidate_q,
      "region" => socket.assigns.form[:region].value || "",
      "per" => "25"
    }

    mode = socket.assigns.form[:recipient_mode].value || "newsletter"

    case Batches.audience(socket.assigns.current_scope, mode, params) do
      {:ok, page} ->
        {:ok, batches} = Batches.list(socket.assigns.current_scope, socket.assigns.draft.id)
        {:ok, quota} = Batches.quota(socket.assigns.current_scope)
        assign(socket, audience: page, batches: batches, quota: quota)

      _ ->
        denied(socket)
    end
  end

  defp batch_label("review"), do: gettext("Awaiting approval")
  defp batch_label("approved"), do: gettext("Approved")
  defp batch_label("sending"), do: gettext("Sending")
  defp batch_label("completed"), do: gettext("Completed")
  defp batch_label("stale"), do: gettext("Approval expired")
  defp batch_label("paused"), do: gettext("Paused")
  defp delivery_label(:idle), do: gettext("Ready for review")
  defp delivery_label(:completed), do: gettext("Completed")
  defp delivery_label(:sending), do: gettext("Sending")
  defp delivery_label(:throttled), do: gettext("Waiting for hourly allowance")
  defp delivery_label(:stale), do: gettext("Approval expired")
  defp delivery_label(:already_sending), do: gettext("Submission already in progress")
  defp delivery_label(:not_approved), do: gettext("Approval required")
  defp delivery_label(_), do: gettext("Needs delivery review")

  defp receipt_label("accepted", environment) when environment in ["dev", "test"],
    do: gettext("Accepted by local mailbox")

  defp receipt_label("accepted", _), do: gettext("Accepted by provider")
  defp receipt_label("pending", _), do: gettext("Queued")
  defp receipt_label("reserved", _), do: gettext("Submission in progress")
  defp receipt_label("excluded", _), do: gettext("Excluded")
  defp receipt_label("failed", _), do: gettext("Not submitted")
  defp receipt_label("unknown", _), do: gettext("Needs delivery review")
  defp selected(socket), do: socket.assigns.form[:recipient_keys].value || []
  defp dirty?(socket), do: socket.assigns.status == gettext("Unsaved changes")

  defp batch_error(:review_required),
    do: gettext("Confirm that you reviewed outreach eligibility for this batch.")

  defp batch_error(:audience_required), do: gettext("Select at least one available recipient.")

  defp batch_error(:content_required),
    do: gettext("Add a subject and message before preparing a batch.")

  defp batch_error(reason) when reason in [:stale, :audience_changed],
    do: gettext("Content or audience changed. Save and prepare a new batch for approval.")

  defp batch_error(:ineligible),
    do:
      gettext(
        "Selected recipients include a withdrawal or blocked address. Review the selection."
      )

  defp batch_error(:reconciliation_required),
    do: gettext("A submission needs provider reconciliation before this batch can resume.")

  defp batch_error(:not_approved), do: gettext("Approve the reviewed batch before sending.")
  defp batch_error(_), do: gettext("This operation is unavailable. Your saved draft is retained.")

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
      <section :if={@draft} id="newsletter-draft" class="crm-surface mx-auto max-w-5xl px-5 py-8">
        <fieldset disabled={!@connected} class="contents">
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
            <section :if={@audience} id="newsletter-recipient-picker" class="space-y-4">
              <h2 class="text-xl font-semibold">{gettext("Recipients")}</h2>
              <.input
                field={@form[:recipient_mode]}
                type="select"
                label={gettext("Audience source")}
                options={[
                  {gettext("Confirmed newsletter subscribers"), "newsletter"},
                  {gettext("Contacts · manual review"), "contacts"}
                ]}
              />
              <.input name="draft[candidate_q]" value={@candidate_q} label={gettext("Find contacts")} />
              <div class="flex flex-wrap gap-4 items-center">
                <button type="button" class="crm-button" phx-click="select-visible">{gettext(
                  "Select visible available recipients"
                )}</button>
                <button type="button" class="underline" phx-click="clear-recipients">{gettext(
                  "Clear selection"
                )}</button>
                <span id="newsletter-selected-count">{gettext("%{count} selected",
                  count: length(@form[:recipient_keys].value || [])
                )}</span>
              </div>
              <input type="hidden" name="draft[recipient_keys][]" value="" />
              <input
                :for={
                  key <- (@form[:recipient_keys].value || []) -- Enum.map(@audience.rows, & &1.id)
                }
                type="hidden"
                name="draft[recipient_keys][]"
                value={key}
              />
              <ul class="space-y-2">
                <li :for={row <- @audience.rows} class="border border-stone-300 rounded-lg p-3">
                  <label class="flex gap-3 items-start">
                    <input
                      type="checkbox"
                      name="draft[recipient_keys][]"
                      value={row.id}
                      checked={row.id in (@form[:recipient_keys].value || [])}
                      disabled={
                        row.status != :available and
                          row.id not in (@form[:recipient_keys].value || [])
                      }
                      aria-label={gettext("Select %{email}", email: row.email || row.name)}
                    />
                    <span><strong class="break-all">{row.email || row.name}</strong><span
                      :if={row.name != ""}
                      class="block text-sm"
                    >{row.name}</span><span :if={row.status != :available} class="block text-sm">{gettext(
                      "Excluded: withdrawal, blocked address or missing preferred email."
                    )}</span></span>
                  </label>
                  <PauseAiCaWeb.ContactSourceComponents.source_summary
                    :for={origin <- Map.get(row, :origins, [])}
                    id={"blast-source-#{origin.id}"}
                    data={origin.source_data}
                  />
                </li>
              </ul>
              <nav aria-label={gettext("Pagination")} class="flex gap-4 items-center">
                <button
                  :if={@audience.page > 1}
                  type="button"
                  phx-click="candidate-page"
                  phx-value-page={@audience.page - 1}
                  class="underline"
                >{gettext("Previous")}</button>
                <span>{gettext("Page %{page} of %{pages}",
                  page: @audience.page,
                  pages: @audience.pages
                )}</span>
                <button
                  :if={@audience.page < @audience.pages}
                  type="button"
                  phx-click="candidate-page"
                  phx-value-page={@audience.page + 1}
                  class="underline"
                >{gettext("Next")}</button>
              </nav>
            </section>
            <button type="submit" class="crm-button" phx-disable-with={gettext("Saving…")}>{gettext(
              "Save"
            )}</button>
          </.form>
          <section
            :if={is_nil(@draft.archived_at)}
            id="newsletter-batch-workspace"
            class="mt-10 space-y-5 border-t border-stone-300 pt-6"
          >
            <h2 class="text-xl font-semibold">{gettext("Review and send")}</h2>
            <p :if={@quota}>
              {gettext(
                "Available this hour: %{personal} for your authorizations, %{global} across the application.",
                personal: @quota.personal_remaining,
                global: @quota.global_remaining
              )}
            </p>
            <p>
              {gettext(
                "Delivery limits: 20 messages/hour per authorizing admin, 100/hour globally. Unsure submissions are held for review, never retried automatically."
              )}
            </p>
            <p :if={PauseAiCa.MailSafety.environment() == :staging} class="crm-error">
              {gettext("Staging rehearsal: every message goes only to the authorizing admin.")}
            </p>
            <.form for={%{}} as={:review} id="newsletter-prepare-form" phx-submit="prepare-batch">
              <input type="hidden" name="review[eligible]" value="false" />
              <label class="flex gap-3 my-3"><input
                type="checkbox"
                name="review[eligible]"
                value="true"
              /><span>{gettext(
                "I reviewed the selected contacts' eligibility for this communication. This does not grant newsletter consent."
              )}</span></label>
              <button type="submit" class="crm-button" phx-disable-with={gettext("Preparing…")}>{gettext(
                "Prepare batch"
              )}</button>
            </.form>
            <ul class="flex flex-wrap gap-4">
              <li :for={batch <- @batches}>
                <button
                  type="button"
                  phx-click="review-batch"
                  phx-value-id={batch.id}
                  class="underline"
                >{batch.subject} · {length(batch.recipient_keys)} · {batch_label(batch.state)}</button>
              </li>
            </ul>
            <section :if={@batch_review} id="newsletter-batch-review" class="space-y-4">
              <h3 class="font-semibold">{gettext("Frozen batch snapshot")}</h3>
              <p>
                {gettext("Saved draft version %{version}",
                  version: @batch_review.batch.draft_revision
                )}
              </p>
              <p>
                {@batch_review.batch.subject} · {length(@batch_review.deliveries)} · {batch_label(
                  @batch_review.batch.state
                )}
              </p>
              <p>
                {@batch_review.batch.sender_name} · {@batch_review.batch.sender_email} · {@batch_review.batch.delivery_environment}
              </p>
              <p>{gettext("Authorizing admin: %{email}", email: @current_scope.user.email)}</p>
              <div class="prose max-w-none">
                {Phoenix.HTML.raw(PauseAiCa.Mail.Render.html(@batch_review.batch.source))}
              </div>
              <p>
                {gettext(
                  "Each recipient gets a personal Manage my subscription link. Approval applies only to this saved content and recipient snapshot."
                )}
              </p>
              <div class="flex flex-wrap gap-4">
                <button
                  :if={@batch_review.batch.state in ["review", "paused"]}
                  type="button"
                  class="crm-button"
                  phx-click="approve-batch"
                >{gettext("Approve batch")}</button>
                <button
                  :if={@batch_review.batch.state in ["approved", "sending"]}
                  type="button"
                  class="crm-button"
                  phx-click="send-batch"
                  disabled={@delivery_state == :sending}
                >{gettext("Send")}</button>
                <button
                  :if={@batch_review.batch.state in ["approved", "sending"]}
                  type="button"
                  class="underline"
                  phx-click="pause-batch"
                >{gettext("Pause batch")}</button>
              </div>
              <p id="newsletter-delivery-progress" role="status">
                {Enum.count(@batch_review.deliveries, &(&1.state == "accepted"))} / {length(
                  @batch_review.deliveries
                )} · {delivery_label(@delivery_state)}
              </p>
              <p :if={@delivery_state == :throttled}>
                {gettext(
                  "Hourly limit reached. Remaining recipients are retained for a later resume."
                )}
              </p>
              <p :if={PauseAiCa.MailSafety.environment() == :dev}>
                <.link href="/dev/mailbox" class="underline">{gettext("Open development mailbox")}</.link>
              </p>
              <ul id="newsletter-batch-receipt" class="space-y-2">
                <li :for={delivery <- @batch_review.deliveries} class="break-all">
                  {delivery.email} · {receipt_label(
                    delivery.state,
                    @batch_review.batch.delivery_environment
                  )}<span :if={delivery.provider_id not in [nil, ""]}> · {if @batch_review.batch.delivery_environment in [
                                                                               "dev",
                                                                               "test"
                                                                             ],
                                                                             do:
                                                                               gettext(
                                                                                 "Local mailbox"
                                                                               ),
                                                                             else: gettext("Brevo")} {delivery.provider_id}</span><span :if={
                    delivery.error
                  }> · {delivery.error}</span>
                </li>
              </ul>
              <p>
                {gettext("Provider acceptance is separate from delivery to the recipient's mailbox.")}
              </p>
            </section>
          </section>
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
        </fieldset>
      </section>
    </Layouts.management>
    """
  end
end
