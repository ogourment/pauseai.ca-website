defmodule PauseAiCaWeb.NewslettersLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.{Newsletters, Volunteers}

  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Volunteers.superadmin?(socket.assigns.current_scope) do
      {:ok,
       assign(socket,
         locale: locale,
         page_title: gettext("Newsletter lists"),
         audience: nil,
         history: [],
         selected_id: nil,
         provider_state: :idle,
         error: nil
       )}
    else
      {:ok, denied(socket)}
    end
  end

  def handle_params(params, _, socket) do
    case Newsletters.audience_page(socket.assigns.current_scope, params) do
      {:ok, audience} ->
        {:noreply, assign(socket, audience: audience, params: params)}

      _ ->
        {:noreply, denied(socket)}
    end
  end

  def handle_event("filter", %{"filters" => filters}, socket),
    do: patch(socket, Map.merge(socket.assigns.params, Map.put(filters, "page", "1")))

  def handle_event("history", %{"id" => id}, socket) do
    case Newsletters.history(socket.assigns.current_scope, id) do
      {:ok, events} -> {:noreply, assign(socket, history: Enum.reverse(events), selected_id: id)}
      _ -> {:noreply, denied(socket)}
    end
  end

  def handle_event("refresh-provider", %{"id" => id}, socket) do
    if Volunteers.superadmin?(socket.assigns.current_scope) and
         socket.assigns.provider_state != :loading do
      scope = socket.assigns.current_scope

      {:noreply,
       socket
       |> assign(provider_state: :loading, error: nil)
       |> start_async(:provider, fn -> PauseAiCa.Newsletters.Provider.refresh(scope, id) end)}
    else
      {:noreply, denied(socket)}
    end
  end

  def handle_async(:provider, {:ok, {:ok, _}}, socket) do
    case Newsletters.audience_page(socket.assigns.current_scope, socket.assigns.params) do
      {:ok, audience} -> {:noreply, assign(socket, audience: audience, provider_state: :done)}
      _ -> {:noreply, denied(socket)}
    end
  end

  def handle_async(:provider, _, socket) do
    if Volunteers.superadmin?(socket.assigns.current_scope),
      do:
        {:noreply,
         assign(socket,
           provider_state: :failed,
           error:
             gettext(
               "Brevo could not be refreshed. Local consent and saved work are unchanged. Try again."
             )
         )},
      else: {:noreply, denied(socket)}
  end

  defp patch(socket, params) do
    if Volunteers.superadmin?(socket.assigns.current_scope),
      do:
        {:noreply,
         push_patch(socket,
           to: ~p"/manage/mail/newsletters?#{Map.put(params, "locale", socket.assigns.locale)}"
         )},
      else: {:noreply, denied(socket)}
  end

  defp denied(socket),
    do:
      socket
      |> assign(audience: nil, history: [], selected_id: nil)
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
      <section id="newsletters" class="crm-surface mx-auto max-w-6xl px-5 py-8">
        <nav aria-label={gettext("Emails")} class="mb-6 flex gap-5 border-b border-stone-300 pb-3">
          <.link navigate={~p"/manage/mail?locale=#{@locale}"} class="underline">{gettext("Drafts")}</.link>
          <.link
            patch={~p"/manage/mail/newsletters?locale=#{@locale}"}
            aria-current="page"
            class="font-bold"
          >{gettext("Newsletter lists")}</.link>
        </nav>
        <h1 class="text-3xl font-bold">{gettext("Newsletter lists")}</h1>
        <p class="mt-3">
          {gettext(
            "Manage confirmed subscribers, withdrawals and subscription history here. Compose emails from Drafts."
          )}
        </p>
        <p
          :if={@provider_state == :loading}
          id="newsletter-provider-status"
          role="status"
          class="mt-3"
        >
          {gettext("Refreshing Brevo status…")}
        </p>
        <p :if={@provider_state == :done} id="newsletter-provider-status" role="status" class="mt-3">
          {gettext("Brevo status refreshed.")}
        </p>
        <p :if={@error} id="newsletter-error" role="alert" class="mt-3 crm-error">{@error}</p>
        <div :if={@audience}>
          <h2 class="mt-8 text-xl font-semibold">{gettext("Newsletter audience")}</h2>
          <.form
            for={
              to_form(Map.merge(@audience.filters, %{"per" => to_string(@audience.per)}),
                as: "filters"
              )
            }
            id="newsletter-filters"
            phx-submit="filter"
            class="mt-6 flex flex-wrap items-end gap-3"
          >
            <.input
              name="filters[q]"
              value={@audience.filters["q"]}
              label={gettext("Find email or city")}
            />
            <.input
              name="filters[region]"
              value={@audience.filters["region"]}
              type="select"
              label={gettext("Geography")}
              options={[
                {gettext("All regions"), ""},
                {"Montréal", "Montréal"},
                {"ROQuébec", "ROQuébec"},
                {"ROCanada", "ROCanada"}
              ]}
            />
            <.input
              name="filters[per]"
              value={to_string(@audience.per)}
              type="select"
              label={gettext("Per page")}
              options={[10, 25, 50, 100]}
            />
            <button class="crm-button" type="submit">{gettext("Find")}</button>
          </.form>
          <dl id="newsletter-counts" class="my-5 flex flex-wrap gap-x-6 gap-y-2">
            <div :for={{status, count} <- @audience.counts}>
              <dt class="text-sm text-stone-600">{status_label(status)}</dt><dd class="font-semibold">
                {count}
              </dd>
            </div>
          </dl>
          <p :if={@audience.total == 0} id="newsletter-empty">
            {gettext("No newsletter signups match these filters.")}
          </p>
          <ul id="newsletter-audience" class="space-y-3">
            <li
              :for={row <- @audience.rows}
              id={"newsletter-#{row.subscription.id}"}
              class="rounded-lg border border-stone-300 p-4"
            >
              <p class="font-semibold break-all">{row.subscription.email}</p>
              <p class="mt-1 text-sm">
                {status_label(row.status)} · {row.subscription.region || gettext("Geography unknown")}
              </p>
              <p class="mt-1 text-sm text-stone-600">
                Brevo: {if row.provider,
                  do:
                    if(row.provider["email_blacklisted"],
                      do: gettext("Provider blocked"),
                      else: gettext("Provider not blocked")
                    ),
                  else: gettext("Not observed yet")}
                <span :if={row.provider}> · {row.provider["observed_at"]}</span>
              </p>
              <dl class="mt-2 text-sm">
                <div :if={row.subscription.requested_at}>
                  <dt class="inline text-stone-600">{gettext("Signup requested")}:</dt><dd class="inline">
                    {timestamp(row.subscription.requested_at)}
                  </dd>
                </div>
                <div :if={row.subscription.confirmed_at}>
                  <dt class="inline text-stone-600">{gettext("Confirmed")}:</dt><dd class="inline">
                    {timestamp(row.subscription.confirmed_at)}
                  </dd>
                </div>
                <div :if={row.subscription.withdrawn_at}>
                  <dt class="inline text-stone-600">{gettext("Withdrawn")}:</dt><dd class="inline">
                    {timestamp(row.subscription.withdrawn_at)}
                  </dd>
                </div>
              </dl>
              <div class="mt-3 flex flex-wrap gap-4">
                <button
                  type="button"
                  phx-click="history"
                  phx-value-id={row.subscription.id}
                  class="underline"
                >{gettext("Consent history")}</button>
                <button
                  type="button"
                  phx-click="refresh-provider"
                  phx-value-id={row.subscription.id}
                  disabled={@provider_state == :loading}
                  class="underline"
                >{gettext("Refresh Brevo status")}</button>
              </div>
            </li>
          </ul>
          <nav aria-label={gettext("Pagination")} class="mt-5 flex gap-5">
            <.link :if={@audience.page > 1} patch={page_path(assigns, @audience.page - 1)}>{gettext(
              "Previous"
            )}</.link>
            <span>{gettext("Page %{page} of %{pages}", page: @audience.page, pages: @audience.pages)}</span>
            <.link
              :if={@audience.page < @audience.pages}
              patch={page_path(assigns, @audience.page + 1)}
            >{gettext("Next")}</.link>
          </nav>
          <section :if={@selected_id} id="newsletter-history" class="mt-7">
            <h2 class="text-xl font-semibold">{gettext("Consent history")}</h2>
            <ol class="mt-3 space-y-2">
              <li :for={event <- @history}>
                <time>{timestamp(event.inserted_at)}</time>
                · {event_label(event.kind)}
                <span :if={event.kind == "provider_observed"}> · Brevo · {if event.evidence[
                                                                               "email_blacklisted"
                                                                             ],
                                                                             do:
                                                                               gettext(
                                                                                 "Provider blocked"
                                                                               ),
                                                                             else:
                                                                               gettext(
                                                                                 "Provider not blocked"
                                                                               )} · {event.evidence[
                  "observed_at"
                ]}</span>
              </li>
            </ol>
          </section>
        </div>
      </section>
    </Layouts.management>
    """
  end

  defp page_path(assigns, page),
    do:
      ~p"/manage/mail/newsletters?#{Map.merge(assigns.params, %{"page" => page, "locale" => assigns.locale})}"

  defp timestamp(date), do: Calendar.strftime(date, "%Y-%m-%d %H:%M UTC")
  defp status_label(:included), do: gettext("Eligible")
  defp status_label(:unconfirmed), do: gettext("Awaiting confirmation")
  defp status_label(:withdrawn), do: gettext("Withdrawn")
  defp status_label(:legacy_uncertain), do: gettext("Legacy evidence to review")
  defp status_label(:provider_blocked), do: gettext("Provider blocked")
  defp status_label(:suppressed), do: gettext("Suppressed")
  defp event_label("requested"), do: gettext("Explicit signup requested")
  defp event_label("confirmed"), do: gettext("Signup confirmed")
  defp event_label("withdrawn"), do: gettext("Consent withdrawn")
  defp event_label("legacy_observed"), do: gettext("Legacy evidence recorded")
  defp event_label("provider_observed"), do: gettext("Provider status observed")
  defp event_label("confirmation_attempted"), do: gettext("Confirmation delivery attempted")
  defp event_label("confirmation_delivery"), do: gettext("Confirmation delivery outcome")
  defp event_label(_), do: gettext("Consent activity")
end
