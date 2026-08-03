defmodule PauseAiCa.AccountsSuperadminTest do
  use PauseAiCa.DataCase, async: false

  import PauseAiCa.AccountsFixtures

  alias PauseAiCa.Accounts

  test "the first confirmed user who sets a password becomes superadmin" do
    user = user_fixture()

    assert {:ok, {updated, _tokens}} =
             Accounts.update_user_password(user, %{password: valid_user_password()})

    assert updated.superadmin
  end

  test "an unconfirmed user is never bootstrapped as superadmin" do
    user = unconfirmed_user_fixture()

    assert {:ok, {updated, _tokens}} =
             Accounts.update_user_password(user, %{password: valid_user_password()})

    refute updated.superadmin
  end

  test "the last superadmin cannot remove their own role" do
    admin = user_fixture()

    assert {:ok, {admin, _tokens}} =
             Accounts.update_user_password(admin, %{password: valid_user_password()})

    assert {:error, :last_superadmin} = Accounts.set_superadmin(admin, admin, false)
  end
end
