defmodule PauseAiCaWeb.MailNavigation do
  use PauseAiCaWeb, :html
  attr :locale, :string, required: true
  attr :active, :string, required: true
  attr :current_scope, :map, default: nil
  attr :workspace, :string, default: ""

  def tabs(assigns) do
    workspace = if assigns.workspace == "newsletters", do: "newsletters", else: "emails"

    assigns =
      assigns
      |> assign(:workspace, workspace)
      |> assign(:mail_capabilities, PauseAiCa.Mail.capabilities(assigns.current_scope))
      |> assign(:tabs, tabs_for(workspace))

    ~H"""
    <nav
      aria-label={if @workspace == "newsletters", do: gettext("Newsletters"), else: gettext("Emails")}
      class="mail-tabs"
    >
      <.link
        :for={{key, label, path} <- @tabs}
        :if={
          (key != "conversations" or @mail_capabilities.outreach?) and
            (key not in ["results", "subscribers"] or PauseAiCa.Volunteers.superadmin?(@current_scope))
        }
        data-navigation-item={"mail." <> key}
        navigate={path <> "?" <> URI.encode_query(%{locale: @locale, workspace: @workspace})}
        aria-current={if @active == key or (@active == "lists" and key == "subscribers"), do: "page"}
        class={
          if @active == key or (@active == "lists" and key == "subscribers"),
            do: "font-bold underline",
            else: "underline"
        }
      >{label}</.link>
      <details :if={PauseAiCa.Volunteers.superadmin?(@current_scope)} id="mail-more">
        <summary>{gettext("More")}</summary>
        <.link
          :if={@workspace == "emails"}
          data-navigation-item="mail.access"
          href={"/manage/mail/access?locale=" <> @locale}
          aria-current={if @active == "access", do: "page"}
        >{gettext("Mailbox access")}</.link>
        <.link navigate={~p"/manage/mail/preferences?locale=#{@locale}"}>{gettext("Email preferences")}</.link>
      </details>
    </nav>
    """
  end

  defp tabs_for("newsletters"),
    do: [
      {"drafts", gettext("Drafts"), "/manage/mail"},
      {"subscribers", gettext("Subscribers"), "/manage/mail/newsletters"},
      {"results", gettext("Sent & results"), "/manage/mail/results"}
    ]

  defp tabs_for(_),
    do: [
      {"drafts", gettext("Drafts"), "/manage/mail"},
      {"conversations", gettext("Inbox"), "/manage/mail/inbox"},
      {"results", gettext("Sent & results"), "/manage/mail/results"}
    ]
end
