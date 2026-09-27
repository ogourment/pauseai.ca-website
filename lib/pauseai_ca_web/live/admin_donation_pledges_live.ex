defmodule PauseAiCaWeb.AdminDonationPledgesLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Donations
  alias PauseAiCaWeb.VolunteerForms

  @impl true
  def mount(params, _, socket) do
    locale = if params["locale"] == "fr", do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    {:ok,
     assign(socket,
       locale: locale,
       page_title: gettext("Donation pledges"),
       pledges: [],
       page: 1,
       more: false
     )}
  end

  @impl true
  def handle_params(params, _, socket) do
    page =
      case Integer.parse(params["page"] || "1") do
        {n, ""} when n > 0 and n <= 100_000 -> n
        _ -> 1
      end

    case Donations.list(socket.assigns.current_scope, page) do
      {:ok, rows} ->
        {:noreply,
         assign(socket, pledges: Enum.take(rows, 25), page: page, more: length(rows) > 25)}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("You do not have access to this page."))
         |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      translated_path={
        ~p"/admin/donation-pledges?#{%{locale: if(@locale == "fr", do: "en", else: "fr"), page: @page}}"
      }
    >
      <section id="donation-pledges" class="mx-auto max-w-6xl px-5 py-12">
        <.link navigate={~p"/admin/dashboard"} class="underline">{gettext("Admin dashboard")}</.link>
        <h1 class="mt-5 font-heading text-4xl">{gettext("Donation pledges")}</h1>
        <p class="mt-4">
          {gettext(
            "Contact permission applies to the pledge. No payment has been collected and no email is sent from this page."
          )}
        </p>
        <p :if={@pledges == []} class="mt-8">{gettext("No pledges on this page.")}</p>
        <article
          :for={pledge <- @pledges}
          id={"pledge-#{pledge.id}"}
          class="mt-6 space-y-3 rounded-xl border p-5"
        >
          <h2 class="text-xl font-bold">{pledge.name}</h2>
          <p>{pledge.email}</p>
          <p>
            {gettext("Pledged amount")}: {if pledge.amount_cad,
              do: "#{Decimal.to_string(pledge.amount_cad, :normal)} CAD",
              else: gettext("Not specified")}
          </p>
          <p>
            {gettext("Contribution frequency")}: {if pledge.frequency == "monthly",
              do: gettext("Monthly"),
              else: gettext("One-time")}
          </p>
          <p>{gettext("Language")}: {pledge.locale}</p>
          <p class="whitespace-pre-wrap">{pledge.notes}</p>
          <p>
            {gettext("Contact permission recorded")}:
            <VolunteerForms.timestamp
              id={"pledge-time-#{pledge.id}"}
              value={pledge.consented_at}
              locale={@locale}
            />
          </p>
        </article>
        <nav class="mt-6 flex gap-5" aria-label={gettext("Pagination")}>
          <.link
            :if={@page > 1}
            patch={~p"/admin/donation-pledges?#{%{page: @page - 1, locale: @locale}}"}
          >{gettext("Previous")}</.link>
          <span>{gettext("Page %{page}", page: @page)}</span>
          <.link
            :if={@more}
            patch={~p"/admin/donation-pledges?#{%{page: @page + 1, locale: @locale}}"}
          >{gettext("Next")}</.link>
        </nav>
      </section>
    </Layouts.app>
    """
  end
end
