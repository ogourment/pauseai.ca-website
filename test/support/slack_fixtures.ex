defmodule PauseAiCa.SlackFixtures do
  @moduledoc false
  alias PauseAiCa.Chat.Slack
  alias PhoenixCommunity.Slack.OAuth

  @keys [
    :slack,
    :slack_enabled,
    :slack_test_revoked,
    :slack_test_post_mode,
    :slack_test_post_count
  ]

  def configure! do
    saved = Map.new(@keys, &{&1, Application.get_env(:pauseai_ca, &1, :absent)})
    Application.put_env(:pauseai_ca, :slack_enabled, true)
    Application.put_env(:pauseai_ca, :slack_test_revoked, false)
    Application.put_env(:pauseai_ca, :slack_test_post_mode, :sent)
    Application.put_env(:pauseai_ca, :slack_test_post_count, 0)

    Application.put_env(:pauseai_ca, :slack, %{
      client_id: "synthetic-client",
      client_secret: "SyntheticSlackReview",
      team_id: "T1",
      app_id: "A1",
      signing_secret: "synthetic-signing",
      redirect_uri: "https://example.org/community/slack/callback",
      channel_ids: ["C1", "C2"],
      channel_names: %{"C1" => "general", "C2" => "private-review"},
      authorize: fn _, channel, _ -> channel == "C1" end,
      read_transport: &read/3,
      oauth_transport: &oauth/2,
      post_transport: &post/2
    })

    saved
  end

  def restore!(saved),
    do:
      Enum.each(saved, fn {key, value} ->
        if value == :absent,
          do: Application.delete_env(:pauseai_ca, key),
          else: Application.put_env(:pauseai_ca, key, value)
      end)

  def connect!(scope) do
    nonce = String.duplicate("r", 43)
    {:ok, started} = Slack.begin_link(scope, nonce)
    {:ok, link} = Slack.complete_link(scope, started.state, nonce, "synthetic-code")
    link
  end

  def oauth(_code, _config),
    do:
      {:ok,
       %{
         "ok" => true,
         "team" => %{"id" => "T1"},
         "authed_user" => %{
           "id" => "U1",
           "token_type" => "user",
           "access_token" => "xoxp-synthetic-U1",
           "scope" => Enum.join(OAuth.user_scopes(), ",")
         }
       }}

  def read(method, _token, params) do
    body =
      case method do
        "auth.test" ->
          %{"team_id" => "T1", "user_id" => "U1"}

        "users.info" ->
          %{"user" => %{"id" => "U1", "deleted" => false, "is_bot" => false}}

        "conversations.info" ->
          %{
            "channel" => %{
              "id" => params.channel,
              "is_member" => !Application.get_env(:pauseai_ca, :slack_test_revoked)
            }
          }

        "conversations.history" ->
          %{
            "messages" => [
              %{
                "ts" => "1800000000.000001",
                "user" => "U1",
                "text" => "Synthetic retained needle"
              }
            ],
            "has_more" => true
          }

        "conversations.replies" ->
          %{
            "messages" => [
              %{
                "ts" => "1800000000.000001",
                "user" => "U1",
                "text" => "Synthetic retained needle"
              },
              %{
                "ts" => "1800000001.000001",
                "user" => "U1",
                "text" => "Synthetic thread reply",
                "thread_ts" => "1800000000.000001"
              }
            ],
            "has_more" => false
          }

        "chat.getPermalink" ->
          %{
            "permalink" =>
              "https://synthetic.slack.com/archives/" <>
                params.channel <> "/p" <> String.replace(params.message_ts, ".", "")
          }
      end

    {:ok, 200, Map.put(body, "ok", true)}
  end

  def post(_token, params) do
    Application.put_env(
      :pauseai_ca,
      :slack_test_post_count,
      Application.get_env(:pauseai_ca, :slack_test_post_count) + 1
    )

    case Application.get_env(:pauseai_ca, :slack_test_post_mode) do
      :uncertain ->
        {:error, :timeout}

      :rejected ->
        {:ok, 200, %{"ok" => false, "error" => "restricted_action"}}

      :sent ->
        {:ok, 200, %{"ok" => true, "channel" => params.channel, "ts" => "1800000002.000001"}}
    end
  end
end
