defmodule PauseAiCaWeb.TorontoChapterActions do
  @moduledoc "Toronto-owned visitor tools for the English chapter pages."
  use Phoenix.Component

  @data_file Path.expand("../../../priv/chapter_data/toronto.json", __DIR__)
  @external_resource @data_file
  @data @data_file |> File.read!() |> Jason.decode!()

  def riding_tool(assigns) do
    assigns = assign(assigns, ridings: @data["ridings"], letter: @data["template"])

    ~H"""
    <toronto-ridings
      id="toronto-ridings"
      phx-update="ignore"
      class="my-8 block"
      data-template={@letter}
    >
      <label class="block font-semibold" for="toronto-riding-filter">Search by riding or MP</label>
      <input type="search" class="input my-2 w-full" id="toronto-riding-filter" autocomplete="off" />
      <p class="my-2 text-sm" role="status" data-count></p>
      <div class="grid gap-5 md:grid-cols-2">
        <ul class="max-h-80 space-y-1 overflow-y-auto" aria-label="Toronto ridings">
          <li :for={r <- @ridings}>
            <a
              class="block rounded border px-3 py-2 hover:underline focus-visible:underline"
              href={r["url"]}
              data-slug={r["slug"]}
              data-riding={r["riding"]}
              data-mp={r["mp"]}
              data-formerly={r["formerly"]}
            ><strong>{r["riding"]}</strong> · {r["mp"] || "Seat vacant"}</a>
          </li>
        </ul>
        <section aria-label="Your MP" data-result tabindex="-1">
          <h2 data-name class="text-xl font-bold">Your MP</h2>
          <p data-instruction>Choose a riding to prepare a letter.</p>
          <div id="letter" data-compose hidden>
            <label for="toronto-letter" class="block font-semibold">Your letter</label>
            <textarea id="toronto-letter" rows="10" class="textarea my-2 w-full"></textarea>
            <button data-copy type="button" class="btn">Copy letter</button>
            <span data-feedback role="status"></span>
          </div>
          <a data-contact hidden class="mt-2 inline-block underline">Open Parliament contact page</a>
        </section>
      </div>
    </toronto-ridings>
    """
  end

  def giving_options(assigns) do
    giving = @data["giving"]
    monthly = Enum.sort_by(giving["monthly"], fn {amount, _} -> String.to_integer(amount) end)
    assigns = assign(assigns, giving: giving, monthly: monthly)

    ~H"""
    <nav
      id="toronto-giving-options"
      aria-label="Toronto donation amounts"
      class="my-6 grid gap-4 sm:grid-cols-2"
    >
      <section id="monthly">
        <h2 class="font-semibold">Monthly gifts</h2>
        <div class="mt-2 flex flex-wrap gap-2">
          <a
            :for={{amount, href} <- @monthly}
            class="btn"
            href={href}
            aria-label={"Donate C$#{amount} a month"}
          >C${amount}</a>
        </div>
      </section>
      <section id="one-off">
        <span id="once" class="chapter-fragment-alias" aria-hidden="true"></span>
        <h2 class="font-semibold">One-off gifts</h2>
        <div class="mt-2 flex flex-wrap gap-2">
          <a
            :for={amount <- @giving["onceAmounts"]}
            class="btn"
            href={@giving["once"] <> "?prefilled_amount=" <> Integer.to_string(amount * 100)}
            aria-label={"Donate C$#{amount} once"}
          >C${amount}</a>
          <a class="btn" href={@giving["once"]}>Other amount</a>
        </div>
      </section>
    </nav>
    """
  end
end
