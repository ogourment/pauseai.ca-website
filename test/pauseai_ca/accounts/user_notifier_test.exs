defmodule PauseAiCa.Accounts.UserNotifierTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias PauseAiCa.Accounts.User
  alias PauseAiCa.Accounts.UserNotifier

  @user %User{email: "camille@example.org", confirmed_at: ~U[2026-08-01 12:00:00Z]}
  @unconfirmed %User{email: "camille@example.org", confirmed_at: nil}

  test "sign-in mail comes from the authenticated domain, not a placeholder" do
    UserNotifier.deliver_login_instructions(@user, "https://pauseai.ca/users/log-in/token")

    assert_email_sent(fn email ->
      # assert_email_sent/1 uses the return value as the match, so the last
      # expression must be truthy.
      refute to_string(elem(email.from, 1)) =~ "example.com"
      assert email.from == {"PauseAI Canada", "campaigns@example.org"}
    end)
  end

  test "every message carries both languages" do
    UserNotifier.deliver_login_instructions(@user, "https://pauseai.ca/users/log-in/token")

    assert_email_sent(fn email ->
      assert email.subject =~ "Your sign-in link"
      assert email.subject =~ "Votre lien de connexion"
      assert email.html_body =~ "Se connecter"
      assert email.html_body =~ "Sign in"
      assert email.text_body =~ "Votre lien de connexion"
    end)
  end

  test "the link is reachable without rendering HTML" do
    url = "https://pauseai.ca/users/log-in/abc123"
    UserNotifier.deliver_login_instructions(@user, url)

    assert_email_sent(fn email ->
      assert email.text_body =~ url
      assert email.html_body =~ url
    end)
  end

  test "an unconfirmed user is asked to confirm rather than simply signed in" do
    UserNotifier.deliver_login_instructions(@unconfirmed, "https://pauseai.ca/confirm")

    assert_email_sent(fn email ->
      assert email.subject =~ "Confirm your account"
      assert email.html_body =~ "never sell or share"
    end)
  end

  test "email-change instructions name the address being confirmed" do
    UserNotifier.deliver_update_email_instructions(@user, "https://pauseai.ca/settings/confirm")

    assert_email_sent(fn email ->
      assert email.html_body =~ "camille@example.org"
      assert email.subject =~ "Confirmez votre nouvelle adresse"
    end)
  end

  test "a new superadmin receives a bilingual role notification" do
    UserNotifier.deliver_superadmin_granted(@user, "https://pauseai.ca/admin/metrics")

    assert_email_sent(fn email ->
      assert email.to == [{"", "camille@example.org"}]
      assert email.subject =~ "superadmin"
      assert email.subject =~ "superadmin de PauseAI Canada"
      assert email.html_body =~ "Open movement metrics"
      assert email.html_body =~ "Ouvrir les indicateurs du mouvement"
      assert email.text_body =~ "https://pauseai.ca/admin/metrics"
    end)
  end

  test "user-supplied text cannot inject markup into the HTML body" do
    hostile = %User{email: "a<script>alert(1)</script>@example.org", confirmed_at: nil}
    UserNotifier.deliver_update_email_instructions(hostile, "https://pauseai.ca/x")

    assert_email_sent(fn email ->
      refute email.html_body =~ "<script>"
      assert email.html_body =~ "&lt;script&gt;"
    end)
  end
end
