defmodule PauseAiCa.Participation.Notifier do
  import Swoosh.Email
  use Gettext, backend: PauseAiCaWeb.Gettext
  alias PauseAiCaWeb.Emails.Layout

  def build(request, url, withdrawal_url, recipient) do
    choices =
      [
        {request.newsletter, {"PauseAI Canada newsletter", "Infolettre de PauseAI Canada"}},
        {request.account,
         {"Your account to save and record actions",
          "Votre compte pour conserver et noter vos actions"}},
        {request.local_kind == "waitlist",
         {"Local waitlist: #{request.city || request.fsa}",
          "Liste d’attente locale : #{request.city || request.fsa}"}},
        {request.local_kind == "help",
         {"Offer of help: #{request.city || request.fsa}",
          "Proposition d’aide : #{request.city || request.fsa}"}}
      ]
      |> Enum.filter(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

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
end
