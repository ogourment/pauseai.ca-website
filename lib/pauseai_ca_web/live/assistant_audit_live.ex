defmodule PauseAiCaWeb.AssistantAuditLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Assistant
  alias PauseAiCa.Assistant.Audit
  alias PhoenixAgentAssistant.{AuditLog, Components}

  @impl true
  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    socket =
      assign(socket,
        locale: locale,
        page_title: gettext("Activity & security"),
        rows: [],
        accounts: [],
        error: nil,
        next_cursor: nil,
        has_more: false,
        scan_limited: false,
        filters: %{"actor" => "", "kind" => ""}
      )

    if Assistant.eligible?(socket.assigns.current_scope),
      do: {:ok, socket},
      else: {:ok, deny(socket)}
  end

  @impl true
  def handle_params(params, _, socket) do
    scope = socket.assigns.current_scope

    if Assistant.eligible?(scope) do
      case Audit.page(scope, params) do
        {:ok, page} ->
          case Audit.accounts(scope, Enum.map(page.rows, & &1.actor_id)) do
            {:ok, %{choices: accounts, labels: labels}} ->
              rows =
                Enum.map(page.rows, fn row ->
                  Map.merge(row, %{
                    actor_label: Map.get(labels, row.actor_id) || gettext("Unlisted account"),
                    time_label: Calendar.strftime(row.inserted_at, "%Y-%m-%d %H:%M:%S UTC"),
                    activity_label: activity(row.kind),
                    outcome_label: outcome(row.outcome)
                  })
                end)

              {:noreply,
               assign(socket,
                 rows: rows,
                 accounts: accounts,
                 next_cursor: page.next_cursor,
                 has_more: page.has_more,
                 scan_limited: page.scan_limited,
                 error: nil,
                 filters: %{"actor" => params["actor"] || "", "kind" => params["kind"] || ""}
               )}

            _ ->
              {:noreply, deny(socket)}
          end

        {:error, :forbidden} ->
          {:noreply, deny(socket)}

        _ ->
          {:noreply,
           assign(socket,
             rows: [],
             accounts: [],
             next_cursor: nil,
             has_more: false,
             scan_limited: false,
             error: gettext("Activity cannot be loaded securely.")
           )}
      end
    else
      {:noreply, deny(socket)}
    end
  end

  @impl true
  def handle_event(event, params, socket) do
    if Assistant.eligible?(socket.assigns.current_scope) do
      query =
        case event do
          "filter" ->
            if(is_map(params["audit"]),
              do: Map.take(params["audit"], ["actor", "kind"]),
              else: %{}
            )

          "next" ->
            Map.put(socket.assigns.filters, "cursor", socket.assigns.next_cursor)

          _ ->
            socket.assigns.filters
        end

      {:noreply,
       push_patch(socket,
         to: ~p"/admin/assistant/activity?#{Map.put(query, "locale", socket.assigns.locale)}"
       )}
    else
      {:noreply, deny(socket)}
    end
  end

  defp deny(socket),
    do: socket |> assign(rows: [], accounts: [], next_cursor: nil) |> redirect(to: "/")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="assistant"
      breadcrumb_context={PauseAiCaWeb.Navigation.breadcrumb_context(@current_scope, @locale)}
    >
      <div
        id="assistant-audit"
        data-breadcrumb-label={gettext("Activity & security")}
        class="crm-surface space-y-5"
      >
        <div class="management-controls space-y-3">
          <.link navigate={~p"/admin/assistant?#{[locale: @locale]}"}>{gettext("Back to assistant")}</.link>
          <h1 class="text-2xl font-bold">{gettext("Activity & security")}</h1>
          <p>{gettext("Protected activity metadata. Message content is not displayed.")}</p>
          <form id="assistant-audit-filters" phx-change="filter" class="flex flex-wrap gap-3">
            <.input
              type="select"
              id="audit-kind"
              name="audit[kind]"
              label={gettext("Activity")}
              value={@filters["kind"]}
              options={
                [{gettext("All activity"), ""}] ++ Enum.map(AuditLog.kinds(), &{activity(&1), &1})
              }
            />
            <.input
              type="select"
              id="audit-actor"
              name="audit[actor]"
              label={gettext("Account")}
              value={@filters["actor"]}
              options={
                [{gettext("All accounts"), ""}] ++
                  Enum.map(@accounts, &{&1.email || gettext("Unlisted account"), &1.id})
              }
            />
          </form>
        </div>
        <p :if={@error} role="alert">{@error}</p>
        <Components.audit_table
          id="assistant-audit-table"
          eligible={@error == nil}
          rows={@rows}
          labels={
            %{
              time: gettext("Time"),
              actor: gettext("Account"),
              activity: gettext("Activity"),
              outcome: gettext("Outcome"),
              tokens: gettext("Tokens")
            }
          }
        />
        <p :if={@error == nil and @rows == []} id="assistant-audit-empty">
          {if @has_more,
            do: gettext("No matching activity on this page. Continue to search older records."),
            else: gettext("No matching activity in the remaining records.")}
        </p>
        <p :if={@scan_limited}>
          {gettext("This page searched a bounded set of protected records. More records remain.")}
        </p>
        <details class="text-sm opacity-70">
          <summary class="min-h-11 cursor-pointer">{gettext("About this view")}</summary>
          <p>
            {gettext(
              "Up to 100 recorded accounts appear in the filter, including former administrators. — means token usage is unknown."
            )}
          </p>
          <p>
            {gettext(
              "Each displayed record is checked for authenticity. This page does not verify the complete history or its order. UTC times come from the database and are not protected event timestamps."
            )}
          </p>
        </details>
        <div class="flex gap-3">
          <button
            id="assistant-audit-first"
            type="button"
            phx-click="first"
            class="btn btn-outline min-h-11"
          >{gettext("Newest")}</button>
          <button
            :if={@has_more}
            id="assistant-audit-next"
            type="button"
            phx-click="next"
            class="btn btn-outline min-h-11"
          >{gettext("Older")}</button>
        </div>
      </div>
    </Layouts.management>
    """
  end

  defp activity("request"), do: gettext("Request recorded")
  defp activity("request_reserved"), do: gettext("Budget reserved")
  defp activity("provider_output"), do: gettext("Response recorded")
  defp activity("response_released"), do: gettext("Response released")
  defp activity("safety_review"), do: gettext("Safety review")
  defp activity("request_held"), do: gettext("Request held")
  defp activity("request_finished"), do: gettext("Request finished")
  defp activity("alert_queued"), do: gettext("Operator alert queued")
  defp activity("alert_outcome"), do: gettext("Alert intake outcome")
  defp activity("enabled_changed"), do: gettext("Assistant setting changed")
  defp activity("mode_changed"), do: gettext("Mode changed")
  defp activity("token_limit_changed"), do: gettext("Token limit changed")
  defp activity("conversation_started"), do: gettext("Conversation started")
  defp activity("audit_viewed"), do: gettext("Audit accessed")
  defp activity(_), do: gettext("Recorded activity")
  defp outcome("released"), do: gettext("Released")
  defp outcome("held"), do: gettext("Held")
  defp outcome("reserved"), do: gettext("Reserved")
  defp outcome("succeeded"), do: gettext("Succeeded")
  defp outcome("failed"), do: gettext("Failed")
  defp outcome("unknown"), do: gettext("Unknown")
  defp outcome("accepted"), do: gettext("Accepted")
  defp outcome("pending"), do: gettext("Pending")
  defp outcome("submitting"), do: gettext("Submitting")
  defp outcome(_), do: gettext("Recorded")
end
