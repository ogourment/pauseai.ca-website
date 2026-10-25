defmodule PauseAiCa.Chat.SlackHTTP do
  @moduledoc false
  @origin "https://slack.com/api/"
  @reads ~w(auth.test users.info conversations.info conversations.history conversations.replies chat.getPermalink)
  def read(method, token, params) when method in @reads do
    request(method, headers: [{"authorization", "Bearer " <> token}], params: params)
  end

  def post_message(token, params),
    do:
      request("chat.postMessage", headers: [{"authorization", "Bearer " <> token}], json: params)

  def oauth(code, config) do
    case request("oauth.v2.access",
           auth: {:basic, config.client_id <> ":" <> config.client_secret},
           form: [code: code, redirect_uri: config.redirect_uri]
         ) do
      {:ok, 200, body} -> {:ok, body}
      _ -> {:error, :authorization_failed}
    end
  end

  defp request(method, options) do
    verb = if method in @reads, do: :get, else: :post

    case Req.request(
           [
             url: @origin <> method,
             method: verb,
             retry: false,
             redirect: false,
             receive_timeout: 5_000,
             connect_options: [timeout: 5_000]
           ] ++ options
         ) do
      {:ok, %{status: status, body: body}} when is_map(body) -> {:ok, status, body}
      _ -> {:error, :provider_unavailable}
    end
  rescue
    _ -> {:error, :provider_unavailable}
  end
end
