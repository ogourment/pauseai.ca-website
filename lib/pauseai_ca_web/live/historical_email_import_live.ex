defmodule PauseAiCaWeb.HistoricalEmailImportLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Outreach.{HistoricalImport, Mailboxes}

  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if PauseAiCa.Volunteers.superadmin?(socket.assigns.current_scope) do
      {:ok, boxes} = Mailboxes.all(socket.assigns.current_scope)

      attrs = %{
        "mailbox_ref" =>
          case List.first(boxes) do
            nil -> ""
            box -> box.id
          end,
        "context" => "",
        "source_kind" => "file",
        "original_source" => ""
      }

      {:ok,
       socket
       |> assign(
         locale: locale,
         page_title: gettext("Import an existing email"),
         mailboxes: boxes,
         form: to_form(attrs, as: "import"),
         attrs: attrs,
         preview: nil,
         raw: nil,
         error: nil,
         saved: nil,
         connected: connected?(socket)
       )
       |> allow_upload(:email,
         accept: ~w(.eml .txt),
         max_entries: 1,
         max_file_size: 5_000_000
       )}
    else
      {:ok, redirect(socket, to: ~p"/manage/mail/inbox?locale=#{locale}")}
    end
  end

  def handle_event("validate", %{"import" => attrs}, socket) do
    socket = reset_source_input(socket, attrs)

    {:noreply,
     assign(socket,
       attrs: attrs,
       raw: socket.assigns.raw,
       form: to_form(attrs, as: "import"),
       preview: nil,
       saved: nil,
       error: nil
     )}
  end

  def handle_event("preview", %{"import" => attrs}, socket) do
    with {:ok, raw} <- preview_source(socket, attrs),
         {:ok, preview} <-
           HistoricalImport.preview(socket.assigns.current_scope, attrs["mailbox_ref"], raw) do
      {:noreply,
       assign(socket,
         raw: raw,
         preview: preview,
         attrs: attrs,
         form: to_form(attrs, as: "import"),
         error: nil
       )}
    else
      {:error, :uploading} ->
        {:noreply, assign(socket, preview: nil, error: gettext("Your file is still uploading."))}

      {:error, _} ->
        {:noreply,
         assign(socket,
           error:
             gettext(
               "Provide complete original message source up to 5 MB, including sender, recipients, Date and Message-ID."
             )
         )}
    end
  end

  def handle_event(
        "confirm",
        %{"confirmation" => %{"reviewed" => "true"}},
        %{assigns: %{preview: preview}} = socket
      )
      when not is_nil(preview) do
    case HistoricalImport.confirm(
           socket.assigns.current_scope,
           socket.assigns.attrs["mailbox_ref"],
           socket.assigns.raw,
           preview.match_fingerprint,
           socket.assigns.attrs["context"] || ""
         ) do
      {:ok, result} ->
        {:noreply,
         assign(socket,
           saved: result,
           preview: nil,
           raw: nil,
           error: nil,
           attrs: Map.put(socket.assigns.attrs, "original_source", "")
         )}

      {:error, :identity_conflict} ->
        {:noreply,
         assign(socket,
           error:
             gettext(
               "This Message-ID is already recorded with different content. Review the existing conversation."
             )
         )}

      {:error, _} ->
        {:noreply,
         assign(socket,
           error:
             gettext(
               "Access or contact matches changed. Preview the email again before importing."
             ),
           preview: nil
         )}
    end
  end

  def handle_event("confirm", _, socket),
    do:
      {:noreply,
       assign(socket,
         error: gettext("Confirm that you reviewed the message and recipient matches.")
       )}

  def handle_event("cancel-upload", %{"ref" => ref}, socket),
    do: {:noreply, assign(cancel_upload(socket, :email, ref), raw: nil, preview: nil)}

  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="mail"
      breadcrumb_context={
        PauseAiCaWeb.Navigation.mail_breadcrumb_context(@current_scope, @locale, false)
      }
    >
      <section id="historical-email-import" class="crm-surface mx-auto max-w-4xl px-5 py-8 space-y-5">
        <.link navigate={~p"/manage/mail/inbox?locale=#{@locale}"} class="underline">{gettext(
          "Back to Emails"
        )}</.link>
        <PauseAiCaWeb.MailNavigation.tabs
          current_scope={@current_scope}
          locale={@locale}
          active="import"
        />
        <h1 class="text-3xl font-bold">{gettext("Import an existing email")}</h1>
        <p>
          {gettext(
            "Record an earlier sent or received email and connect its participants to existing CRM contacts."
          )}
        </p>
        <p>
          {gettext(
            "Historical imports preserve the original sender and recipients. They create no contacts or subscriptions and send no email or notifications."
          )}
        </p>
        <details id="email-source-help" class="crm-panel space-y-3" open>
          <summary class="font-bold">{gettext("How do I get the original email?")}</summary>
          <details open>
            <summary class="font-bold">{gettext("Gmail on a computer")}</summary>
            <ol class="list-decimal pl-6">
              <li>{gettext("Open the message in Gmail. For a sent email, start in Sent.")}</li>
              <li>
                {gettext("Open the message’s three-dot More menu and choose Download message.")}
              </li>
              <li>{gettext("Upload the downloaded .eml file here, then preview the import.")}</li>
            </ol>
            <a
              href={"https://support.google.com/mail/answer/9261412?hl=" <> @locale}
              target="_blank"
              rel="noopener"
              class="underline"
            >{gettext("Gmail’s download instructions")}</a>
          </details>
          <details>
            <summary class="font-bold">{gettext("Outlook")}</summary>
            <p>
              {gettext(
                "In Outlook on the web, open the message and choose More actions → Download. In new Outlook, choose More actions → Save as. Select EML when a format choice is offered."
              )}
            </p>
            <a
              href="https://support.microsoft.com/en-gb/outlook/mail/save-an-outlook-message-as-a-eml-file-a-pdf-file-or-as-a-draft"
              target="_blank"
              rel="noopener"
              class="underline"
            >{gettext("Outlook’s save instructions")}</a>
          </details>
          <details>
            <summary class="font-bold">{gettext("Proton Mail")}</summary>
            <p>
              {gettext(
                "Open the message, choose the three-dot More menu under the sender details, then Export. Save the email file and upload it here."
              )}
            </p>
            <a
              href="https://proton.me/support/export-import-emails"
              target="_blank"
              rel="noopener"
              class="underline"
            >{gettext("Proton Mail’s export instructions")}</a>
          </details>
          <p>
            {gettext(
              "You can also paste the complete original message source or upload it as a .txt file. Include its headers and body so the CRM can match addresses, preserve the date and recognize repeat imports."
            )}
          </p>
          <p>
            {gettext(
              "For another person’s sent email, ask them for their original export to retain any available Bcc recipients."
            )}
          </p>
        </details>
        <p :if={@error} role="alert" class="crm-error">{@error}</p>
        <%= if @saved do %>
          <section id="email-import-result" role="status" class="crm-panel space-y-3">
            <p>
              {if @saved.duplicate?,
                do: gettext("Already recorded. The existing message was retained."),
                else: gettext("Email recorded.")}
            </p>
            <.link
              navigate={
                ~p"/manage/mail/conversations/#{@saved.message.conversation_id}?locale=#{@locale}"
              }
              class="underline"
            >{gettext("Open conversation")}</.link>
          </section>
        <% else %>
          <.form
            for={@form}
            id="email-import-form"
            phx-change="validate"
            phx-submit="preview"
            class="crm-panel space-y-4"
          >
            <fieldset disabled={!@connected} class="space-y-4">
              <.input
                field={@form[:mailbox_ref]}
                type="select"
                label={gettext("Save to mailbox")}
                options={Enum.map(@mailboxes, &{&1.email, &1.id})}
              />
              <p>
                {gettext(
                  "People with access to this mailbox can read the copy. Sender and recipients come from the original email."
                )}
              </p>
              <.input
                field={@form[:context]}
                label={gettext("Context (optional)")}
                maxlength="200"
                placeholder={gettext("For example, Montréal march outreach")}
              />
              <.input
                field={@form[:source_kind]}
                type="select"
                label={gettext("Import from")}
                options={[
                  {gettext("Email file (.eml or original-source .txt)"), "file"},
                  {gettext("Paste original message source"), "paste"}
                ]}
              />
              <%= if @attrs["source_kind"] == "paste" do %>
                <.input
                  field={@form[:original_source]}
                  type="textarea"
                  rows="10"
                  maxlength="5000000"
                  label={gettext("Complete original message source")}
                  placeholder={
                    gettext("Paste the original headers, a blank line, and the message body.")
                  }
                />
              <% else %>
                <label for={@uploads.email.ref} class="block font-bold">{gettext(
                  "Original email (.eml or .txt, up to 5 MB)"
                )}</label>
                <.live_file_input upload={@uploads.email} />
                <div :for={entry <- @uploads.email.entries}>
                  <span>{entry.client_name} · {entry.progress}%</span>
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-value-ref={entry.ref}
                    class="underline"
                  >{gettext("Remove")}</button>
                  <p :for={_error <- upload_errors(@uploads.email, entry)} role="alert">
                    {gettext("Choose one .eml or original-source .txt file up to 5 MB.")}
                  </p>
                </div>
              <% end %>
              <button
                class="crm-button"
                disabled={
                  @attrs["source_kind"] != "paste" and not file_ready?(@uploads.email.entries, @raw)
                }
                phx-disable-with={gettext("Preparing preview…")}
              >{gettext("Preview import")}</button>
            </fieldset>
          </.form>
          <section :if={@preview} id="email-import-preview" class="crm-panel space-y-4">
            <h2 class="text-xl font-bold">{gettext("Review the import")}</h2>
            <p><strong>{gettext("Subject")}</strong> {@preview.message.envelope["subject"]}</p>
            <p>
              <strong>{gettext("From")}</strong> {@preview.message.envelope["from_name"]} &lt;{@preview.message.envelope[
                "from"
              ]}&gt;
            </p>
            <p>
              <strong>{gettext("Original date")}</strong> {DateTime.to_iso8601(
                @preview.message.occurred_at
              )}
            </p>
            <p><strong>{gettext("Message-ID")}</strong> {@preview.message.rfc_message_id}</p>
            <p :for={key <- ["to", "cc", "bcc"]} class="break-all">
              <strong>{String.upcase(key)}</strong> {Enum.join(@preview.message.envelope[key], ", ")}
            </p>
            <p :if={@preview.existing} class="font-bold">
              {gettext("This Message-ID already exists. Confirmation checks for an exact duplicate.")}
            </p>
            <.link
              :if={@preview.existing}
              navigate={
                ~p"/manage/mail/conversations/#{@preview.existing.conversation_id}?locale=#{@locale}"
              }
              class="underline"
            >{gettext("Open conversation")}</.link>
            <h3 class="font-bold">{gettext("Contact matches")}</h3>
            <ul id="email-import-matches">
              <li :for={row <- @preview.contacts} class="py-2 break-words">
                {row.email} ·
                <%= if row.person_id do %>
                  <.link
                    href={~p"/admin/contacts/#{row.person_id}?locale=#{@locale}"}
                    target="_blank"
                    rel="noopener"
                    class="underline"
                  >{row.name || row.email}</.link>
                <% else %>
                  {gettext("No matching contact. Address retained in the message.")}
                <% end %>
              </li>
            </ul>
            <details>
              <summary>{gettext("Message content")}</summary>
              <pre class="whitespace-pre-wrap break-words">{@preview.message.body_text || @preview.message.body_html}</pre>
            </details>
            <p>
              {gettext(
                "Bcc includes only addresses present in the original file. Delivery and reading status remain unknown."
              )}
            </p>
            <.form
              for={%{}}
              as={:confirmation}
              id="email-import-confirm"
              phx-submit="confirm"
              class="space-y-4"
            >
              <.input
                type="checkbox"
                name="confirmation[reviewed]"
                value="false"
                label={
                  gettext("I reviewed the original message, recipient matches and mailbox access.")
                }
                required
              />
              <button class="crm-button" phx-disable-with={gettext("Recording…")}>{gettext(
                "Confirm import"
              )}</button>
            </.form>
          </section>
        <% end %>
      </section>
    </Layouts.management>
    """
  end

  defp preview_source(_socket, %{"source_kind" => "paste"} = attrs),
    do: {:ok, attrs["original_source"] || ""}

  defp preview_source(socket, _attrs) do
    case uploaded_entries(socket, :email) do
      {[], []} ->
        {:ok, socket.assigns.raw}

      {[_], []} ->
        [raw] =
          consume_uploaded_entries(socket, :email, fn %{path: path}, _ ->
            {:ok, File.read!(path)}
          end)

        {:ok, raw}

      _ ->
        {:error, :uploading}
    end
  end

  defp file_ready?(entries, raw) do
    case entries do
      [] -> is_binary(raw)
      [entry] -> entry.valid? and (entry.progress == 0 or entry.done?)
      _ -> false
    end
  end

  defp reset_source_input(socket, attrs) do
    if attrs["source_kind"] == socket.assigns.attrs["source_kind"] do
      socket
    else
      socket =
        Enum.reduce(socket.assigns.uploads.email.entries, socket, fn entry, current ->
          cancel_upload(current, :email, entry.ref)
        end)

      assign(socket, raw: nil)
    end
  end
end
