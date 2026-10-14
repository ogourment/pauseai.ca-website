defmodule PauseAiCaWeb.NewsletterControllerTest do
  use PauseAiCaWeb.ConnCase, async: true
  alias PauseAiCa.Newsletters

  test "opening confirmation and withdrawal links has no effect; explicit POST changes consent only",
       %{conn: conn} do
    accounts = PauseAiCa.Repo.aggregate(PauseAiCa.Accounts.User, :count)

    {:ok, request} =
      Newsletters.request_signup("confirm@example.org", %{consent: true, locale: "fr"})

    confirm = "/newsletters/confirm?token=" <> request.confirmation_token
    withdrawal = "/newsletters/withdraw?token=" <> request.withdrawal_token
    page = get(conn, confirm)
    assert html_response(page, 200) =~ "Confirmer"
    assert get_resp_header(page, "cache-control") == ["no-store"]
    refute Newsletters.eligible?(request.subscription.email)

    assert html_response(
             post(conn, "/newsletters/confirm", %{"token" => request.confirmation_token}),
             200
           ) =~ "newsletter-result"

    assert Newsletters.eligible?(request.subscription.email)
    assert html_response(get(conn, withdrawal), 200) =~ "newsletter-confirm-action"
    assert Newsletters.eligible?(request.subscription.email)

    assert html_response(
             post(conn, "/newsletters/withdraw", %{"token" => request.withdrawal_token}),
             200
           ) =~ "newsletter-result"

    refute Newsletters.eligible?(request.subscription.email)

    assert html_response(
             post(conn, "/newsletters/confirm", %{"token" => request.confirmation_token}),
             200
           ) =~ "newsletter-invalid"

    assert PauseAiCa.Repo.aggregate(PauseAiCa.Accounts.User, :count) == accounts
  end

  test "an edition language stays on withdrawal GET and POST without changing stored preference",
       %{conn: conn} do
    {:ok, request} =
      Newsletters.request_signup("edition-language@example.org", %{consent: true, locale: "en"})

    {:ok, _} = Newsletters.confirm(request.confirmation_token)

    page =
      get(conn, "/newsletters/withdraw", %{"token" => request.withdrawal_token, "locale" => "fr"})

    assert html_response(page, 200) =~ "Se désabonner"
    assert html_response(page, 200) =~ "name=\"locale\""
    assert Newsletters.eligible?("edition-language@example.org")

    result =
      post(conn, "/newsletters/withdraw", %{"token" => request.withdrawal_token, "locale" => "fr"})

    assert html_response(result, 200) =~ "lang=\"fr\""
    refute Newsletters.eligible?("edition-language@example.org")
    assert PauseAiCa.Repo.get!(Newsletters.Subscription, request.subscription.id).locale == "en"
  end
end
