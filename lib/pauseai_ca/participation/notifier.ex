defmodule PauseAiCa.Participation.Notifier do
  import Swoosh.Email
  use Gettext, backend: PauseAiCaWeb.Gettext
  alias PauseAiCaWeb.Emails.Layout

  def build(request, url, withdrawal_url, recipient) do
    {target_en, target_fr} = local_target(request)

    choices =
      [
        {request.newsletter, {"PauseAI Canada newsletter", "Infolettre de PauseAI Canada"}},
        {request.account,
         {"Your account to save and record actions",
          "Votre compte pour conserver et noter vos actions"}},
        {not is_nil(request.local_kind),
         if(request.local_kind == "help",
           do: {"Offer of help: #{target_en}", "Proposition d’aide : #{target_fr}"},
           else:
             {"Local waitlist#{if request.local_kind, do: ": #{target_en}"}",
              "Liste d’attente locale#{if request.local_kind, do: " : #{target_fr}"}"}
         )}
      ]
      |> Enum.map(fn
        {true, {en, fr}} -> {"Included: " <> en, "Inclus : " <> fr}
        {false, {en, fr}} -> {"Not selected: " <> en, "Non sélectionné : " <> fr}
      end)

    blocks =
      [
        {"Confirm the choices you made on PauseAI.ca:",
         "Confirmez les choix que vous avez faits sur PauseAI.ca :"}
      ] ++
        choices ++
        [
          {"If you did not make this request, ignore this email.",
           "Si vous n’avez pas fait cette demande, ignorez ce courriel."}
        ]

    links =
      if request.local_kind,
        do: [
          {Gettext.with_locale(PauseAiCaWeb.Gettext, request.locale, fn ->
             gettext("Withdraw my local request")
           end), withdrawal_url}
        ],
        else: []

    {html, text} =
      Layout.render(
        "Confirm your choices",
        "Confirmez vos choix",
        blocks,
        {"Confirm and continue", "Confirmer et continuer", url},
        locale: request.locale,
        footer:
          {"You received this because a signup was requested with this address.",
           "Vous recevez ce courriel parce qu’une inscription a été demandée avec cette adresse."},
        footer_links: links
      )

    new()
    |> to(recipient)
    |> from(
      Application.get_env(:pauseai_ca, :campaign_sender, {"PauseAI Canada", "info@pauseai.ca"})
    )
    |> subject(
      Gettext.with_locale(PauseAiCaWeb.Gettext, request.locale, fn ->
        gettext("Confirm your choices")
      end)
    )
    |> html_body(html)
    |> text_body(text)
  end

  defp local_target(request) do
    group_id = Map.get(request.context || %{}, "incubator_group_id")

    case PauseAiCa.Incubators.public_group(group_id) do
      {:ok, group} -> {group.name_en, group.name_fr}
      _ -> {request.city || request.fsa, request.city || request.fsa}
    end
  end
end
