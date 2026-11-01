defmodule PauseAiCa.OutreachNotifier do
  @moduledoc "Brevo delivery adapter for locally persisted admin notification work."
  use Gettext, backend: PauseAiCaWeb.Gettext
  alias PauseAiCa.{Mailer, Newsletters.Edition}

  def deliver(%{user: user, conversation: conversation, message: message}) do
    [%{edition: edition}] = Edition.decorate([%{email: user.email}])
    locale = if edition in ["en", "fr"], do: edition
    route_locale = locale || "en"
    path = "/manage/mail/conversations/#{conversation.id}?locale=#{route_locale}"
    reply_url = PauseAiCaWeb.Site.url(route_locale, path)
    uri = URI.parse(reply_url)
    origin = URI.to_string(%URI{scheme: uri.scheme, host: uri.host, port: uri.port})

    descriptor = %{
      sender_email: message.envelope["from"] || "",
      subject: message.envelope["subject"] || conversation.subject || "",
      sent_at: message.occurred_at || message.inserted_at
    }

    with {:ok, {html, text}} <-
           PhoenixMailWorkflow.OutreachNotification.render(descriptor, reply_url,
             locale: locale,
             app_origin: origin,
             allow_local_http:
               Application.get_env(:pauseai_ca, :mail_environment) in [:dev, :test],
             brand_name:
               Gettext.with_locale(PauseAiCaWeb.Gettext, locale || "en", fn ->
                 gettext("PauseAI Canada")
               end),
             identity_text: "pauseai.ca",
             brand_color: "#ff9416",
             format_time: &Calendar.strftime(&1, "%Y-%m-%d %H:%M UTC")
           ) do
      subject =
        if locale do
          Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
            gettext("New outreach message: %{subject}", subject: descriptor.subject)
          end)
        else
          gettext("New outreach message · Nouveau message: %{subject}",
            subject: descriptor.subject
          )
        end

      Swoosh.Email.new()
      |> Swoosh.Email.to({user.name || "", user.email})
      |> Swoosh.Email.from(Application.fetch_env!(:pauseai_ca, :campaign_sender))
      |> Swoosh.Email.subject(subject)
      |> Swoosh.Email.html_body(html)
      |> Swoosh.Email.text_body(text)
      |> Mailer.deliver()
    end
  end
end
