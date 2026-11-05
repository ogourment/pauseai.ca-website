defmodule PauseAiCaWeb.MailNavigation do
  use PauseAiCaWeb, :html
  attr :locale, :string, required: true
  attr :active, :string, required: true
  attr :current_scope, :map, default: nil

  def tabs(assigns) do
    assigns =
      assign(assigns, :mail_capabilities, PauseAiCa.Mail.capabilities(assigns.current_scope))

    ~H"""
    <nav
      aria-label={gettext("Emails")}
      class="mail-tabs"
    >
      <.link
        :for={
          {key, label, path} <- [
            {"drafts", gettext("Drafts"), "/manage/mail"},
            {"conversations", gettext("Inbox"), "/manage/mail/inbox"},
            {"results", gettext("Sent & results"), "/manage/mail/results"},
            {"lists", gettext("Lists"), "/manage/mail/newsletters"}
          ]
        }
        :if={
          (key != "conversations" or @mail_capabilities.outreach?) and
            (key not in ["results", "lists"] or PauseAiCa.Volunteers.superadmin?(@current_scope))
        }
        data-navigation-item={"mail." <> key}
        navigate={path <> "?locale=" <> @locale}
        aria-current={if @active == key, do: "page"}
        class={if @active == key, do: "font-bold underline", else: "underline"}
      >{label}</.link>
      <.link
        :if={PauseAiCa.Volunteers.superadmin?(@current_scope)}
        data-navigation-item="mail.access"
        href={"/manage/mail/access?locale=" <> @locale}
        aria-current={if @active == "access", do: "page"}
        class={if @active == "access", do: "font-bold underline", else: "underline"}
      >{gettext("Mailbox access")}</.link>
      <details :if={PauseAiCa.Volunteers.superadmin?(@current_scope)} id="mail-more">
        <summary>{gettext("More")}</summary>
        <.link navigate={~p"/manage/mail/preferences?locale=#{@locale}"}>{gettext("Email preferences")}</.link>
      </details>
    </nav>
    """
  end
end
