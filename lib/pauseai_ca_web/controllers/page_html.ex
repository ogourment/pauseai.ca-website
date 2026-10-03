defmodule PauseAiCaWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use PauseAiCaWeb, :html

  attr :id, :string, required: true
  attr :number, :string, required: true
  attr :question, :string, required: true
  attr :locale, :string, required: true

  def belief_question(assigns) do
    ~H"""
    <fieldset
      class="belief-question rounded-3xl border border-stone-200 bg-white p-6 shadow-sm"
      data-question={@id}
    >
      <legend class="sr-only">{@question}</legend>
      <div class="flex gap-4">
        <span class="font-mono text-sm font-bold text-brand">{@number}</span>
        <p class="text-lg font-semibold leading-7 text-stone-900">{@question}</p>
      </div>
      <div class="mt-5 grid grid-cols-6 gap-2" role="group" aria-label={@question}>
        <button
          :for={{value, label} <- answer_options(@locale)}
          type="button"
          data-answer={value}
          class="belief-option"
        >
          {label}
        </button>
      </div>
    </fieldset>
    """
  end

  attr :id, :string, required: true
  attr :stage, :string, required: true
  attr :title, :string, required: true
  attr :body, :string, required: true
  attr :href, :string, required: true
  attr :source, :string, required: true
  attr :cta, :string, required: true
  attr :bookmark, :string, required: true
  attr :locale, :string, required: true
  attr :current_scope, :map, default: nil

  def resource_card(assigns) do
    ~H"""
    <article
      id={@id}
      class="resource-card group relative rounded-3xl border border-stone-200 bg-[#f8f5ed] p-7 transition duration-300 hover:-translate-y-1 hover:shadow-lg"
    >
      <span class="recommendation-badge hidden rounded-full bg-brand px-3 py-1 text-xs font-bold uppercase tracking-wider text-stone-950">{gettext(
        "Suggested first"
      )}</span>
      <p class="mt-3 text-xs font-bold uppercase tracking-[0.18em] text-brand-ink">{@stage}</p>
      <h3 class="mt-3 font-serif text-3xl leading-tight text-stone-950">{@title}</h3>
      <p class="mt-4 leading-7 text-stone-600">{@body}</p>
      <a
        href={@href}
        target="_blank"
        rel="noreferrer"
        class="mt-6 inline-flex font-semibold text-stone-900 underline decoration-brand decoration-2 underline-offset-4"
      >
        {@cta} <span aria-hidden="true">&nbsp;↗</span>
      </a>
      <p class="mt-5 text-xs text-stone-400">Source: {@source}</p>
      <.resource_bookmark
        title={@title}
        compact={false}
        selected={!!@current_scope && @bookmark in @current_scope.user.saved_resources}
        href={
          if @current_scope,
            do: ~p"/bookmarks/#{@bookmark}?locale=#{@locale}",
            else: ~p"/users/register?bookmark=#{@bookmark}"
        }
        method={if @current_scope, do: "post", else: "get"}
      />
    </article>
    """
  end

  defp answer_options(_locale),
    do: [
      {"0", gettext("Unsure")},
      {"1", gettext("Strongly disagree")},
      {"2", gettext("Disagree")},
      {"3", gettext("Mixed")},
      {"4", gettext("Agree")},
      {"5", gettext("Strongly agree")}
    ]

  embed_templates "page_html/*"
end
