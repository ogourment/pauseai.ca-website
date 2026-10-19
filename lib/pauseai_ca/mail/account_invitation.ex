defmodule PauseAiCa.Mail.AccountInvitation do
  @moduledoc "Authored invitations through the existing shared mail draft and review workflow."
  alias PhoenixMailWorkflow.Template

  def languages(editions), do: PhoenixMailWorkflow.Invitations.languages(editions)

  # Called with context validated by the shared invitation planner.
  def content(edition, context) when edition in ["en", "fr", "unknown"] do
    variables =
      Map.merge(context, %{
        "registration_en" =>
          PauseAiCaWeb.Site.url(
            "en",
            "/users/register?locale=en&utm_source=crm&utm_medium=email&utm_campaign=account-invitation&utm_content=create-account-en"
          ),
        "registration_fr" =>
          PauseAiCaWeb.Site.url(
            "fr",
            "/users/register?locale=fr&utm_source=crm&utm_medium=email&utm_campaign=account-invitation&utm_content=create-account-fr"
          )
      })

    source =
      case edition do
        "en" -> english()
        "fr" -> french()
        "unknown" -> english() <> "\n\n---\n\n" <> french()
      end

    with {:ok, source} <- Template.merge(source, variables) do
      {:ok, %{"subject" => subject(edition), "source" => source}}
    end
  end

  defp subject("en"), do: "Your invitation to PauseAI Canada"
  defp subject("fr"), do: "Votre invitation à PauseAI Canada"
  defp subject("unknown"), do: "Your invitation · Votre invitation à PauseAI Canada"

  defp english do
    """
    {{inviter}} invites you to create a PauseAI Canada account.

    {{reason_en}}

    [Create your account]({{registration_en}})

    You choose whether to subscribe to the newsletter or take part in a local group. If you already have an account, you can sign in instead.
    """
  end

  defp french do
    """
    {{inviter}} vous invite à créer un compte PauseAI Canada.

    {{reason_fr}}

    [Créer votre compte]({{registration_fr}})

    Vous choisissez de vous abonner à l’infolettre ou de participer à un groupe local. Si vous avez déjà un compte, vous pouvez vous connecter.
    """
  end
end
