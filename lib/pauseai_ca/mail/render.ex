defmodule PauseAiCa.Mail.Render do
  @moduledoc "Draft rendering only. No delivery API. Same sanitized rendering powers every preview."
  defdelegate merge(template, variables), to: PhoenixMailWorkflow.Template
  defdelegate complete_links?(source), to: PhoenixMailWorkflow.Template

  def html(source) do
    MDEx.to_html!(source,
      render: [escape: true],
      sanitize: [
        rm_tags: ["img", "area", "map"],
        url_schemes: ["https", "http", "mailto"],
        url_relative: :deny
      ]
    )
  end
end
