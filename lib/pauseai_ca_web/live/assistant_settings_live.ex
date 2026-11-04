defmodule PauseAiCaWeb.AssistantSettingsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Assistant

  def mount(_params, _session, socket) do
    if Assistant.eligible?(socket.assigns.current_scope) do
      if connected?(socket),
        do: Phoenix.PubSub.subscribe(PauseAiCa.PubSub, "agent_assistant:settings")

      {:ok, reload(assign(socket, page_title: gettext("Assistant"), error: nil))}
    else
      {:ok, redirect(socket, to: "/")}
    end
  end

  def handle_info(:assistant_settings_changed, socket), do: {:noreply, reload(socket)}
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

  defp reload(socket),
    do:
      assign(socket,
        enabled: PhoenixAgentAssistant.Store.enabled?(Assistant.store()),
        missing: Assistant.readiness(),
        admins: Assistant.admin_usage(socket.assigns.current_scope),
        default_limit: Assistant.configuration()[:daily_token_limit],
        quota_ceiling: Assistant.configuration()[:max_daily_token_limit]
      )

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
          <p id="assistant-status">{if @enabled, do: gettext("On"), else: gettext("Off")}</p>
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
              "Daily Claude input and output tokens. Uncertain requests keep their reservation. Quotas reset at 00:00 UTC; safety-review charges have a separate cost ceiling."
            )}
          </p>
          <p>{gettext("Default per admin: %{limit} tokens/day", limit: @default_limit)}</p>
          <div class="overflow-x-auto">
            <table class="w-full text-left text-sm">
              <thead>
                <tr>
                  <th>{gettext("Admin")}</th><th>{gettext("Input")}</th><th>{gettext("Output")}</th><th>
                    {gettext("Reserved")}
                  </th><th>{gettext("Remaining")}</th><th>{gettext("Daily limit")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={admin <- @admins}>
                  <td class="p-2">{admin.email}</td>
                  <%= case admin.usage do %>
                    <% {:ok, usage} -> %>
                      <td>{usage.reported_input}</td><td>{usage.reported_output}</td><td>
                        {usage.held_tokens}
                      </td><td>{usage.remaining_tokens}</td><td>{usage.limit}</td>
                    <% _ -> %>
                      <td colspan="5">{gettext("Unavailable")}</td>
                  <% end %>
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
              options={Enum.map(@admins, &{&1.email, &1.id})}
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
          <h2 class="text-lg font-bold">{gettext("Setup required")}</h2>
          <p>
            {gettext(
              "The assistant stays off until its protected storage, safety checks, usage limits and operator alerts are ready."
            )}
          </p>
          <ul class="list-disc pl-5">
            <li :for={item <- @missing}>{readiness_label(item)}</li>
          </ul>
        </section>
      </div>
    </Layouts.management>
    """
  end

  defp readiness_label(:feature_catalogue), do: gettext("Verified website feature catalogue")
  defp readiness_label(:audit_keys), do: gettext("Protected audit storage")
  defp readiness_label(:models), do: gettext("Fast, Normal and High models")
  defp readiness_label(:provider), do: gettext("Claude connection")
  defp readiness_label(:moderation), do: gettext("Moderation checks")
  defp readiness_label(:jev), do: gettext("Jev safety review")
  defp readiness_label(:budget), do: gettext("Usage limits")
  defp readiness_label(:operator_alerts), do: gettext("Verified operator alerts")
  defp readiness_label(:audit_anchor), do: gettext("Independent audit verification")
  defp readiness_label(:price_policy), do: gettext("Verified cost limits")
end
