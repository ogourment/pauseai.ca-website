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
       result: nil,
       provider: nil,
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
         assign(socket, records: records, result: nil, page: page, provider: nil, error: nil)}

      {:ok, result} ->
        {:noreply, assign(socket, result: result, provider: nil, error: nil)}

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
    if PauseAiCa.Volunteers.superadmin?(socket.assigns.current_scope),
      do: {:noreply, assign(socket, provider: provider, loading: false)},
      else:
        {:noreply,
         socket
         |> assign(result: nil, provider: nil, loading: false)
         |> redirect(to: ~p"/dashboard")}
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

  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="mail"
    >
      <section class="crm-surface mx-auto max-w-6xl px-5 py-8">
        <PauseAiCaWeb.MailNavigation.tabs locale={@locale} active="results" />
        <h1 class="text-3xl font-bold">{gettext("Sent & results")}</h1>
        <p class="mt-3">
          {gettext(
            "Open a send to inspect its frozen audience, sending status and provider observations. Drafts that have never been sent are in Drafts."
          )}
        </p>
        <div :if={is_nil(@result)} class="mt-6 space-y-4">
          <p :if={@records == []}>{gettext("No sends on this page.")}</p>
          <article :for={batch <- @records} class="rounded-lg border border-stone-300 p-4">
            <.link
              class="text-lg font-bold underline"
              navigate={~p"/manage/mail/results/#{batch.id}?locale=#{@locale}"}
            >{batch.subject}</.link>
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
            <strong>{gettext("Local unsubscribes from this send")}: {@result.local_unsubscribed}</strong>
          </p>
          <p>
            {gettext(
              "Exact link attribution is recorded from this release onward. Earlier local withdrawals cannot be attributed reliably to a particular send."
            )}
          </p>
          <h3 class="text-xl font-semibold">{gettext("Campaign performance")}</h3>
          <button type="button" phx-click="refresh" disabled={@loading} class="crm-button">{if @loading,
            do: gettext("Refreshing…"),
            else: gettext("Refresh provider results")}</button>
          <p :if={@error} role="alert" class="crm-error">{@error}</p>
          <p :if={is_nil(@provider)}>
            {gettext("Provider observations have not been loaded. Unavailable results are not zero.")}
          </p>
          <div :if={@provider}>
            <p>{gettext("Updated")}: {DateTime.to_iso8601(@provider.refreshed_at)}</p>
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
                "Counts are unique recipients with an observed event for this send. Delivery means receiving-server acceptance. Opens and clicks can be automated; proxy opens are separate. Unsubscribes count provider events only; local unsubscribes are counted separately using the exact withdrawal link."
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
