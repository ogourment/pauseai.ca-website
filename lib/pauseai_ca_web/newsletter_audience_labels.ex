defmodule PauseAiCaWeb.NewsletterAudienceLabels do
  use Gettext, backend: PauseAiCaWeb.Gettext
  def rule_label("city"), do: gettext("City")
  def rule_label("region"), do: gettext("Region")
  def rule_label("fsa"), do: gettext("FSA")
  def status_label(:included), do: gettext("Eligible")
  def status_label(:unconfirmed), do: gettext("Awaiting confirmation")
  def status_label(:withdrawn), do: gettext("Withdrawn")
  def status_label(:legacy_uncertain), do: gettext("Legacy evidence to review")
  def status_label(:provider_blocked), do: gettext("Provider blocked")
  def status_label(:suppressed), do: gettext("Suppressed")
end
