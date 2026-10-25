defmodule PauseAiCaWeb.SlackCommunityLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{SlackFixtures, Accounts.Scope}

  setup %{conn: conn} do
    saved = SlackFixtures.configure!()
    on_exit(fn -> SlackFixtures.restore!(saved) end)
    user = user_fixture()
    %{conn: log_in_user(conn, user), scope: Scope.for_user(user)}
  end

  test "missing installation renders a clear setup state and no connect action", c do
    Application.put_env(:pauseai_ca, :slack, %{})
    {:ok, view, _} = live(c.conn, "/community/slack?locale=en")
    assert has_element?(view, "#slack-setup", "awaiting site configuration")
    refute has_element?(view, "#slack-connect")
  end

  test "retained browse/search and original-link lookup require fresh channel authority", c do
    SlackFixtures.connect!(c.scope)
    {:ok, view, _} = live(c.conn, "/community/slack?locale=en")
    assert has_element?(view, "select[name=channel] option", "general")
    refute has_element?(view, "select[name=channel] option", "private-review")
    view |> element("button", "Capture recent Slack history") |> render_click()
    assert has_element?(view, "#slack-messages", "Synthetic retained needle")
    assert render(view) =~ "Coverage is incomplete"
    view |> form("#slack-search", chat_search: %{query: "needle"}) |> render_submit()
    assert has_element?(view, "#slack-messages", "Synthetic retained needle")
    refute has_element?(view, "#slack-messages", "Synthetic thread reply")
    render_click(view, "source", %{"ts" => "1800000000.000001", "channel" => "C1"})

    assert has_element?(
             view,
             "a[href='https://synthetic.slack.com/archives/C1/p1800000000000001']"
           )

    Application.put_env(:pauseai_ca, :slack_test_revoked, true)
    send(view.pid, :refresh_access)
    refute has_element?(view, "#slack-messages")
    refute render(view) =~ "Synthetic retained needle"
    refute has_element?(view, "a[href^='https://synthetic.slack.com/']")
  end

  test "post confirmation uses saved text and retains uncertain attempts without retry", c do
    SlackFixtures.connect!(c.scope)
    {:ok, view, _} = live(c.conn, "/community/slack?locale=en")

    view
    |> form("#slack-draft", chat_draft: %{text: "Saved synthetic message"})
    |> render_submit()

    assert has_element?(view, "#slack-post-review", "Saved synthetic message")
    view |> form("#slack-draft", chat_draft: %{text: "Unreviewed edit"}) |> render_change()
    assert has_element?(view, "#slack-post-review button[disabled]", "Post to Slack")
    render_click(view, "post")
    assert Application.get_env(:pauseai_ca, :slack_test_post_count) == 0
    view |> form("#slack-draft", chat_draft: %{text: "Reviewed edit"}) |> render_submit()
    Application.put_env(:pauseai_ca, :slack_test_post_mode, :uncertain)
    view |> element("button", "Post to Slack") |> render_click()
    assert has_element?(view, "#slack-post-status", "Delivery uncertain")
    assert has_element?(view, "#slack-post-review", "Reviewed edit")
    refute has_element?(view, "#slack-post-review button", "Post to Slack")
    render_click(view, "post")
    assert Application.get_env(:pauseai_ca, :slack_test_post_count) == 1
  end

  test "thread reply target is frozen in the saved draft", c do
    SlackFixtures.connect!(c.scope)
    {:ok, view, _} = live(c.conn, "/community/slack?locale=en")
    view |> element("button", "Capture recent Slack history") |> render_click()
    render_click(view, "sync_thread", %{"ts" => "1800000000.000001", "channel" => "C1"})
    render_click(view, "reply", %{"ts" => "1800000001.000001", "channel" => "C1"})
    assert has_element?(view, "#slack-draft", "Synthetic thread reply")
    view |> form("#slack-draft", chat_draft: %{text: "Reviewed thread reply"}) |> render_submit()
    assert has_element?(view, "#slack-post-review", "1800000000.000001")
    view |> element("button", "Post to Slack") |> render_click()
    assert has_element?(view, "#slack-post-status", "Posted to Slack")
  end
end
