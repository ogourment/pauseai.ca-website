defmodule PauseAiCaWeb.AuthLayout do
  @moduledoc """
  Shared chrome for the sign-in pages.

  These routes are not locale-prefixed — a magic link has to work whichever
  language the person was reading in — so rather than guessing, they show both
  languages the way the account emails do: English, then French beneath it in a
  lighter weight. It is the pattern federal sites use, and it means the page a
  link lands on reads the same as the email it came from.
  """

  use Phoenix.Component

  attr :title_en, :string, required: true
  attr :title_fr, :string, required: true
  slot :subtitle
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <div class="mx-auto max-w-md px-5 py-12 sm:py-16">
      <div class="overflow-hidden rounded-2xl border border-stone-200 bg-white">
        <p class="bg-brand px-5 py-3 text-center font-heading text-xs font-bold uppercase tracking-[0.16em] text-stone-950">
          PauseAI Canada
        </p>

        <div class="p-7 sm:p-8">
          <h1 class="font-heading text-3xl leading-tight text-stone-950">{@title_en}</h1>
          <p class="mt-1 font-heading text-xl leading-tight text-stone-500">{@title_fr}</p>

          <div :if={@subtitle != []} class="mt-4 leading-7 text-stone-600">
            {render_slot(@subtitle)}
          </div>

          <div class="mt-6">{render_slot(@inner_block)}</div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  A short line of English with its French counterpart beneath.
  """
  attr :en, :string, required: true
  attr :fr, :string, required: true

  def bilingual(assigns) do
    ~H"""
    <p class="leading-7 text-stone-600">{@en}</p>
    <p class="mt-1 leading-7 text-stone-500">{@fr}</p>
    """
  end
end
