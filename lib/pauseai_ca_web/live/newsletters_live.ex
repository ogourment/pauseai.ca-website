defmodule PauseAiCaWeb.NewslettersLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.{Newsletters, Volunteers}
  alias PauseAiCa.Newsletters.Lists
  import PauseAiCaWeb.NewsletterAudienceLabels

  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Volunteers.superadmin?(socket.assigns.current_scope) do
      {:ok,
       assign(socket,
         locale: locale,
         page_title: gettext("Newsletter lists"),
         audience: nil,
         mailing_lists: [],
         editing_list: nil,
         list_form: to_form(Lists.form(nil), as: "list"),
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
        {:ok, lists} = Lists.list(socket.assigns.current_scope)
        {:noreply, assign(socket, audience: audience, params: params, mailing_lists: lists)}

      _ ->
        {:noreply, denied(socket)}
    end
  end

  def handle_event("list-compose", %{"id" => id}, socket) do
    case PauseAiCa.Newsletters.Drafts.create_for_list(socket.assigns.current_scope, id) do
      {:ok, draft} ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/manage/mail/drafts/#{draft.id}?locale=#{socket.assigns.locale}"
         )}

      _ ->
        {:noreply, denied(socket)}
    end
  end

  def handle_event("list-new", params, socket) do
    attrs =
      if params["preset"] == "montreal",
        do:
          Map.merge(Lists.form(nil), %{
            "name" => "Montréal",
            "city" => "Montréal",
            "region" => "Montréal"
          }),
        else: Lists.form(nil)

    {:noreply,
     assign(socket, editing_list: nil, list_form: to_form(attrs, as: "list"), error: nil)}
  end

  def handle_event("list-edit", %{"id" => id}, socket) do
    case Lists.get(socket.assigns.current_scope, id) do
      {:ok, list} ->
        {:noreply,
         assign(socket,
           editing_list: list,
           list_form: to_form(Lists.form(list), as: "list"),
           error: nil
         )}

      _ ->
        {:noreply, denied(socket)}
    end
  end

  def handle_event("list-save", %{"list" => attrs}, socket) do
    case Lists.save(socket.assigns.current_scope, socket.assigns.editing_list, attrs) do
      {:ok, list} ->
        {:ok, lists} = Lists.list(socket.assigns.current_scope)
        params = Map.merge(socket.assigns.params, %{"list_id" => list.id, "page" => "1"})
        {:ok, audience} = Newsletters.audience_page(socket.assigns.current_scope, params)

        socket =
          socket
          |> assign(
            mailing_lists: lists,
            editing_list: list,
            audience: audience,
            list_form: to_form(Lists.form(list), as: "list"),
            error: nil
          )
          |> put_flash(:info, gettext("List saved."))

        patch(socket, params)

      {:error, :unauthorized} ->
        {:noreply, denied(socket)}

      {:error, :stale} ->
        {:noreply,
         assign(socket,
           error: gettext("This list changed. Reopen it before editing."),
           list_form: to_form(attrs, as: "list")
         )}

      _ ->
        {:noreply,
         assign(socket,
           error:
             gettext(
               "Enter a list name and at least one valid city, region or three-character FSA. Your entries have been kept."
             ),
           list_form: to_form(attrs, as: "list")
         )}
    end
  end

  def handle_event("list-archive", %{"id" => id}, socket) do
    with {:ok, list} <- Lists.get(socket.assigns.current_scope, id),
         {:ok, _} <- Lists.archive(socket.assigns.current_scope, list),
         {:ok, lists} <- Lists.list(socket.assigns.current_scope) do
      socket =
        assign(socket,
          mailing_lists: lists,
          editing_list: nil,
          list_form: to_form(Lists.form(nil), as: "list")
        )

      patch(socket, Map.merge(socket.assigns.params, %{"list_id" => "", "page" => "1"}))
    else
      _ -> {:noreply, denied(socket)}
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
    params = if params["list_id"] == "", do: Map.delete(params, "list_id"), else: params

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
        <section id="dynamic-mailing-lists" class="mt-8 space-y-4">
          <h2 class="text-xl font-semibold">{gettext("Dynamic mailing lists")}</h2>
          <p>
            {gettext(
              "Rules update membership automatically. Matching a list does not grant newsletter consent."
            )}
          </p>
          <ul class="space-y-3">
            <li
              :for={list <- @mailing_lists}
              id={"mailing-list-#{list.id}"}
              class="flex flex-wrap items-center gap-4 rounded-lg border border-stone-300 p-3"
            >
              <strong>{list.name}</strong>
              <button type="button" phx-click="list-compose" phx-value-id={list.id} class="crm-button">{gettext(
                "Compose"
              )}</button>
              <.link
                patch={~p"/manage/mail/newsletters?#{%{locale: @locale, list_id: list.id}}"}
                class="underline"
              >{gettext("Preview members")}</.link>
              <button type="button" phx-click="list-edit" phx-value-id={list.id} class="underline">{gettext(
                "Edit rules"
              )}</button>
              <button type="button" phx-click="list-archive" phx-value-id={list.id} class="underline">{gettext(
                "Archive"
              )}</button>
            </li>
          </ul>
          <div class="flex gap-4">
            <button type="button" phx-click="list-new" class="underline">{gettext("New list")}</button>
            <button type="button" phx-click="list-new" phx-value-preset="montreal" class="underline">{gettext(
              "Use Montréal rules"
            )}</button>
          </div>
          <.form
            for={@list_form}
            id="mailing-list-form"
            phx-submit="list-save"
            class="grid gap-3 rounded-lg border border-stone-300 p-4 md:grid-cols-2"
          >
            <.input field={@list_form[:name]} label={gettext("List name")} maxlength="120" />
            <.input
              field={@list_form[:match]}
              type="select"
              label={gettext("Combine rules")}
              options={[
                {gettext("Match any rule (OR)"), "any"},
                {gettext("Match every rule (AND)"), "all"}
              ]}
            />
            <.input
              field={@list_form[:city]}
              label={gettext("Cities")}
              placeholder="Montréal, Laval"
            />
            <.input
              field={@list_form[:region]}
              type="select"
              label={gettext("Recorded region")}
              options={[
                {gettext("No region rule"), ""},
                {"Montréal", "Montréal"},
                {"ROQuébec", "ROQuébec"},
                {"ROCanada", "ROCanada"}
              ]}
            />
            <.input field={@list_form[:fsas]} label={gettext("FSAs")} placeholder="H2X, H2Y" />
            <p class="text-sm text-stone-600">
              {gettext(
                "Separate cities and three-character postal prefixes with commas. Empty fields add no rule; unknown geography never matches a rule."
              )}
            </p>
            <button
              type="submit"
              class="crm-button justify-self-start"
              phx-disable-with={gettext("Saving…")}
            >{gettext("Save list")}</button>
          </.form>
        </section>
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
              name="filters[list_id]"
              value={@params["list_id"] || ""}
              type="select"
              label={gettext("Mailing list")}
              options={
                [{gettext("All subscribers"), ""}] ++ Enum.map(@mailing_lists, &{&1.name, &1.id})
              }
            />
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
              <p :if={row.subscription.name} class="mt-1">{row.subscription.name}</p>
              <p :if={row.subscription.fsa} class="mt-1 text-sm">
                {gettext("Postal area")}: {row.subscription.fsa}
              </p>
              <p class="mt-1 text-sm">
                <span :if={row.matched_fields != []} class="block">{gettext("Matches: %{fields}",
                  fields: Enum.map_join(row.matched_fields, ", ", &rule_label/1)
                )}</span>
                {status_label(row.status)} · {row.subscription.city || row.subscription.region ||
                  gettext("Geography unknown")}
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
  defp event_label("requested"), do: gettext("Explicit signup requested")
  defp event_label("confirmed"), do: gettext("Signup confirmed")
  defp event_label("withdrawn"), do: gettext("Consent withdrawn")
  defp event_label("legacy_observed"), do: gettext("Legacy evidence recorded")
  defp event_label("provider_observed"), do: gettext("Provider status observed")
  defp event_label("confirmation_attempted"), do: gettext("Confirmation delivery attempted")
  defp event_label("confirmation_delivery"), do: gettext("Confirmation delivery outcome")
  defp event_label(_), do: gettext("Consent activity")
end
