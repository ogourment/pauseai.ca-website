defmodule PauseAiCa.ExternalServices do
  @moduledoc "Public operation names for outbound HTTP logs. Paths can contain credentials or personal data."

  def classify(%{host: "api.brevo.com", path: path}) do
    operation =
      case path do
        "/v3/smtp/email" ->
          :send_email

        "/v3/smtp/statistics/events" ->
          :delivery_history

        "/v3/contacts" ->
          :upsert_contact

        "/v3/contacts/" <> rest ->
          if String.ends_with?(rest, "/campaignStats"), do: :campaign_history, else: :get_contact

        "/v3/inbound/attachments/" <> _ ->
          :download_attachment

        _ ->
          :other
      end

    {:brevo, operation}
  end

  def classify(%{host: "api.openai.com", path: "/v1/moderations"}), do: {:openai, :moderation}
  def classify(%{host: "api.openai.com"}), do: {:openai, :generation}
  def classify(%{host: "api.anthropic.com"}), do: {:anthropic, :generation}
  def classify(%{host: "openrouter.ai"}), do: {:openrouter, :generation}

  def classify(%{host: host}) when host in ["jevtypesafeai.com", "api.typesafe.ai"],
    do: {:jev, :safety_review}

  def classify(%{host: "represent.opennorth.ca"}), do: {:represent, :postcode_lookup}
  def classify(%{host: "api.telegram.org"}), do: {:telegram, :send_alert}
  def classify(%{host: "www.bankofcanada.ca"}), do: {:bank_of_canada, :exchange_rate}
  def classify(%{host: "manifund.org"}), do: {:manifund, :funding}
  def classify(%{host: "raw.githubusercontent.com"}), do: {:github, :read_source}
  def classify(%{host: "slack.com", path: "/api/oauth.v2.access"}), do: {:slack, :oauth}
  def classify(%{host: "slack.com", path: "/api/chat.postMessage"}), do: {:slack, :send_message}
  def classify(%{host: "slack.com"}), do: {:slack, :read_api}

  def classify(%{host: host, scheme: scheme, port: port, path: path}) do
    config = Application.get_env(:pauseai_ca, :agent_assistant, [])

    Enum.find_value([:alert_delivery, :anchor], {:other_external, :unknown}, fn service ->
      with endpoint when is_binary(endpoint) <- get_in(config, [service, :endpoint]),
           %URI{host: ^host, port: ^port, scheme: configured_scheme, path: prefix} <-
             URI.parse(endpoint),
           true <- configured_scheme == to_string(scheme) and is_binary(prefix) do
        prefix =
          if service == :anchor, do: String.replace_suffix(prefix, "/journal", ""), else: prefix

        if path == prefix or String.starts_with?(path, prefix <> "/"),
          do: {:assistant_receiver, service}
      else
        _ -> nil
      end
    end)
  end
end
