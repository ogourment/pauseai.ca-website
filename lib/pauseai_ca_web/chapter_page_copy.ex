defmodule PauseAiCaWeb.ChapterPageCopy do
  @moduledoc false
  use Gettext, backend: PauseAiCaWeb.Gettext

  alias PauseAiCa.Incubators

  def text(:address_taken), do: gettext("A page already uses this address.")
  def text(:add_page), do: gettext("Add page")

  def text(:stale),
    do: gettext("Another edit was saved. Copy your text before reloading this page.")

  def text(:back_editor), do: gettext("Back to editor")
  def text(:chapter_pages), do: gettext("Chapter pages")
  def text(:body), do: gettext("Content")

  def text(:draft_help),
    do: gettext("English edition. Saving a draft keeps the published page as it is.")

  def text(:bad_title), do: gettext("Enter a title of 150 characters or fewer.")
  def text(:bad_order), do: gettext("Enter a whole number from 0 to 9,999.")
  def text(:manage_pages), do: gettext("Manage chapter pages")
  def text(:order), do: gettext("Navigation order")
  def text(:slug), do: gettext("Page address")
  def text(:preview_link), do: gettext("Preview private draft")
  def text(:preview_label), do: gettext("Private draft preview")
  def text(:publish_empty), do: gettext("Save some content before publishing.")
  def text(:save_failed), do: gettext("The page could not be saved. Your text is still here.")

  def text(:bad_body),
    do: gettext("Use %{limit} characters or fewer.", limit: Incubators.chapter_content_limit())

  def text(:bad_address),
    do: gettext("Use lowercase letters, digits and hyphens, up to 80 characters.")

  def text(:home_limit),
    do:
      gettext("Up to %{limit} characters per edition.", limit: Incubators.chapter_content_limit())
end
