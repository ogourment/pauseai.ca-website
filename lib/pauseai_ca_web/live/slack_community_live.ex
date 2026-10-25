defmodule PauseAiCaWeb.SlackCommunityLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Chat.Slack
  alias PauseAiCaWeb.VolunteerForms

  @impl true
  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    socket =
      assign(socket,
        locale: locale,
        page_title: gettext("Conversations"),
        configured: Slack.configured?(),
        link: nil,
        channels: [],
        channel: nil,
        messages: [],
        results: nil,
        drafts: [],
        draft: nil,
        target: nil,
        source_url: nil,
        error: nil,
        sync: nil,
        dirty: false,
        query: "",
        form: to_form(%{"text" => ""}, as: "chat_draft")
      )

    if Application.get_env(:pauseai_ca, :slack_enabled, false) do
      if connected?(socket), do: Process.send_after(self(), :refresh_access, 30_000)
      {:ok, load(socket, params["channel"])}
    else
      {:ok, redirect(socket, to: "/dashboard")}
    end
  end

  @impl true
  def handle_event(event, %{"_chat_ref" => ref} = params, socket)
      when event in ["edit", "save"] do
    if Application.get_env(:pauseai_ca, :slack_enabled, false) and ref == form_ref(socket.assigns),
      do: action(event, params, socket),
      else: {:noreply, socket}
  end

  def handle_event(event, _, socket) when event in ["edit", "save"], do: {:noreply, socket}

  def handle_event(event, params, socket) do
    if Application.get_env(:pauseai_ca, :slack_enabled, false),
      do: action(event, params, socket),
      else: {:noreply, redirect(socket, to: "/dashboard")}
  end

  defp action("channel", %{"channel" => channel}, socket) do
    {:noreply,
     socket
     |> assign(
       results: nil,
       target: nil,
       draft: nil,
       source_url: nil,
       form: to_form(%{"text" => ""}, as: "chat_draft")
     )
     |> load(channel)}
  end

  defp action("search", %{"chat_search" => %{"query" => query}}, socket) do
    case Slack.search(socket.assigns.current_scope, String.trim(query)) do
      {:ok, results} ->
        {:noreply, assign(socket, results: results, query: query, source_url: nil, error: nil)}

      _ ->
        {:noreply, denied(socket)}
    end
  end

  defp action("clear_search", _, socket), do: {:noreply, assign(socket, results: nil, query: "")}

  defp action("reply", %{"ts" => ts, "channel" => channel}, socket) do
    case Slack.history(socket.assigns.current_scope, channel) do
      {:ok, messages} ->
        if message = Enum.find(messages, &(&1.external_ts == ts)) do
          {:noreply,
           assign(load(socket, channel),
             target: message,
             draft: nil,
             dirty: false,
             form: to_form(%{"text" => ""}, as: "chat_draft"),
             error: nil
           )}
        else
          {:noreply,
           assign(socket,
             error: gettext("This message is unavailable. Refresh the channel before replying.")
           )}
        end

      _ ->
        {:noreply, denied(socket)}
    end
  end

  defp action("edit", %{"chat_draft" => attrs}, socket) do
    dirty = !socket.assigns.draft || attrs["text"] != socket.assigns.draft.text
    {:noreply, assign(socket, dirty: dirty, form: to_form(attrs, as: "chat_draft"))}
  end

  defp action("new_root", _, socket),
    do:
      {:noreply,
       assign(socket, target: nil, draft: nil, form: to_form(%{"text" => ""}, as: "chat_draft"))}

  defp action("save", %{"chat_draft" => attrs}, socket) do
    a = socket.assigns

    attrs =
      Map.put(attrs, "thread_ts", if(a.target, do: a.target.thread_ts || a.target.external_ts))

    result =
      if a.draft,
        do: Slack.update_draft(a.current_scope, a.draft.id, a.draft.revision, attrs),
        else: Slack.save_draft(a.current_scope, a.channel, attrs)

    case result do
      {:ok, draft} ->
        {:noreply,
         socket
         |> assign(draft: draft, dirty: false, error: nil, form: to_form(attrs, as: "chat_draft"))
         |> load(a.channel)
         |> put_flash(:info, gettext("Your conversation draft is saved."))}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply,
         assign(socket,
           form: to_form(attrs, as: "chat_draft", errors: cs.errors),
           error: gettext("Enter a message of up to 4,000 characters.")
         )}

      _ ->
        {:noreply,
         assign(socket,
           error: gettext("This draft could not be saved. Your text is retained."),
           form: to_form(attrs, as: "chat_draft")
         )}
    end
  end

  defp action("open_draft", %{"id" => id}, socket) do
    case Slack.draft(socket.assigns.current_scope, id) do
      {:ok, draft} ->
        socket = load(socket, draft.channel_id)

        {:noreply,
         assign(socket,
           draft: draft,
           target: nil,
           dirty: false,
           form: to_form(%{"text" => draft.text}, as: "chat_draft")
         )}

      _ ->
        {:noreply, assign(socket, error: gettext("This draft is unavailable."))}
    end
  end

  defp action("post", _, %{assigns: %{draft: nil}} = socket), do: {:noreply, socket}
  defp action("post", _, %{assigns: %{dirty: true}} = socket), do: {:noreply, socket}

  defp action("post", _, socket) do
    a = socket.assigns

    with {:ok, queued} <- Slack.queue(a.current_scope, a.draft.id, a.draft.revision),
         {:ok, outcome} <- Slack.deliver(a.current_scope, queued.id, queued.revision) do
      {:noreply, socket |> assign(draft: outcome, error: nil) |> load(a.channel)}
    else
      _ ->
        fresh =
          case Slack.draft(a.current_scope, a.draft.id) do
            {:ok, draft} -> draft
            _ -> a.draft
          end

        {:noreply,
         assign(load(socket, a.channel),
           draft: fresh,
           error:
             gettext(
               "Posting is unavailable. Check your current access and the saved draft status before trying again."
             )
         )}
    end
  end

  defp action("sync", _, socket) do
    case Slack.repair_page(socket.assigns.current_scope, socket.assigns.channel) do
      {:ok, receipt} ->
        {:noreply,
         socket |> assign(sync: receipt, source_url: nil) |> load(socket.assigns.channel)}

      _ ->
        {:noreply,
         assign(denied(socket),
           error:
             gettext("Slack history is unavailable. Refresh your connection before trying again.")
         )}
    end
  end

  defp action("sync_thread", %{"ts" => thread, "channel" => channel}, socket) do
    case Slack.repair_thread(socket.assigns.current_scope, channel, thread) do
      {:ok, receipt} -> {:noreply, socket |> assign(sync: receipt) |> load(channel)}
      _ -> {:noreply, denied(socket)}
    end
  end

  defp action("source", %{"ts" => ts, "channel" => channel}, socket) do
    case Slack.permalink(socket.assigns.current_scope, channel, ts) do
      {:ok, url} ->
        {:noreply, assign(socket, source_url: url)}

      _ ->
        {:noreply,
         assign(denied(socket),
           source_url: nil,
           error: gettext("The original Slack link is unavailable.")
         )}
    end
  end

  defp action("unlink", _, socket) do
    if socket.assigns.link do
      case Slack.unlink(socket.assigns.current_scope, socket.assigns.link.revision) do
        {:ok, _} ->
          {:noreply, socket |> assign(draft: nil, target: nil, source_url: nil) |> load(nil)}

        _ ->
          {:noreply,
           assign(socket, error: gettext("The connection changed. Reload before disconnecting."))}
      end
    else
      {:noreply, socket}
    end
  end

  defp action(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:refresh_access, socket) do
    Process.send_after(self(), :refresh_access, 30_000)

    if Application.get_env(:pauseai_ca, :slack_enabled, false),
      do: {:noreply, load(socket, socket.assigns.channel)},
      else: {:noreply, redirect(socket, to: "/dashboard")}
  end

  defp load(socket, requested) do
    scope = socket.assigns.current_scope

    with true <- Slack.configured?(),
         {:ok, link} <- Slack.link(scope),
         {:ok, channels} <- Slack.channels(scope),
         {:ok, drafts} <- Slack.drafts(scope) do
      channel = if requested in channels, do: requested, else: List.first(channels)

      case if(channel, do: Slack.history(scope, channel), else: {:ok, []}) do
        {:ok, messages} ->
          assign(socket,
            configured: true,
            link: link,
            channels: channels,
            channel: channel,
            messages: messages,
            drafts: drafts,
            results: refreshed_search(scope, socket.assigns.query),
            source_url: nil,
            error: nil,
            target:
              if(socket.assigns.target && channel == socket.assigns.channel,
                do: Enum.find(messages, &(&1.external_ts == socket.assigns.target.external_ts))
              )
          )

        _ ->
          denied(socket)
      end
    else
      _ -> assign(denied(socket), configured: Slack.configured?(), link: nil)
    end
  end

  defp refreshed_search(_, ""), do: nil

  defp refreshed_search(scope, query) do
    case Slack.search(scope, query) do
      {:ok, results} -> results
      _ -> []
    end
  end

  defp denied(socket),
    do:
      assign(socket,
        channels: [],
        channel: nil,
        messages: [],
        results: nil,
        source_url: nil,
        target: nil,
        error:
          gettext(
            "Channel access is unavailable. Connect Slack or ask your group manager about access."
          )
      )

  defp form_ref(a) do
    Enum.join(
      [
        a.channel || "",
        if(a.draft, do: a.draft.id <> ":" <> to_string(a.draft.revision), else: "new"),
        if(a.target, do: a.target.external_ts, else: "root")
      ],
      ":"
    )
  end

  defp message_datetime(ts) do
    with [seconds, _] <- String.split(ts, "."),
         {value, ""} <- Integer.parse(seconds),
         {:ok, time} <- DateTime.from_unix(value),
         do: time,
         else: (_ -> nil)
  end

  defp state("draft"), do: gettext("Draft")
  defp state("pending"), do: gettext("Pending")
  defp state("sending"), do: gettext("Posting")
  defp state("sent"), do: gettext("Posted to Slack")
  defp state("failed"), do: gettext("Slack rejected this attempt")
  defp state("uncertain"), do: gettext("Delivery uncertain — do not retry")
  defp state("cancelled"), do: gettext("Cancelled")
  defp state(_), do: gettext("Unavailable")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      translated_path={"/community/slack?locale=#{if @locale == "fr", do: "en", else: "fr"}"}
    >
      <section
        id="slack-community"
        class="mx-auto max-w-5xl px-5 py-8 space-y-6 [&_.label]:whitespace-normal [&_.label]:max-w-full [&_.fieldset]:min-w-0 [&_.fieldset]:max-w-full"
      >
        <h1 class="text-3xl font-bold">{gettext("Conversations")}</h1>
        <p
          :if={!@configured}
          class="rounded-xl border border-base-300 bg-base-200 p-4"
          id="slack-setup"
        >
          {gettext(
            "Slack conversations are awaiting site configuration. Please contact the site team."
          )}
        </p>
        <div :if={@configured} class="rounded-xl border border-base-300 bg-base-200 p-4 space-y-3">
          <p :if={@link}>{gettext("Slack account connected")}: {@link.provider_user_id}</p>
          <.form
            :if={!@link}
            for={%{}}
            action={~p"/community/slack/connect"}
            method="post"
            id="slack-connect"
          >
            <button type="submit" class="btn btn-primary">{gettext("Connect Slack")}</button>
          </.form>
          <button
            :if={@link}
            phx-click="unlink"
            data-confirm={gettext("Disconnect Slack and cancel pending posts?")}
            class="btn btn-outline"
          >{gettext("Disconnect Slack")}</button>
          <p class="text-sm">
            {gettext(
              "Your website account must be explicitly linked to your Slack account. Access depends on your current website audience and Slack channel membership."
            )}
          </p>
          <form :if={@channels != []} phx-change="channel" id="slack-channel">
            <.input
              name="channel"
              type="select"
              label={gettext("Channel")}
              value={@channel}
              options={Enum.map(@channels, &{Slack.channel_name(&1), &1})}
            />
          </form>
        </div>
        <p :if={@error && @configured} role="alert" class="rounded border border-warning p-3">
          {@error}
        </p>
        <div :if={@channel} class="space-y-5">
          <form phx-submit="search" id="slack-search" class="flex flex-wrap gap-3 items-end">
            <.input
              name="chat_search[query]"
              value={@query}
              label={gettext("Search retained conversations")}
              maxlength="200"
            /><button type="submit" class="btn btn-outline">{gettext("Search")}</button><button
              :if={@results}
              type="button"
              phx-click="clear_search"
              class="btn btn-ghost"
            >{gettext("Clear search")}</button>
          </form>
          <div class="flex flex-wrap gap-3 items-center">
            <h2 class="text-xl font-semibold">{Slack.channel_name(@channel)}</h2><button
              phx-click="sync"
              class="btn btn-outline"
            >{gettext("Capture recent Slack history")}</button>
          </div>
          <p class="text-sm">
            {gettext(
              "Only captured text is searchable here. Each capture reads at most 50 recent messages; older history and attachment bytes may be missing."
            )}
          </p>
          <p :if={@sync && @sync.has_more} class="text-sm">
            {gettext("Slack reports more history beyond this captured page. Coverage is incomplete.")}
          </p>
          <div id="slack-messages" class="space-y-3">
            <p :if={(@results || @messages) == []}>
              {gettext("No retained messages match this view.")}
            </p><article
              :for={message <- @results || @messages}
              id={"slack-message-#{message.id}"}
              class="rounded-xl border border-base-300 p-4 space-y-2"
            >
              <p :if={@results} class="text-sm">
                {gettext("Channel")}: {Slack.channel_name(message.channel_id)}
              </p>
              <p class="text-sm">
                {gettext("Slack member")}: {message.provider_user_id || gettext("Application")}
              </p>
              <VolunteerForms.timestamp
                id={"slack-time-#{message.id}"}
                value={message_datetime(message.external_ts)}
                locale={@locale}
              />
              <p class="whitespace-pre-wrap break-words">{message.text}</p><p
                :if={message.thread_ts && message.thread_ts != message.external_ts}
                class="text-sm"
              >
                {gettext("Thread reply")}
              </p><div class="flex flex-wrap gap-3">
                <button
                  phx-click="reply"
                  phx-value-ts={message.external_ts}
                  phx-value-channel={message.channel_id}
                  class="btn btn-ghost"
                >{gettext("Reply")}</button><button
                  phx-click="source"
                  phx-value-ts={message.external_ts}
                  phx-value-channel={message.channel_id}
                  class="btn btn-ghost"
                >{gettext("Get original link")}</button>
                <button
                  :if={is_nil(message.thread_ts) or message.thread_ts == message.external_ts}
                  phx-click="sync_thread"
                  phx-value-ts={message.external_ts}
                  phx-value-channel={message.channel_id}
                  class="btn btn-ghost"
                >{gettext("Capture thread replies")}</button>
              </div>
            </article>
          </div>
          <.link
            :if={@source_url}
            href={@source_url}
            target="_blank"
            rel="noopener noreferrer"
            class="underline"
          >{gettext("Open original in Slack")}</.link>
          <.form
            for={@form}
            id="slack-draft"
            phx-submit="save"
            phx-change="edit"
            class="rounded-xl border border-base-300 p-5 space-y-4"
          >
            <input type="hidden" name="_chat_ref" value={form_ref(assigns)} />
            <h2 class="text-xl font-semibold">{gettext("Write a message")}</h2><p :if={@target}>
              {gettext("Reply to")}: {String.slice(@target.text || "", 0, 200)}
            </p><button :if={@target} type="button" phx-click="new_root" class="btn btn-ghost">{gettext(
              "Write a new channel message"
            )}</button>
            <.input
              field={@form[:text]}
              type="textarea"
              label={gettext("Message")}
              maxlength="4000"
              required
              disabled={@draft && @draft.status not in ["draft", "failed"]}
            /><button
              :if={!@draft || @draft.status in ["draft", "failed"]}
              type="submit"
              class="btn btn-primary"
            >{gettext("Save draft")}</button>
          </.form>
        </div>
        <section
          :if={@draft}
          id="slack-post-review"
          class="rounded-xl border border-base-300 p-5 space-y-3"
        >
          <h2 class="text-xl font-semibold">{gettext("Review Slack post")}</h2><p>
            {gettext("Channel")}: {Slack.channel_name(@draft.channel_id)}
          </p><p :if={@draft.thread_ts}>{gettext("Thread")}: {@draft.thread_ts}</p><p class="whitespace-pre-wrap break-words">
            {@draft.text}
          </p><p id="slack-post-status">{state(@draft.status)}</p><button
            :if={@draft.status in ["draft", "failed"] and @draft.channel_id in @channels}
            phx-click="post"
            data-confirm={
              gettext("Post this exact message to the displayed Slack channel or thread?")
            }
            disabled={@dirty}
            class="btn btn-primary"
          >{gettext("Post to Slack")}</button><p :if={@draft.status in ["uncertain", "sending"]}>
            {gettext(
              "Check the actual Slack conversation before any recovery. This attempt will not be retried automatically."
            )}
          </p>
        </section>
        <section :if={@drafts != []} class="space-y-3" id="slack-saved-drafts">
          <h2 class="text-xl font-semibold">{gettext("Your conversation drafts")}</h2><ul>
            <li :for={draft <- @drafts} class="py-2 border-b border-base-300">
              <button phx-click="open_draft" phx-value-id={draft.id} class="underline">{Slack.channel_name(
                draft.channel_id
              )} · {state(draft.status)} · {String.slice(draft.text, 0, 80)}</button>
            </li>
          </ul>
        </section>
      </section>
    </Layouts.app>
    """
  end
end
