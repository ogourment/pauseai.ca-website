defmodule PauseAiCaWeb.AssistantSettingsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Assistant

  def mount(_params, _session, socket) do
    if Assistant.eligible?(socket.assigns.current_scope) do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(PauseAiCa.PubSub, "agent_assistant:settings")
        Process.send_after(self(), :refresh_readiness, 15_000)
      end

      {:ok, reload(assign(socket, page_title: gettext("Assistant"), error: nil))}
    else
      {:ok, redirect(socket, to: "/")}
    end
  end

  def handle_info(:assistant_settings_changed, socket), do: {:noreply, reload(socket)}

  def handle_info(:refresh_readiness, socket) do
    Process.send_after(self(), :refresh_readiness, 15_000)

    if Assistant.eligible?(socket.assigns.current_scope),
      do: {:noreply, refresh_readiness(socket)},
      else: {:noreply, redirect(socket, to: "/")}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  def handle_event("enable", _, socket), do: change(socket, true)
  def handle_event("disable", _, socket), do: change(socket, false)

  def handle_event(
        "token-limit",
        %{"assistant_settings" => %{"actor_id" => actor, "limit" => text}},
        socket
      )
      when is_binary(text) do
    result =
      with {limit, ""} <- Integer.parse(text),
           do: Assistant.set_token_limit(socket.assigns.current_scope, actor, limit)

    case result do
      {:ok, _} ->
        {:noreply, reload(assign(socket, error: nil))}

      _ ->
        {:noreply,
         reload(assign(socket, error: gettext("The token limit could not be changed.")))}
    end
  end

  def handle_event(_, _, socket),
    do: {:noreply, assign(socket, error: gettext("The token limit could not be changed."))}

  defp change(socket, value) do
    case Assistant.set_enabled(socket.assigns.current_scope, value) do
      {:ok, _} ->
        {:noreply, reload(assign(socket, error: nil))}

      _ ->
        {:noreply,
         reload(
           assign(socket,
             error:
               gettext("The assistant could not be changed. Check its readiness and your access.")
           )
         )}
    end
  end

  defp reload(socket) do
    pilot =
      case Assistant.token_usage(socket.assigns.current_scope) do
        {:ok, usage} -> Map.get(usage, :pilot)
        _ -> nil
      end

    socket
    |> refresh_readiness()
    |> assign(
      admins: Assistant.admin_usage(socket.assigns.current_scope),
      default_limit: Assistant.configuration()[:daily_token_limit],
      quota_ceiling: Assistant.configuration()[:max_daily_token_limit],
      instructions_access:
        PauseAiCa.Assistant.Instructions.permitted?(socket.assigns.current_scope),
      pilot: pilot
    )
  end

  defp refresh_readiness(socket) do
    config = Assistant.configuration()

    diagnostics =
      if config[:operations_adapter],
        do: nil,
        else: PauseAiCa.Assistant.Operations.diagnostics(config)

    assign(socket,
      enabled: PhoenixAgentAssistant.Store.enabled?(Assistant.store()),
      missing: Assistant.readiness(),
      diagnostics: diagnostics
    )
  end

  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="assistant"
      breadcrumb_context={
        PauseAiCaWeb.Navigation.assistant_breadcrumb_context(@current_scope, @locale)
      }
    >
      <div class="crm-surface space-y-6" id="assistant-settings">
        <section class="management-controls space-y-3">
          <h1 class="text-2xl font-bold">{gettext("Assistant")}</h1>
          <p>
            {gettext(
              "Help organizers use the website, review information and prepare their next action."
            )}
          </p>
          <.link
            id="assistant-activity-link"
            navigate={~p"/admin/assistant/activity?#{[locale: @locale]}"}
            class="underline"
          >{gettext("Activity & security")}</.link>
          <.link
            :if={@instructions_access}
            id="assistant-instructions-link"
            href={~p"/admin/assistant/instructions?#{[locale: @locale]}"}
            class="underline"
          >{gettext("Instructions")}</.link>
          <p id="assistant-status">{if @enabled, do: gettext("On"), else: gettext("Off")}</p>
          <p :if={@pilot} id="assistant-pilot-budget" role="status">
            {gettext("All-provider pilot · USD %{remaining} / %{limit} remaining through %{date} UTC",
              remaining: usd(@pilot.remaining_micros, @locale),
              limit: usd(@pilot.limit_micros, @locale),
              date: Calendar.strftime(@pilot.expires_at, "%Y-%m-%d %H:%M")
            )}
            {gettext(
              "Generation, safety reviews and unresolved usage count toward this shared ceiling."
            )}
          </p>
          <button
            :if={!@enabled}
            id="assistant-enable"
            phx-click="enable"
            disabled={@missing != []}
            class="btn btn-primary"
          >{gettext("Enable assistant")}</button>
          <button :if={@enabled} id="assistant-disable" phx-click="disable" class="btn btn-outline">{gettext(
            "Disable assistant"
          )}</button>
          <p :if={@error} role="alert">{@error}</p>
        </section>
        <section class="rounded-xl border border-stone-200 p-5 space-y-3" id="assistant-token-limits">
          <h2 class="text-lg font-bold">{gettext("Token usage and limits")}</h2>
          <p>
            {gettext(
              "Daily generation input and output tokens. Uncertain requests keep their reservation. Quotas reset at 00:00 UTC."
            )}
          </p>
          <p>{gettext("Default per admin: %{limit} tokens/day", limit: @default_limit)}</p>
          <p class="text-sm" id="assistant-cost-explanation">
            {gettext(
              "USD service value may use configured estimates and does not determine cash paid after credits. Unknown holds are conservative limits, not charges."
            )}
          </p>
          <div class="paa-data-table">
            <table role="table">
              <thead role="rowgroup">
                <tr role="row">
                  <th role="columnheader" scope="col">{gettext("Admin")}</th><th
                    role="columnheader"
                    scope="col"
                  >
                    {gettext("Input")}
                  </th><th role="columnheader" scope="col">{gettext("Output")}</th><th
                    role="columnheader"
                    scope="col"
                  >
                    {gettext("Reserved")}
                  </th><th role="columnheader" scope="col">{gettext("Remaining")}</th><th
                    role="columnheader"
                    scope="col"
                  >
                    {gettext("Daily limit")}
                  </th><th role="columnheader" scope="col">{gettext("USD service value")}</th>
                </tr>
              </thead>
              <tbody role="rowgroup">
                <tr :for={admin <- @admins} role="row">
                  <td role="cell" data-label={gettext("Admin")}>
                    {admin.email || gettext("Unavailable account")}
                    <span :if={!admin.current_admin} class="block text-xs">{gettext("Former admin")}</span>
                    <span :if={is_nil(admin.email)} class="block text-xs break-all">{admin.id}</span>
                  </td>
                  <%= case admin.usage do %>
                    <% {:ok, usage} -> %>
                      <td role="cell" data-label={gettext("Input")}>{usage.reported_input}</td><td
                        role="cell"
                        data-label={gettext("Output")}
                      >
                        {usage.reported_output}
                      </td><td role="cell" data-label={gettext("Reserved")}>
                        {usage.held_tokens}
                      </td><td role="cell" data-label={gettext("Remaining")}>
                        {usage.remaining_tokens}
                      </td><td role="cell" data-label={gettext("Daily limit")}>{usage.limit}</td>
                    <% _ -> %>
                      <td role="cell" data-label={gettext("Input")}>{gettext("Unavailable")}</td>
                      <td role="cell" data-label={gettext("Output")}>{gettext("Unavailable")}</td>
                      <td role="cell" data-label={gettext("Reserved")}>{gettext("Unavailable")}</td>
                      <td role="cell" data-label={gettext("Remaining")}>{gettext("Unavailable")}</td>
                      <td role="cell" data-label={gettext("Daily limit")}>
                        {gettext("Unavailable")}
                      </td>
                  <% end %>
                  <td
                    role="cell"
                    data-label={gettext("USD service value")}
                    id={"assistant-cost-" <> admin.id}
                  >
                    <%= case admin.spend do %>
                      <% {:ok, %{accounting: :ledger} = spend} -> %>
                        <span :if={settled_known?(spend)} class="block">{gettext(
                          "Settled value: USD %{amount}",
                          amount: usd(spend.settled_service_micros, @locale)
                        )}</span>
                        <span :if={!settled_known?(spend)} class="block">{gettext(
                          "No settled value yet"
                        )}</span>
                        <span class="block text-sm">{gettext("Unknown hold: USD %{amount}",
                          amount:
                            usd(
                              spend.unresolved_stage_hold_micros + spend.legacy_unobserved_hold_micros,
                              @locale
                            )
                        )}</span>
                        <details class="text-xs mt-1">
                          <summary class="cursor-pointer underline">
                            {gettext("Cost evidence")}
                          </summary>
                          <p>{evidence_amount(:estimate, spend, @locale)}</p>
                          <p>{evidence_amount(:reported, spend, @locale)}</p>
                          <p>
                            {gettext(
                              "Estimates and provider reports may cover the same stages; do not add them."
                            )}
                          </p>
                        </details>
                      <% {:ok, %{accounting: :reservations_only} = spend} -> %>
                        <span>{gettext("Reserved limit: USD %{amount}",
                          amount: usd(spend.reserved_cost_micros, @locale)
                        )}</span>
                        <span class="block text-xs">{gettext("Settled service value unavailable")}</span>
                      <% _ -> %>
                        <span>{gettext("Unavailable")}</span>
                    <% end %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <.form
            for={to_form(%{}, as: "assistant_settings")}
            id="assistant-token-limit-form"
            phx-submit="token-limit"
            class="flex flex-wrap items-end gap-3"
          >
            <.input
              id="assistant-admin-selector"
              name="assistant_settings[actor_id]"
              type="select"
              value=""
              label={gettext("Admin")}
              options={@admins |> Enum.filter(& &1.current_admin) |> Enum.map(&{&1.email, &1.id})}
            />
            <.input
              id="assistant-token-limit"
              name="assistant_settings[limit]"
              type="number"
              value={@default_limit}
              min="0"
              max={@quota_ceiling}
              required
              label={gettext("Daily token limit")}
            />
            <.button disabled={:audit_keys in @missing}>{gettext("Save limit")}</.button>
          </.form>
          <p class="text-sm">
            {gettext(
              "Set zero to stop new requests for that admin. Existing conversations are retained."
            )}
          </p>
        </section>
        <section
          :if={@missing != []}
          class="rounded-xl border border-stone-200 p-5 space-y-3"
          id="assistant-readiness"
        >
          <h2 class="text-lg font-bold">
            {if @enabled,
              do: gettext("Assistant temporarily unavailable"),
              else: gettext("Setup required")}
          </h2>
          <p>
            {gettext("Checks run automatically. New requests can resume when all checks pass.")}
          </p>
          <p :if={:audit_anchor in @missing}>
            {gettext(
              "The independent security receiver verifies the integrity of the assistant’s activity log."
            )}
          </p>
          <ul class="list-disc pl-5">
            <li :for={item <- @missing}>{readiness_label(item)}</li>
          </ul>
        </section>
        <section :if={@diagnostics} id="assistant-operational-check" class="text-sm space-y-2">
          <p :if={@diagnostics[:checked_at_utc]}>
            {gettext("Last operational check")}
            <time datetime={DateTime.to_iso8601(@diagnostics.checked_at_utc)}>
              {Calendar.strftime(@diagnostics.checked_at_utc, "%Y-%m-%d %H:%M:%S UTC")}
            </time>
          </p>
          <p :if={@diagnostics[:last_success_at_utc]}>
            {gettext("Last successful readiness check")}
            <time datetime={DateTime.to_iso8601(@diagnostics.last_success_at_utc)}>
              {Calendar.strftime(@diagnostics.last_success_at_utc, "%Y-%m-%d %H:%M:%S UTC")}
            </time>
          </p>
          <p :if={!@diagnostics.current}>{gettext("Current verification required")}</p>
          <p :if={@diagnostics[:failure_phase]}>
            {failure_phase(@diagnostics.failure_phase)} · {failure_reason(@diagnostics.failure_reason)}
          </p>
          <p :if={is_integer(@diagnostics[:elapsed_ms])}>
            {gettext("Verification duration %{milliseconds} ms",
              milliseconds: @diagnostics.elapsed_ms
            )}
          </p>
        </section>
      </div>
    </Layouts.management>
    """
  end

  defp failure_phase(:audit_confirmation), do: gettext("Independent audit verification")
  defp failure_phase(:readiness_audit), do: gettext("Independent audit verification")
  defp failure_phase(:readiness_alert), do: gettext("Operator alert audit verification")
  defp failure_phase(:operator_alerts), do: gettext("Verified operator alerts")
  defp failure_phase(:configuration), do: gettext("Configuration")
  defp failure_phase(:local_probe), do: gettext("Local readiness record")
  defp failure_phase(_), do: gettext("Readiness refresh")

  defp failure_reason(:not_configured), do: gettext("Configuration required")
  defp failure_reason(:unresolved_alerts), do: gettext("Unresolved operator alerts")
  defp failure_reason(_), do: gettext("Cause not supplied")

  defp settled_known?(spend),
    do:
      spend.request_count == 0 or
        Map.get(spend.state_counts, "reported", 0) + Map.get(spend.state_counts, "not_invoked", 0) >
          0

  defp usd(micros, locale) do
    amount =
      Integer.to_string(div(micros, 1_000_000)) <>
        "." <> String.pad_leading(Integer.to_string(rem(micros, 1_000_000)), 6, "0")

    if locale == "fr", do: String.replace(amount, ".", ","), else: amount
  end

  defp evidence_amount(:estimate, %{configured_estimate_stage_count: 0}, _),
    do: gettext("Configured estimate unavailable")

  defp evidence_amount(:estimate, spend, locale),
    do:
      ngettext(
        "Configured estimate: USD %{amount} (%{count} stage)",
        "Configured estimate: USD %{amount} (%{count} stages)",
        spend.configured_estimate_stage_count,
        amount: usd(spend.configured_estimate_micros, locale),
        count: spend.configured_estimate_stage_count
      )

  defp evidence_amount(:reported, %{provider_reported_stage_count: 0}, _),
    do: gettext("Provider report unavailable")

  defp evidence_amount(:reported, spend, locale),
    do:
      ngettext(
        "Provider report: USD %{amount} (%{count} stage)",
        "Provider report: USD %{amount} (%{count} stages)",
        spend.provider_reported_stage_count,
        amount: usd(spend.provider_reported_service_micros, locale),
        count: spend.provider_reported_stage_count
      )

  defp readiness_label(:spend_ledger), do: gettext("Per-admin spending ledger")
  defp readiness_label(:credit_allocation), do: gettext("Designated assistant credit allocation")
  defp readiness_label(:feature_catalogue), do: gettext("Verified website feature catalogue")
  defp readiness_label(:audit_keys), do: gettext("Protected audit storage")
  defp readiness_label(:models), do: gettext("Fast, Normal and High models")
  defp readiness_label(:provider), do: gettext("Generation provider connection")
  defp readiness_label(:moderation), do: gettext("Moderation checks")
  defp readiness_label(:jev), do: gettext("Jev safety review")
  defp readiness_label(:budget), do: gettext("Usage limits")
  defp readiness_label(:operator_alerts), do: gettext("Verified operator alerts")
  defp readiness_label(:audit_anchor), do: gettext("Independent audit verification")
  defp readiness_label(:price_policy), do: gettext("Verified cost limits")
  defp readiness_label(:instructions), do: gettext("Published application instructions")

  defp readiness_label(:stage_tracking),
    do: gettext("Required generation and safety spend tracking")

  defp readiness_label(:pilot_budget), do: gettext("Valid all-provider pilot ceiling")
end
