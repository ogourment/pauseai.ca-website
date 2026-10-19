defmodule PauseAiCaWeb.MailNavigation do
  use PauseAiCaWeb, :html
  attr :locale, :string, required: true
  attr :active, :string, required: true

  def tabs(assigns) do
    ~H"""
    <nav
      aria-label={gettext("Emails")}
      class="mb-6 flex flex-wrap gap-5 border-b border-stone-300 pb-3"
    >
      <.link
        :for={
          {key, label, path} <- [
            {"drafts", gettext("Drafts"), "/manage/mail"},
            {"results", gettext("Sent & results"), "/manage/mail/results"},
            {"lists", gettext("Lists"), "/manage/mail/newsletters"}
          ]
        }
        navigate={path <> "?locale=" <> @locale}
        aria-current={if @active == key, do: "page"}
        class={if @active == key, do: "font-bold underline", else: "underline"}
      >{label}</.link>
    </nav>
    """
  end
end
