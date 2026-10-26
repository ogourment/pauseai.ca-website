defmodule PauseAiCaWeb.ManifundDonateLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias PauseAiCa.{Donations, Repo}
  alias PauseAiCa.Donations.Campaign

  @url "https://manifund.org/projects/pauseai-canada-national-expansion--core-operations"

  setup do
    previous = Application.get_env(:pauseai_ca, :manifund_donations_enabled)
    campaign = Application.get_env(:pauseai_ca, :manifund_campaign)
    Application.put_env(:pauseai_ca, :manifund_donations_enabled, true)

    on_exit(fn ->
      Application.put_env(:pauseai_ca, :manifund_donations_enabled, previous)
      Application.put_env(:pauseai_ca, :manifund_campaign, campaign)
    end)

    :ok
  end

  test "both public editions offer the configured campaign and retain Interac without pledge intake",
       %{conn: conn} do
    for {path, action, disclosure} <- [
          {"/en/donate", "Donate on Manifund", "A Manifund account is required"},
          {"/fr/faire-un-don", "Faire un don sur Manifund", "Un compte Manifund est nécessaire"}
        ] do
      {:ok, view, _} = live(conn, path)

      assert has_element?(
               view,
               "#manifund-donate[href='#{@url}'][target='_blank'][rel='noopener noreferrer'][data-donation='manifund']",
               action
             )

      assert has_element?(view, "#manifund-proposal[href='#{@url}']")
      assert has_element?(view, "#manifund-account-requirement", disclosure)
      assert has_element?(view, "#donation-email", "pauseaicanada@proton.me")
      assert has_element?(view, "#donate-interac strong", "PauseAI Canada")
      refute has_element?(view, "#pledge-form")
      refute has_element?(view, "#pledge-suggestions")
      refute has_element?(view, "iframe")
      assert Repo.aggregate(Donations.Pledge, :count) == 0
      assert Repo.aggregate(PauseAiCa.Accounts.User, :count) == 0
      assert Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count) == 0
      refute_receive {:email, _}
    end
  end

  test "invalid campaign configuration keeps the local summary and verified Interac route", %{
    conn: conn
  } do
    for url <- [
          "https://manifund.org.evil.example/projects/fake",
          "javascript:alert(1)",
          "https://manifund.org/projects/fake?redirect=elsewhere",
          42
        ] do
      Application.put_env(:pauseai_ca, :manifund_campaign,
        project_id: Ecto.UUID.generate(),
        url: url
      )

      assert Campaign.current() == {:error, :not_configured}
      {:ok, view, _} = live(conn, "/en/donate")
      assert has_element?(view, "#manifund-campaign", "What your support makes possible")
      assert has_element?(view, "#manifund-unavailable", "Interac below")
      assert has_element?(view, "#donation-email", "pauseaicanada@proton.me")
      refute has_element?(view, "#manifund-donate")
      refute has_element?(view, "#pledge-form")
    end
  end

  test "retired public save events cannot create a new pledge while historical records remain readable",
       %{conn: conn} do
    {:ok, :recorded} =
      Donations.pledge(%{
        "name" => "Historical example",
        "email" => "historical@example.org",
        "locale" => "en",
        "contact_consent" => true
      })

    original = Repo.get_by!(Donations.Pledge, email: "historical@example.org")

    {:ok, view, _} = live(conn, "/en/donate")

    render_hook(view, "save", %{
      "pledge" => %{
        "name" => "New example",
        "email" => "new@example.org",
        "contact_consent" => "true"
      }
    })

    assert Repo.aggregate(Donations.Pledge, :count) == 1
    assert Repo.get!(Donations.Pledge, original.id).name == "Historical example"
    refute_receive {:email, _}
  end
end
