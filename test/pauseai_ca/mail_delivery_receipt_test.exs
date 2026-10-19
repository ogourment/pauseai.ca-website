defmodule PauseAiCa.MailDeliveryReceiptTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  import Swoosh.Email, except: [from: 2]
  alias PauseAiCa.{Accounts, CRM, Mailer}
  alias PauseAiCa.Mail.DeliveryReceipt

  test "generic shared-address sends retain admin attribution without storing message bodies" do
    admin = user_fixture() |> change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)
    {:ok, contact} = CRM.create(scope, %{email: "receipt@example.org"})

    message =
      new()
      |> Swoosh.Email.from({"PauseAI Canada", "info@pauseai.ca"})
      |> to("receipt@example.org")
      |> subject("Synthetic individual invitation")
      |> text_body("Private body")

    assert {:ok, _} = Mailer.deliver(message, admin_actor_id: admin.id)
    receipt = Repo.get_by!(DeliveryReceipt, subject: "Synthetic individual invitation")
    assert receipt.actor_id == admin.id
    assert receipt.state == "accepted"
    refute Map.has_key?(receipt, :text_body)

    assert {:ok, [%{admin_email: email, sender_email: "info@pauseai.ca"}]} =
             PauseAiCa.Newsletters.Results.contact_history(scope, contact.person.id)

    assert email == admin.email
    Repo.update!(change(admin, superadmin: false))

    assert {:error, :unauthorized} =
             PauseAiCa.Newsletters.Results.contact_history(scope, contact.person.id)
  end
end
