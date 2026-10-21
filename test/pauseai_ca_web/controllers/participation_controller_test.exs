defmodule PauseAiCaWeb.ParticipationControllerTest do
  use PauseAiCaWeb.ConnCase
  alias PauseAiCa.{Participation, Accounts, Repo}

  defp signup do
    {:ok, _} =
      Participation.request(
        %{
          "email" => "next-step@example.org",
          "name" => "Morgan",
          "location" => "Ottawa",
          "newsletter" => true
        },
        %{},
        fn _, token -> "https://example.org/confirm?token=#{token}" end
      )

    assert_receive {:email, mail}
    [_, token] = Regex.run(~r/confirm\?token=([^\s]+)/, mail.text_body)
    token
  end

  test "confirmation lists included and excluded choices; account offer creates and signs in only on POST",
       %{conn: conn} do
    token = signup()
    ready = get(conn, "/participation/confirm", token: token)
    html = html_response(ready, 200)
    assert html =~ "participation-choice-summary"
    assert html =~ "Included"
    assert html =~ "Not selected"
    refute Accounts.get_user_by_email("next-step@example.org")

    confirmed = post(recycle(ready), "/participation/confirm", token: token)
    html = html_response(confirmed, 200)
    assert html =~ "Create my account"
    refute Accounts.get_user_by_email("next-step@example.org")
    assert get_resp_header(confirmed, "cache-control") == ["no-store"]

    [offer] =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("input[name=account_offer]")
      |> LazyHTML.attribute("value")

    invalid_phone =
      post(recycle(confirmed), "/participation/account",
        account_offer: offer,
        phone: "not a number",
        locale: "en"
      )

    assert html_response(invalid_phone, 200) =~ "Phone (optional)"
    refute Accounts.get_user_by_email("next-step@example.org")

    created =
      post(recycle(confirmed), "/participation/account",
        account_offer: offer,
        locale: "en",
        phone: "+1 613 555 0101"
      )

    assert redirected_to(created) == "/en/dashboard"
    assert get_session(created, :user_token)
    assert Accounts.get_user_by_email("next-step@example.org").city == "Ottawa"
    assert Accounts.get_user_by_email("next-step@example.org").phone == "+1 613 555 0101"
    refute_receive {:email, _}
  end

  test "no account can be created through an invented offer", %{conn: conn} do
    result = post(conn, "/participation/account", account_offer: "forged")
    assert html_response(result, 200) =~ "participation-invalid"
    assert Repo.aggregate(Accounts.User, :count) == 0
    refute get_session(result, :user_token)
  end
end
