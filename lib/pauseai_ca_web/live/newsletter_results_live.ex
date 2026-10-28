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
        else: Results.list(socket.assigns.current_scope, page)

    case response do
      {:ok, records} when is_list(records) ->
        {:noreply,
         assign(socket,
           senders: Results.senders(socket.assigns.current_scope, Enum.map(records, & &1.id)),
           recipient_summaries:
             Results.recipient_summaries(socket.assigns.current_scope, Enum.map(records, & &1.id)),
           records: records,
           sync_status: PauseAiCa.Newsletters.ProviderSync.status(),
           result: nil,
           page: page,
           provider: nil,
           error: nil
         )}

      {:ok, result} ->
        socket =
          assign(socket,
            senders: Results.senders(socket.assigns.current_scope, [result.batch.id]),
            result: result,
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

  defp recipient_count_label(count),
    do: ngettext("%{count} recipient", "%{count} recipients", count, count: count)

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
        <section id="provider-synchronization" class="my-5 rounded border border-stone-300 p-4">
          <h2 class="font-semibold">{gettext("Provider synchronization")}</h2>
          <p :if={!PauseAiCa.Newsletters.ProviderSyncWorker.enabled?()}>
            {gettext("Automatic synchronization is disabled in this environment.")}
          </p>
          <p :if={PauseAiCa.Newsletters.ProviderSyncWorker.enabled?()}>
            {gettext(
              "Read-only reconciliation runs every 15 minutes. Recent history overlaps, with a daily scan of the available 90-day history."
            )}
          </p>
          <p :if={@sync_status && @sync_status.last_success_at}>
            {gettext("Last successful reconciliation")}:
            <time datetime={DateTime.to_iso8601(@sync_status.last_success_at)}>{Calendar.strftime(
              @sync_status.last_success_at,
              "%Y-%m-%d %H:%M UTC"
            )}</time>
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
        </section>
        <div :if={is_nil(@result)} class="mt-6 space-y-4">
          <p :if={@records == []}>{gettext("No sends on this page.")}</p>
          <article :for={batch <- @records} class="rounded-lg border border-stone-300 p-4">
            <.link
              class="text-lg font-bold underline"
              navigate={~p"/manage/mail/results/#{batch.id}?locale=#{@locale}"}
            >{batch.subject}</.link>
            <p class="font-semibold">
              {recipient_count_label(Map.get(@recipient_summaries, batch.id, %{count: 0}).count)}
            </p>
            <p class="break-words" data-recipient-identities>
              {Enum.join(Map.get(@recipient_summaries, batch.id, %{emails: []}).emails, ", ")}
              <span :if={Map.get(@recipient_summaries, batch.id, %{count: 0}).count > 3}>
                · {gettext("and %{count} more", count: @recipient_summaries[batch.id].count - 3)}
              </span>
            </p>
            <p>{gettext("Sent by")}: {sender_labels(@senders, batch.id)}</p>
            <p>
              {gettext("Prepared")}: {Date.to_iso8601(DateTime.to_date(batch.inserted_at))} · {batch.edition} · {batch.delivery_environment}
            </p>
          </article>
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
          <h2 class="text-2xl font-bold">{@result.batch.subject}</h2>
          <p>{gettext("Sent by")}: {sender_labels(@senders, @result.batch.id)}</p>
          <p>
            {gettext("From address")}: {@result.batch.sender_name} &lt;{@result.batch.sender_email}&gt;
          </p>
          <p>
            {@result.batch.edition} · {@result.batch.delivery_environment} · {@result.report.total} {gettext(
              "recipients"
            )}
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
