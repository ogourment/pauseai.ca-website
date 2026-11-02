defmodule PauseAiCaWeb.OutreachInboxLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Outreach
  alias PhoenixMailWorkflow.OutreachManagement

  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    {:ok,
     assign(socket,
       locale: locale,
       page_title: gettext("Inbox"),
       mailboxes: [],
       processing: [],
       notification_attention: [],
       recovery_status: nil,
       conversations: [],
       conversation: nil,
       messages: [],
       mailbox: nil,
       filters: %{"q" => "", "mailbox_ref" => "", "page" => "1"},
       page: 1,
       more?: false,
       truncated?: false,
       error: nil,
       no_access: false,
       connected: connected?(socket),
       compose_form:
         to_form(%{"mailbox_ref" => "", "email" => "", "subject" => ""}, as: "outreach")
     )}
  end

  def handle_params(params, _, socket) do
    scope = socket.assigns.current_scope

    if params["id"] do
      case Outreach.get(scope, params["id"]) do
        {:ok, result} ->
          {:noreply,
           assign(socket,
             no_access: false,
             conversation: result.conversation,
             mailbox: result.mailbox,
             messages: result.messages,
             truncated?: Map.get(result, :truncated?, false),
             page_title: conversation_subject(result.conversation),
             error: nil
           )}

        _ ->
          {:noreply, denied(socket)}
      end
    else
      filters = Map.take(params, ["q", "mailbox_ref", "page"])
      filters = Map.merge(%{"q" => "", "mailbox_ref" => "", "page" => "1"}, filters)

      case Outreach.list(scope, filters) do
        {:ok, %{mailboxes: []}} ->
          {:noreply, denied(socket)}

        {:ok, result} ->
          {:noreply,
           assign(socket,
             no_access: false,
             conversations: result.conversations,
             page_title: gettext("Inbox"),
             mailboxes: result.mailboxes,
             conversation: nil,
             messages: [],
             filters: filters,
             page: Map.get(result, :page, positive_page(filters["page"])),
             more?: Map.get(result, :page, 1) < Map.get(result, :pages, 1),
             error: nil,
             compose_form:
               to_form(
                 %{
                   "mailbox_ref" => default_mailbox(result.mailboxes, socket.assigns.locale),
                   "email" => "",
                   "subject" => ""
                 },
                 as: "outreach"
               )
           )
           |> attention(result)}

        _ ->
          {:noreply, denied(socket)}
      end
    end
  end

  def handle_event("filter", %{"filters" => filters}, socket) do
    if Outreach.access?(socket.assigns.current_scope) do
      {:noreply,
       push_patch(socket, to: inbox_path(socket.assigns.locale, Map.put(filters, "page", "1")))}
    else
      {:noreply, denied(socket)}
    end
  end

  def handle_event("create-draft", %{"outreach" => attrs}, socket) do
    case Outreach.create_draft(
           socket.assigns.current_scope,
           Map.take(attrs, ["mailbox_ref", "email", "subject"])
         ) do
      {:ok, draft} ->
        {:noreply, open_draft(socket, draft)}

      {:error, :unauthorized} ->
        {:noreply, denied(socket)}

      _ ->
        {:noreply,
         assign(socket,
           compose_form: to_form(attrs, as: "outreach"),
           error: gettext("Choose an available mailbox and enter a valid recipient email.")
         )}
    end
  end

  def handle_event("reply", _, %{assigns: %{conversation: nil}} = socket),
    do: {:noreply, denied(socket)}

  def handle_event("reply", _, socket) do
    case Outreach.reply_draft(socket.assigns.current_scope, socket.assigns.conversation.id) do
      {:ok, draft} ->
        {:noreply, open_draft(socket, draft)}

      {:error, :unauthorized} ->
        {:noreply, denied(socket)}

      _ ->
        {:noreply,
         assign(socket,
           error: gettext("A reply draft is unavailable. The conversation is retained.")
         )}
    end
  end

  def handle_event("retry-receipt", %{"id" => id}, socket) do
    case Outreach.retry_receipt(socket.assigns.current_scope, id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(
           recovery_status: gettext("Incoming message queued for another processing attempt."),
           error: nil
         )
         |> refresh_attention()}

      {:error, :unauthorized} ->
        {:noreply, denied(socket)}

      _ ->
        {:noreply,
         socket
         |> assign(
           error:
             gettext(
               "This incoming message could not be queued. Refresh Inbox status and check the mailbox configuration before trying again."
             )
         )
         |> refresh_attention()}
    end
  end

  def handle_event("refresh-processing", _, socket), do: {:noreply, refresh_attention(socket)}

  defp refresh_attention(socket) do
    case Outreach.list(socket.assigns.current_scope, socket.assigns.filters) do
      {:ok, result} -> attention(socket, result)
      _ -> denied(socket)
    end
  end

  defp attention(socket, result) do
    if PauseAiCa.Volunteers.superadmin?(socket.assigns.current_scope) do
      case Outreach.notification_status(socket.assigns.current_scope) do
        {:ok, rows} ->
          assign(socket,
            processing: Map.get(result, :processing, []),
            notification_attention: Enum.reject(rows, &(&1.state == "accepted"))
          )

        _ ->
          denied(socket)
      end
    else
      assign(socket, processing: [], notification_attention: [])
    end
  end

  defp processing_state("pending"), do: gettext("Queued for processing")
  defp processing_state("failed"), do: gettext("Processing stopped")
  defp processing_state("quarantined"), do: gettext("Mailbox or message needs review")
  defp processing_state(_), do: gettext("Needs review")

  defp notification_state("pending"), do: gettext("Notification queued")
  defp notification_state("reserved"), do: gettext("Notification submission in progress")
  defp notification_state("blocked"), do: gettext("Notification blocked")
  defp notification_state("unassigned"), do: gettext("No authorized notification recipient")
  defp notification_state(_), do: gettext("Notification acceptance needs review")

  defp notification_instruction(state) when state in ["unknown", "reserved"],
    do:
      gettext(
        "Check the provider outcome before any resend. This page does not resend an uncertain notification."
      )

  defp notification_instruction("pending"),
    do:
      gettext(
        "The notification is waiting for the next processing cycle. Refresh Inbox status to check its outcome."
      )

  defp notification_instruction(_),
    do:
      gettext(
        "Check the mailbox owner and administrator access, then review the provider outcome. The incoming conversation remains available in Inbox."
      )

  defp open_draft(socket, draft),
    do:
      push_navigate(socket, to: "/manage/mail/drafts/#{draft.id}?locale=#{socket.assigns.locale}")

  defp denied(socket),
    do:
      assign(socket,
        no_access: true,
        page_title: gettext("Inbox"),
        conversation: nil,
        conversations: [],
        messages: [],
        mailbox: nil,
        mailboxes: [],
        processing: [],
        notification_attention: [],
        error: nil
      )

  defp conversation_subject(conversation) do
    if conversation.subject in [nil, ""],
      do: gettext("Untitled conversation"),
      else: conversation.subject
  end

  defp positive_page(value) do
    case Integer.parse(to_string(value)) do
      {page, ""} when page > 0 and page < 10_000 -> page
      _ -> 1
    end
  end

  defp default_mailbox(mailboxes, locale) do
    case Enum.find(mailboxes, &(&1.locale == locale)) || List.first(mailboxes) do
      nil -> ""
      mailbox -> mailbox.id
    end
  end

  defp inbox_path(locale, filters),
    do: "/manage/mail/inbox?" <> URI.encode_query(Map.put(filters, "locale", locale))

  defp inbox_html(assigns) do
    rows =
      Enum.map(assigns.conversations, fn row ->
        %{
          id: row.id,
          subject: conversation_subject(row),
          sender_email: Enum.join(row.participants || [], ", "),
          updated_at: row.updated_at,
          href: "/manage/mail/conversations/#{row.id}?locale=#{assigns.locale}"
        }
      end)

    OutreachManagement.inbox(rows,
      card_class: "crm-panel mb-3 break-words",
      link_class: "underline min-h-11 inline-flex items-center",
      labels: %{
        empty: gettext("No conversations match these filters."),
        subject: gettext("Subject"),
        participants: gettext("Participants"),
        updated: gettext("Updated")
      }
    )
  end

  defp conversation_html(assigns) do
    rows =
      Enum.map(assigns.messages, fn message ->
        envelope = message.envelope || %{}

        %{
          id: message.id,
          direction: message.direction,
          sender_email: envelope_value(envelope, "from"),
          sender_name: "",
          recipient_emails: envelope_value(envelope, "to"),
          subject: envelope_value(envelope, "subject"),
          text_body: message.body_text || "",
          occurred_at: message.occurred_at || message.inserted_at,
          actor_label:
            if(message.direction in [:outbound, "outbound"],
              do: Map.get(message, :actor_name) || gettext("Not recorded")
            ),
          outcome_label: outcome_label(message.outcome),
          attachments:
            Enum.map(message.attachments || [], fn attachment ->
              %{
                name:
                  Map.get(
                    attachment,
                    "filename",
                    Map.get(attachment, "name", gettext("Attachment"))
                  ),
                href: Map.get(attachment, "download_path")
              }
            end)
        }
      end)

    OutreachManagement.conversation(rows,
      card_class: "crm-panel mb-5 break-words",
      labels: %{
        incoming: gettext("Received"),
        outgoing: gettext("Sent"),
        submitted_by: gettext("Submitted by"),
        from: gettext("From"),
        to: gettext("To"),
        attachments: gettext("Attachments")
      }
    )
  end

  defp outcome_label(:accepted), do: gettext("Accepted by provider")
  defp outcome_label(:pending), do: gettext("Queued")
  defp outcome_label(:failed), do: gettext("Not submitted")
  defp outcome_label(:unknown), do: gettext("Needs delivery review")
  defp outcome_label(:received), do: gettext("Received")
  defp outcome_label(_), do: gettext("Not recorded")

  defp envelope_value(envelope, key) do
    value = Map.get(envelope, key, "")

    cond do
      is_binary(value) ->
        value

      is_list(value) ->
        Enum.map_join(value, ", ", fn item ->
          if is_binary(item), do: item, else: Map.get(item, "email", "")
        end)

      is_map(value) ->
        Map.get(value, "email", "")

      true ->
        ""
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="mail"
      breadcrumb_context={
        PauseAiCaWeb.Navigation.mail_breadcrumb_context(
          @current_scope,
          @locale,
          !is_nil(@conversation)
        )
      }
    >
      <section
        id="outreach-workspace"
        data-breadcrumb-label={
          if @conversation, do: conversation_subject(@conversation), else: gettext("Inbox")
        }
        class="crm-surface mx-auto max-w-6xl px-5 py-8"
      >
        <section :if={@no_access} id="outreach-no-access" class="crm-panel" role="status">
          <h1 class="text-3xl font-bold">{gettext("Mailbox access required")}</h1>
          <p>
            {gettext(
              "An administrator must grant you access to a mailbox before you can read or send its messages."
            )}
          </p>
          <.link href={inbox_path(@locale, %{})} class="underline min-h-11 inline-flex items-center">{gettext(
            "Refresh mailbox access"
          )}</.link>
        </section>

        <%= if !@no_access do %>
          <div class="management-controls space-y-4">
            <PauseAiCaWeb.MailNavigation.tabs
              current_scope={@current_scope}
              locale={@locale}
              active="conversations"
            />
            <h1 class="text-3xl font-bold">
              {if @conversation, do: conversation_subject(@conversation), else: gettext("Inbox")}
            </h1>
            <p :if={@error} role="alert" class="crm-error">{@error}</p>
            <%= if @conversation do %>
              <p class="break-all">{@mailbox.name} &lt;{@mailbox.email}&gt;</p>
              <div class="flex flex-wrap gap-4 items-center">
                <button
                  id="outreach-reply"
                  phx-click="reply"
                  disabled={!@connected}
                  class="crm-button min-h-11"
                  phx-disable-with={gettext("Opening…")}
                >{gettext("Reply")}</button>
                <.link
                  navigate={inbox_path(@locale, %{})}
                  class="underline min-h-11 inline-flex items-center"
                >{gettext("Inbox")}</.link>
              </div>
            <% else %>
              <.form
                for={to_form(@filters, as: "filters")}
                id="outreach-filters"
                phx-submit="filter"
                class="crm-panel grid gap-3 sm:grid-cols-3 items-end"
              >
                <.input
                  id="outreach-filter-mailbox"
                  name="filters[mailbox_ref]"
                  value={@filters["mailbox_ref"]}
                  type="select"
                  label={gettext("Mailbox")}
                  options={
                    [{gettext("All mailboxes"), ""}] ++ Enum.map(@mailboxes, &{&1.email, &1.id})
                  }
                />
                <.input
                  name="filters[q]"
                  value={@filters["q"]}
                  label={gettext("Search conversations")}
                />
                <button type="submit" disabled={!@connected} class="crm-button min-h-11">{gettext(
                  "Search"
                )}</button>
              </.form>
              <details
                :if={@processing != [] or @notification_attention != []}
                id="outreach-processing-attention"
                class="crm-panel text-sm"
              >
                <summary class="cursor-pointer min-h-11 font-semibold">
                  {gettext("Incoming mail status")} · {length(@processing) +
                    length(@notification_attention)}
                </summary>
                <button
                  type="button"
                  phx-click="refresh-processing"
                  disabled={!@connected}
                  class="underline min-h-11"
                >{gettext("Refresh status")}</button>
                <p :if={@recovery_status} role="status">{@recovery_status}</p>
                <section :if={@processing != []} class="mt-3 space-y-3">
                  <h2 class="font-semibold">{gettext("Incoming messages awaiting processing")}</h2>
                  <p>
                    {gettext(
                      "Incoming payloads remain saved while processing or attachment retrieval is pending. After correcting the mailbox or attachment problem, choose Retry."
                    )}
                  </p>
                  <ul class="space-y-3">
                    <li
                      :for={row <- @processing}
                      id={"outreach-receipt-#{row.id}"}
                      class="border-t pt-3"
                    >
                      <p>
                        {processing_state(row.state)} · {gettext("%{count} attempts",
                          count: row.attempts
                        )}
                      </p>
                      <p :if={row.next_attempt_at}>
                        {gettext("Next attempt")}:
                        <time datetime={DateTime.to_iso8601(row.next_attempt_at)}>{DateTime.to_iso8601(
                          row.next_attempt_at
                        )} (UTC)</time>
                      </p>
                      <p :if={row.error}>
                        {gettext(
                          "Check the mailbox configuration and attachment retrieval before retrying."
                        )}
                      </p>
                      <button
                        type="button"
                        phx-click="retry-receipt"
                        phx-value-id={row.id}
                        disabled={!@connected}
                        class="underline min-h-11"
                        phx-disable-with={gettext("Queuing…")}
                      >{gettext("Retry")}</button>
                    </li>
                  </ul>
                </section>
                <section :if={@notification_attention != []} class="mt-4 space-y-3">
                  <h2 class="font-semibold">{gettext("Reply notifications")}</h2>
                  <ul class="space-y-3">
                    <li
                      :for={row <- @notification_attention}
                      id={"outreach-notification-#{row.id}"}
                      class="border-t pt-3"
                    >
                      <p>{notification_state(row.state)}</p>
                      <p>{notification_instruction(row.state)}</p>
                      <.link
                        navigate={"/manage/mail/conversations/#{row.conversation_id}?locale=#{@locale}"}
                        class="underline min-h-11 inline-flex items-center"
                      >{gettext("View conversation")}</.link>
                    </li>
                  </ul>
                </section>
              </details>
              <details id="outreach-compose" class="crm-panel">
                <summary class="cursor-pointer min-h-11 font-semibold">
                  {gettext("Compose outreach email")}
                </summary>
                <.form
                  for={@compose_form}
                  id="outreach-create-draft"
                  phx-submit="create-draft"
                  class="mt-3 space-y-3"
                >
                  <.input
                    field={@compose_form[:mailbox_ref]}
                    type="select"
                    label={gettext("From")}
                    aria-label={gettext("From")}
                    options={Enum.map(@mailboxes, &{"#{&1.name} <#{&1.email}>", &1.id})}
                  />
                  <.input field={@compose_form[:email]} type="email" required label={gettext("To")} />
                  <.input field={@compose_form[:subject]} label={gettext("Subject")} />
                  <button
                    type="submit"
                    disabled={!@connected or @mailboxes == []}
                    class="crm-button min-h-11"
                  >{gettext("Open draft")}</button>
                </.form>
              </details>
            <% end %>
          </div>
          <%= if @conversation do %>
            <section id="outreach-messages" class="mt-6 space-y-5">
              {Phoenix.HTML.raw(conversation_html(assigns))}
            </section>
            <p :if={@truncated?} class="mt-4">
              {gettext("Showing the latest 200 messages in this conversation.")}
            </p>
          <% else %>
            <section id="outreach-conversations" class="mt-6">
              {Phoenix.HTML.raw(inbox_html(assigns))}
            </section>
            <nav aria-label={gettext("Pagination")} class="mt-5 flex gap-5 items-center">
              <.link
                :if={@page > 1}
                patch={inbox_path(@locale, Map.put(@filters, "page", @page - 1))}
                class="underline min-h-11 inline-flex items-center"
              >{gettext("Previous")}</.link>
              <span>{gettext("Page %{page}", page: @page)}</span>
              <.link
                :if={@more?}
                patch={inbox_path(@locale, Map.put(@filters, "page", @page + 1))}
                class="underline min-h-11 inline-flex items-center"
              >{gettext("Next")}</.link>
            </nav>
          <% end %>
        <% end %>
      </section>
    </Layouts.management>
    """
  end
end
