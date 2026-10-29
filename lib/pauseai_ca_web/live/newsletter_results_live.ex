defmodule PauseAiCaWeb.NewsletterResultsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Newsletters.Results

  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    {:ok,
     assign(socket,
       locale: locale,
       page_title: gettext("Sent & results"),
       records: [],
       overview: %{},
       navigation: %{ids: [], previous: nil, next: nil},
       context: "",
       return_id: nil,
       preview: nil,
       senders: %{},
       recipient_summaries: %{},
       result: nil,
       provider: nil,
       sync_status: nil,
       loading: false,
       error: nil,
       page: 1
     )}
  end

  def handle_params(params, _, socket) do
    socket = socket |> cancel_async(:results) |> assign(loading: false)

    page =
      case Integer.parse(params["page"] || "1") do
        {n, ""} when n > 0 and n < 10000 -> n
        _ -> 1
      end

    response =
      if params["id"],
        do: Results.get(socket.assigns.current_scope, params["id"]),
        else:
          if(params["context"],
            do:
              Results.list_context(
                socket.assigns.current_scope,
                String.split(params["context"], ",")
              ),
            else: Results.list(socket.assigns.current_scope, page)
          )

    case response do
      {:ok, records} when is_list(records) ->
        ids = Enum.map(records, & &1.id)

        {:noreply,
         assign(socket,
           senders: Results.senders(socket.assigns.current_scope, Enum.map(records, & &1.id)),
           recipient_summaries:
             Results.recipient_summaries(socket.assigns.current_scope, Enum.map(records, & &1.id)),
           records: records,
           overview: Results.overview(socket.assigns.current_scope, ids),
           context: Enum.map_join(records, ",", & &1.id),
           return_id: params["return"],
           sync_status: PauseAiCa.Newsletters.ProviderSync.status(),
           result: nil,
           page: page,
           provider: nil,
           error: nil
         )}

      {:ok, result} ->
        ids =
          if params["context"],
            do: String.split(params["context"], ","),
            else:
              (case Results.list(socket.assigns.current_scope, page) do
                 {:ok, rows} -> Enum.map(rows, & &1.id)
                 _ -> []
               end)

        navigation = Results.navigation(socket.assigns.current_scope, result.batch.id, ids)

        socket =
          assign(socket,
            senders: Results.senders(socket.assigns.current_scope, [result.batch.id]),
            result: result,
            page: page,
            navigation: navigation,
            context: Enum.join(navigation.ids, ","),
            return_id: params["return"] || result.batch.id,
            preview: PauseAiCa.Mail.Render.html(result.batch.source || ""),
            sync_status: result.synchronization,
            provider: result.provider,
            error: nil
          )

        socket =
          if connected?(socket) and is_nil(result.provider) and
               result.batch.delivery_environment == "production" do
            scope = socket.assigns.current_scope

            assign(socket, loading: true)
            |> start_async(:results, fn -> Results.refresh(scope, result.batch.id) end)
          else
            socket
          end

        {:noreply, socket}

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Superadmin access required."))
         |> redirect(to: ~p"/dashboard")}
    end
  end

  def handle_event("refresh", _, socket) do
    if socket.assigns.loading or is_nil(socket.assigns.result) do
      {:noreply, socket}
    else
      scope = socket.assigns.current_scope
      id = socket.assigns.result.batch.id

      {:noreply,
       socket
       |> assign(loading: true, error: nil)
       |> start_async(:results, fn -> Results.refresh(scope, id) end)}
    end
  end

  def handle_async(:results, {:ok, {:ok, provider}}, socket) do
    case Results.get(socket.assigns.current_scope, socket.assigns.result.batch.id) do
      {:ok, result} ->
        {:noreply,
         assign(socket,
           result: result,
           sync_status: result.synchronization,
           provider: provider,
           loading: false
         )}

      _ ->
        {:noreply,
         socket
         |> assign(result: nil, provider: nil, loading: false)
         |> redirect(to: ~p"/dashboard")}
    end
  end

  def handle_async(:results, {:ok, {:error, :unauthorized}}, socket),
    do:
      {:noreply,
       socket
       |> assign(result: nil, provider: nil, loading: false)
       |> redirect(to: ~p"/dashboard")}

  def handle_async(:results, _, socket),
    do:
      {:noreply,
       assign(socket,
         loading: false,
         error:
           gettext(
             "Provider results are unavailable. Check configuration, retention or rate limits and try again. Sending records remain available."
           )
       )}

  defp sender_labels(senders, id) do
    Map.get(senders, id, [])
    |> Enum.map(fn sender ->
      cond do
        sender.email && sender.name not in [nil, ""] -> "#{sender.name} <#{sender.email}>"
        sender.email -> sender.email
        true -> gettext("Not recorded")
      end
    end)
    |> Enum.uniq()
    |> Enum.join(", ")
    |> case do
      "" -> gettext("Not recorded")
      value -> value
    end
  end

  defp edition_label("en"), do: gettext("English")
  defp edition_label("fr"), do: gettext("French")
  defp edition_label("unknown"), do: gettext("Bilingual · language unknown only")
  defp edition_label(_), do: gettext("Not recorded")

  defp recipient_count_label(count), do: gettext("Planned recipients: %{count}", count: count)

  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="mail"
    >
      <section
        class="crm-surface mx-auto max-w-6xl px-5 py-8"
        data-breadcrumb-label={if @result, do: @result.batch.subject, else: gettext("Sent & results")}
      >
        <div class="management-controls">
          <PauseAiCaWeb.MailNavigation.tabs locale={@locale} active="results" />
          <h1 class="text-3xl font-bold">{gettext("Sent & results")}</h1>
          <p class="mt-3">
            {gettext(
              "Open a send to inspect its frozen audience, sending status and provider observations. Drafts that have never been sent are in Drafts."
            )}
          </p>
        </div>
        <details
          id="provider-synchronization"
          class="my-4 rounded border border-stone-300 p-3"
          open={@sync_status && (@sync_status.last_error || @sync_status.partial)}
        >
          <summary class="cursor-pointer font-semibold">
            {gettext("Provider synchronization")}
            <span :if={@sync_status && @sync_status.last_success_at} class="text-sm font-normal">
              · {gettext("Last successful reconciliation")}:
              <time datetime={DateTime.to_iso8601(@sync_status.last_success_at)}>{Calendar.strftime(
                @sync_status.last_success_at,
                "%Y-%m-%d %H:%M UTC"
              )}</time>
            </span>
          </summary>
          <p :if={!PauseAiCa.Newsletters.ProviderSyncWorker.enabled?()}>
            {gettext("Automatic synchronization is disabled in this environment.")}
          </p>
          <p :if={PauseAiCa.Newsletters.ProviderSyncWorker.enabled?()}>
            {gettext(
              "Read-only reconciliation runs every 15 minutes. Recent history overlaps, with a daily scan of the available 90-day history."
            )}
          </p>
          <p :if={@sync_status && @sync_status.partial} role="status">
            {gettext("History is incomplete. The next pass continues from its saved cursor.")}
          </p>
          <p :if={@sync_status && @sync_status.last_error} role="alert" class="crm-error">
            {gettext(
              "Provider reconciliation needs attention. Existing address holds and withdrawals remain in effect."
            )}
          </p>
          <p :if={@sync_status && Map.get(@sync_status.counts, "invalid", 0) > 0} role="alert">
            {gettext("%{count} provider events could not be classified and need review.",
              count: @sync_status.counts["invalid"]
            )}
          </p>
        </details>
        <div :if={is_nil(@result)} class="mt-6 space-y-4">
          <h2 class="text-2xl font-bold">{gettext("Send results at a glance")}</h2>
          <p>
            {gettext(
              "Each row is one send batch. Editions and additional audiences can have separate batches. Stored results only; opens and clicks may be automated."
            )}
          </p>
          <p :if={@records == []}>{gettext("No sends on this page.")}</p>
          <section
            :for={group <- Enum.chunk_by(@records, &{&1.draft_id || &1.id, &1.subject})}
            class="border-t border-stone-300 pt-3"
          >
            <h3 class="text-xl font-bold">{hd(group).subject}</h3>
            <article
              :for={batch <- group}
              id={"send-#{batch.id}"}
              class="min-w-0 border-b border-stone-200 py-3"
            >
              <div class="flex flex-wrap items-baseline gap-x-4 gap-y-1">
                <.link
                  class="font-bold underline"
                  patch={detail_path(batch.id, @locale, @page, @context, batch.id)}
                >{edition_label(batch.edition)} · {Date.to_iso8601(
                  DateTime.to_date(batch.inserted_at)
                )}</.link>
                <span>{if batch.recipient_mode in ["newsletter", "list"],
                  do: gettext("Newsletter"),
                  else: gettext("Individual / manually targeted email")}</span>
                <span>{recipient_count_label(
                  Map.get(@recipient_summaries, batch.id, %{count: 0}).count
                )}</span>
                <span>{batch.delivery_environment}</span>
              </div>
              <p
                :if={batch.recipient_mode == "contacts"}
                class="mt-1 break-words text-sm"
                data-manual-recipients
              >
                {gettext("Recipients")}: {Enum.join(
                  Map.get(@recipient_summaries, batch.id, %{emails: []}).emails,
                  ", "
                )}
              </p>
              <.stored_results summary={@overview[batch.id]} />
              <details class="mt-2 text-sm">
                <summary class="cursor-pointer underline">
                  {gettext("Content and recipients")}
                </summary>
                <p class="mt-2 whitespace-pre-line break-words">
                  {String.slice(batch.source || "", 0, 320)}
                </p>
                <p class="break-words" data-recipient-identities>
                  {Enum.join(Map.get(@recipient_summaries, batch.id, %{emails: []}).emails, ", ")}
                  <span :if={Map.get(@recipient_summaries, batch.id, %{count: 0}).count > 3}> · {gettext(
                    "and %{count} more",
                    count: @recipient_summaries[batch.id].count - 3
                  )}</span>
                </p>
                <p>{gettext("Sent by")}: {sender_labels(@senders, batch.id)}</p>
              </details>
            </article>
          </section>
          <div class="flex gap-4">
            <.link
              :if={@page > 1}
              patch={~p"/manage/mail/results?#{%{page: @page - 1, locale: @locale}}"}
              class="underline"
            >{gettext("Previous")}</.link>
            <.link
              :if={length(@records) == 25}
              patch={~p"/manage/mail/results?#{%{page: @page + 1, locale: @locale}}"}
              class="underline"
            >{gettext("Next")}</.link>
          </div>
        </div>
        <div :if={@result} class="mt-6 space-y-5">
          <nav aria-label={gettext("Send navigation")} class="flex flex-wrap gap-4">
            <.link
              class="underline"
              patch={
                ~p"/manage/mail/results?#{%{locale: @locale, page: @page, return: @return_id, context: @context}}" <> "#send-#{@return_id}"
              }
            >{gettext("Back to results")}</.link>
            <.link
              :if={@navigation.previous}
              class="underline"
              patch={detail_path(@navigation.previous, @locale, @page, @context, @return_id)}
            >{gettext("Previous send")}</.link>
            <.link
              :if={@navigation.next}
              class="underline"
              patch={detail_path(@navigation.next, @locale, @page, @context, @return_id)}
            >{gettext("Next send")}</.link>
          </nav>
          <h2 class="text-2xl font-bold">{@result.batch.subject}</h2>
          <p class="font-semibold">
            {gettext("Accepted by provider")}: {Map.get(@result.report.states, "accepted", 0)} · {recipient_count_label(
              @result.report.total
            )}
          </p>
          <details id="sent-content-preview" class="rounded border border-stone-300 p-4" open>
            <summary class="cursor-pointer font-semibold">{gettext("Sent content preview")}</summary>
            <p class="my-2 text-sm">
              {gettext(
                "Message body for this send. Links are inactive in this preview; personalized footers are omitted."
              )}
            </p>
            <iframe
              title={gettext("Sent content preview")}
              sandbox=""
              srcdoc={preview_document(@preview)}
              class="h-80 w-full rounded border"
            />
            <p :if={!@provider || is_nil(@provider.links)} class="mt-2 text-sm">
              {gettext(
                "No saved link-level report is available. Refresh results to check authored links."
              )}
            </p>
            <section :if={@provider && @provider.links} id="clicked-links" class="mt-3">
              <h3 class="font-semibold">{gettext("Clicks by authored link")}</h3>
              <p class="text-sm">
                {gettext(
                  "Unique recipients with an observed click per link. Automated clicks may be included. Recipient-specific links are excluded."
                )}
              </p>
              <p :if={@provider.links["items"] == []}>
                {gettext("No reportable authored links in this send.")}
              </p>
              <p :if={!Enum.any?(@provider.links["items"], &(&1["clicked"] > 0))} class="mt-2 text-sm">
                {gettext("No observed clicks on these authored links yet.")}
              </p>
              <.clicked_link_rows links={
                Enum.filter(@provider.links["items"], &(&1["clicked"] > 0))
                |> Enum.sort_by(&(-&1["clicked"]))
              } />
              <details :if={Enum.any?(@provider.links["items"], &(&1["clicked"] == 0))} class="mt-2">
                <summary class="cursor-pointer text-sm underline">
                  {gettext("Other authored links (%{count})",
                    count: Enum.count(@provider.links["items"], &(&1["clicked"] == 0))
                  )}
                </summary>
                <.clicked_link_rows links={
                  Enum.filter(@provider.links["items"], &(&1["clicked"] == 0))
                } />
              </details>
            </section>
          </details>
          <p>{gettext("Sent by")}: {sender_labels(@senders, @result.batch.id)}</p>
          <p>
            {gettext("From address")}: {@result.batch.sender_name} &lt;{@result.batch.sender_email}&gt;
          </p>
          <p>
            {edition_label(@result.batch.edition)} · {@result.batch.delivery_environment}
          </p>
          <h3 class="text-xl font-semibold">{gettext("Sending status")}</h3>
          <dl class="flex flex-wrap gap-6">
            <div :for={{state, count} <- @result.report.states}>
              <dt>{state_label(state)}</dt><dd class="text-2xl font-bold">{count}</dd>
            </div>
          </dl>
          <p>
            {gettext(
              "Accepted means the provider accepted the submission; it does not establish delivery or reading."
            )}
          </p>
          <p>
            <strong>{gettext("Recipients currently withdrawn")}: {@result.current_withdrawn}</strong>
          </p>
          <p>
            <strong>{gettext("Withdrawals attributed to this send")}: {@result.local_unsubscribed}</strong>
          </p>
          <p>
            {gettext(
              "Includes exact local withdrawal links and matched provider unsubscribe events. Earlier unattributed withdrawals remain separate."
            )}
          </p>
          <section id="newsletter-deliverability" class="rounded border border-stone-300 p-4">
            <h3 class="text-xl font-semibold">{gettext("Recipient deliverability review")}</h3>
            <dl class="mt-3 grid grid-cols-2 gap-4 md:grid-cols-4">
              <div>
                <dt>{gettext("Permanent address failures")}</dt><dd data-review="hard-bounce">
                  {@result.reconciliation["hard_bounce"]}
                </dd>
              </div>
              <div>
                <dt>{gettext("Provider unsubscribe withdrawals")}</dt><dd data-review="unsubscribe">
                  {@result.reconciliation["unsubscribe"]}
                </dd>
              </div>
              <div>
                <dt>{gettext("Soft bounces to review")}</dt><dd data-review="soft-bounce">
                  {@result.reconciliation["review"]}
                </dd>
              </div>
              <div>
                <dt>{gettext("Invalid-domain address holds")}</dt><dd data-review="invalid-domain">
                  {@result.reconciliation["invalid_domain"]}
                </dd>
              </div>
            </dl>
            <p class="mt-3">
              {gettext(
                "Address failures do not revoke newsletter consent. Invalid domains are held for verification; other soft bounces remain review flags. Addresses are never changed automatically."
              )}
            </p>
            <p :if={@result.reconciliation["conflicts"] > 0} role="alert" class="crm-error">
              {gettext(
                "%{count} historical unsubscribes conflict with a later signup choice. The later choice is preserved; newsletter delivery remains held for review.",
                count: @result.reconciliation["conflicts"]
              )}
            </p>
            <details :if={@result.deliverability_rows != []} class="mt-3">
              <summary class="cursor-pointer underline">
                {gettext("Review affected recipients")}
              </summary>
              <ul id="deliverability-review-rows" class="mt-3 space-y-2">
                <li :for={row <- @result.deliverability_rows} class="break-words">
                  {row.email} · {delivery_reason(row.reason)} ·
                  <time datetime={DateTime.to_iso8601(row.occurred_at)}>{Calendar.strftime(
                    row.occurred_at,
                    "%Y-%m-%d %H:%M UTC"
                  )}</time>
                </li>
              </ul>
            </details>
          </section>
          <h3 class="text-xl font-semibold">{gettext("Campaign performance")}</h3>
          <button type="button" phx-click="refresh" disabled={@loading} class="crm-button">{if @loading,
            do: gettext("Refreshing…"),
            else: gettext("Refresh results and recipient status")}</button>
          <p class="text-sm">
            {gettext(
              "Refreshing reads provider history. When reconciliation is enabled, matching failures and unsubscribes update recipient status. It never resends mail."
            )}
          </p>
          <p :if={@error} role="alert" class="crm-error">{@error}</p>
          <p :if={is_nil(@provider)}>
            {gettext("Provider observations have not been loaded. Unavailable results are not zero.")}
          </p>
          <div :if={@provider}>
            <p>
              {gettext("Last refreshed")}:
              <time id="provider-refreshed-at" datetime={DateTime.to_iso8601(@provider.refreshed_at)}>{Calendar.strftime(
                @provider.refreshed_at,
                "%Y-%m-%d %H:%M UTC"
              )}</time>
            </p>
            <p :if={@provider.partial} class="crm-error">
              {gettext(
                "Partial report: the provider page limit was reached. Counts are lower bounds."
              )}
            </p>
            <dl class="grid grid-cols-2 gap-4 md:grid-cols-4">
              <div :for={{key, label} <- metrics()} class="rounded border border-stone-300 p-3">
                <dt>{label}</dt><dd class="text-2xl font-bold">{@provider.report.observed[key]}</dd>
              </div>
            </dl>
            <p class="mt-3">
              {gettext(
                "Counts are unique recipients with an observed event for this send. Delivery means receiving-server acceptance. Opens and clicks can be automated; proxy opens are separate. Provider unsubscribes are also recorded as local purpose withdrawals; repeated observations do not create another withdrawal."
              )}
            </p>
          </div>
          <details>
            <summary class="cursor-pointer underline">
              {gettext("Recipient sending receipts")}
            </summary><ul class="mt-3 space-y-2">
              <li :for={delivery <- @result.deliveries} class="break-words">
                {delivery.email} · {state_label(delivery.state)}<span :if={delivery.error}> · {delivery.error}</span>
              </li>
            </ul>
          </details>
        </div>
      </section>
    </Layouts.management>
    """
  end

  defp detail_path(id, locale, page, context, return_id),
    do:
      ~p"/manage/mail/results/#{id}?#{%{locale: locale, page: page, context: context, return: return_id}}"

  defp preview_document(html) do
    html =
      html |> String.replace(~r/<a\b[^>]*>/i, "<span>") |> String.replace(~r/<\/a>/i, "</span>")

    "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'\"><style>body{font:16px/1.55 Arial,Helvetica,sans-serif;color:#292524;max-width:680px;margin:0 auto;padding:12px;overflow-wrap:anywhere}a{pointer-events:none;color:#854d0e}pre{white-space:pre-wrap}</style></head><body>#{html}</body></html>"
  end

  defp stored_results(assigns) do
    ~H"""
    <div class="mt-3" data-stored-results>
      <p class="font-semibold">
        {gettext("Accepted by provider")}:
        <strong class="text-lg">{Map.get(@summary.states, "accepted", 0)}</strong>
        · {gettext("Failed")}: {Map.get(@summary.states, "failed", 0)}
      </p>
      <p :if={is_nil(@summary.provider)}>
        {gettext("Provider observations have not been loaded. Unavailable results are not zero.")}
      </p>
      <div :if={@summary.provider}>
        <p class="text-sm">
          {gettext("Last refreshed")}:
          <time datetime={DateTime.to_iso8601(@summary.provider.refreshed_at)}>{Calendar.strftime(
            @summary.provider.refreshed_at,
            "%Y-%m-%d %H:%M UTC"
          )}</time>
        </p>
        <p :if={@summary.provider.partial} class="crm-error">
          {gettext("Partial report: the provider page limit was reached. Counts are lower bounds.")}
        </p>
        <p
          :if={
            Enum.all?(metrics(), fn {key, _} ->
              Map.get(@summary.provider.observed, Atom.to_string(key), 0) == 0
            end)
          }
          class="mt-2"
        >
          {gettext(
            "No deliveries, opens or clicks reported yet. Accepted submissions do not establish delivery or reading."
          )}
        </p>
        <dl class="mt-2 grid grid-cols-2 gap-x-4 gap-y-2 sm:grid-cols-3 lg:grid-cols-6">
          <div :for={{key, label} <- overview_metrics()}>
            <dt class="text-sm">{label}</dt><dd class="font-bold">
              {Map.get(@summary.provider.observed, Atom.to_string(key), "—")}
            </dd>
          </div>
        </dl>
      </div>
    </div>
    """
  end

  attr :links, :list, required: true

  defp clicked_link_rows(assigns) do
    ~H"""
    <ul class="mt-2 divide-y divide-stone-200">
      <li :for={link <- @links} class="flex flex-wrap justify-between gap-2 py-2">
        <span class="min-w-0 break-all">{link["label"]}<span class="block text-sm">{link["url"]}</span></span>
        <strong>{link["clicked"]}</strong>
      </li>
    </ul>
    """
  end

  defp overview_metrics,
    do:
      Enum.filter(metrics(), fn {key, _} ->
        key in [:delivered, :opened, :proxy_opened, :clicked, :bounced, :unsubscribed]
      end)

  defp delivery_reason("hard_bounce"), do: gettext("Permanent address failure")
  defp delivery_reason("unsubscribed"), do: gettext("Newsletter withdrawal")
  defp delivery_reason("invalid_domain"), do: gettext("Invalid domain: verify the address")
  defp delivery_reason("mailbox_full"), do: gettext("Mailbox full")

  defp delivery_reason("sender_reputation"),
    do: gettext("Sender reputation: review delivery configuration")

  defp delivery_reason("recipient_policy"), do: gettext("Recipient server policy")
  defp delivery_reason("transient"), do: gettext("Temporary delivery failure")
  defp delivery_reason(_), do: gettext("Unclassified soft bounce")

  defp state_label("accepted"), do: gettext("Accepted by provider")
  defp state_label("pending"), do: gettext("Pending")
  defp state_label("reserved"), do: gettext("Submission in progress")
  defp state_label("unknown"), do: gettext("Needs delivery review")
  defp state_label("failed"), do: gettext("Failed")
  defp state_label("excluded"), do: gettext("Excluded")
  defp state_label(value), do: value

  defp metrics,
    do: [
      {:delivered, gettext("Delivered")},
      {:opened, gettext("Observed opens")},
      {:proxy_opened, gettext("Proxy opens")},
      {:clicked, gettext("Observed clicks")},
      {:bounced, gettext("Bounced")},
      {:blocked, gettext("Blocked")},
      {:complained, gettext("Complaints")},
      {:unsubscribed, gettext("Provider unsubscribes")}
    ]
end
