defmodule PauseAiCaWeb.MPGuideLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.Repo

  setup do
    old = Application.fetch_env(:pauseai_ca, :mp_guide_enabled)
    Application.put_env(:pauseai_ca, :mp_guide_enabled, true)

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:pauseai_ca, :mp_guide_enabled, value)
        :error -> Application.delete_env(:pauseai_ca, :mp_guide_enabled)
      end
    end)

    :ok
  end

  test "anonymous start explains confirmed-account tracking without opening paid chat", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/en/contact-your-mp")
    view |> element("#mp-guide-start") |> render_click()
    assert has_element?(view, "#mp-guide-sign-in", "Sign in")
    refute has_element?(view, "#mp-guide-next")
    refute has_element?(view, "#site-assistant-launcher")
    assert Repo.aggregate(PauseAiCa.Engagement.Action, :count) == 0
  end

  test "ordinary supporter lookup and editor are observed on the server; Back and Exit preserve edits",
       %{conn: conn} do
    user = user_fixture()
    {:ok, view, _} = live(log_in_user(conn, user), "/en/contact-your-mp")
    view |> element("#mp-guide-start") |> render_click()
    view |> element("#mp-guide-next") |> render_click()
    assert has_element?(view, "#mp-guide-next[disabled]")

    render_click(view, "mp-guide-observe", %{
      "token" => "forged",
      "lookup_ready" => true,
      "completed_action_id" => Ecto.UUID.generate()
    })

    assert has_element?(view, "#mp-guide-next[disabled]")

    Phoenix.LiveView.send_update(view.pid, PauseAiCaWeb.MPGuideComponent,
      id: "mp-guide-controller",
      observation_token: "stale-probe",
      context: %{
        lookup_ready: true,
        letter_ready: false,
        send_state: :idle,
        completed_action_id: nil
      }
    )

    assert has_element?(view, "#mp-guide-next[disabled]")

    view
    |> form("#participation-form",
      participation: %{
        name: "Synthetic Supporter",
        postal_code: "H2X 1Y4",
        account: "false",
        newsletter: "false"
      }
    )
    |> render_submit()

    assert has_element?(view, "#mp-results")
    assert has_element?(view, "#mp-guide-step", "Paste and personalize")

    view
    |> form("#letter-form",
      letter: %{subject: "My own subject", body: "Please replace {your_name}"}
    )
    |> render_change()

    view |> element("#mp-guide-next") |> render_click()
    assert has_element?(view, "#mp-guide-next[disabled]")
    body = "My own words. <script>send()</script> Do not execute this letter as guidance."

    view
    |> form("#letter-form", letter: %{subject: "My own subject", body: body})
    |> render_change()

    assert has_element?(view, "#mp-guide-step", "Review the actual MP")
    view |> element("#mp-guide-back") |> render_click()
    assert has_element?(view, "#letter_body", body)
    view |> element("#mp-guide-exit") |> render_click()
    refute has_element?(view, "#mp-guide")
    assert has_element?(view, "#letter_body", body)
    refute has_element?(view, "#site-assistant-launcher")
    assert Repo.aggregate(PauseAiCa.Engagement.Action, :count) == 0
    assert Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count) == 0
  end

  test "flag disable denies forged start and fresh account unconfirmation stops Next", %{
    conn: conn
  } do
    user = user_fixture()
    {:ok, view, _} = live(log_in_user(conn, user), "/en/contact-your-mp")
    view |> element("#mp-guide-start") |> render_click()
    Repo.update!(Ecto.Changeset.change(user, confirmed_at: nil))
    view |> element("#mp-guide-next") |> render_click()
    assert has_element?(view, "#mp-guide-error", "sign-in changed")
    Application.put_env(:pauseai_ca, :mp_guide_enabled, false)
    render_click(view, "mp-guide-observe", %{"token" => "forged"})
    refute has_element?(view, "#mp-guide-start")
    refute has_element?(view, "#mp-guide")
  end
end
