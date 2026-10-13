defmodule PauseAiCaWeb.LocalInterestLive do
  use PauseAiCaWeb, :live_view

  @impl true
  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    case PauseAiCa.Participation.local_requests(socket.assigns.current_scope, params["page"] || 1) do
      {:ok, result} ->
        {:ok,
         assign(socket,
           locale: locale,
           page_title: gettext("Local participation"),
           requests: result.entries,
           pagination: result
         )}

      _ ->
        {:ok, redirect(socket, to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_params(params, _, socket) do
    case PauseAiCa.Participation.local_requests(socket.assigns.current_scope, params["page"] || 1) do
      {:ok, result} -> {:noreply, assign(socket, requests: result.entries, pagination: result)}
      _ -> {:noreply, push_navigate(socket, to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event("claim", %{"id" => id}, socket) do
    case PauseAiCa.Participation.claim(socket.assigns.current_scope, id) do
      {:ok, _} -> handle_params(%{"page" => socket.assigns.pagination.page}, nil, socket)
      _ -> {:noreply, push_navigate(socket, to: ~p"/dashboard")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="contacts"
    >
      <h1 class="font-heading text-3xl">{gettext("Local participation")}</h1>
      <p class="mt-3 text-stone-600">
        {gettext(
          "Confirmed waitlist requests and offers of help. Follow-up is private; these requests do not create group membership."
        )}
      </p>
      <p :if={@requests == []} class="mt-6">{gettext("No confirmed local requests yet.")}</p>
      <ul id="local-request-queue" class="mt-6 divide-y divide-stone-200">
        <li :for={request <- @requests} class="py-5">
          <h2 class="font-heading text-2xl">{request.name || request.email}</h2>
          <p>{request.email} · {request.city} {request.fsa}</p>
          <p class="mt-2 font-semibold">
            {if request.local_kind == "help",
              do: gettext("I can help"),
              else: gettext("Join the waitlist")}
          </p>
          <p :if={request.followup_owner_id == @current_scope.user.id} class="mt-2 text-sm">
            {gettext("Your follow-up")}
          </p>
          <button
            :if={request.followup_owner_id != @current_scope.user.id}
            type="button"
            phx-click="claim"
            phx-value-id={request.id}
            class="mt-2 rounded border border-stone-300 px-3 py-1"
          >{gettext("Take ownership")}</button>
          <p :if={request.help_text} class="mt-2 whitespace-pre-wrap">{request.help_text}</p>
          <p class="mt-2 text-sm text-stone-600">
            {String.upcase(request.locale)} · {Calendar.strftime(request.confirmed_at, "%Y-%m-%d")}
          </p>
        </li>
      </ul>
      <nav class="mt-5 flex flex-wrap items-center gap-4" aria-label={gettext("Contact pages")}>
        <span>{gettext("Page %{page} of %{pages} · %{total} requests",
          page: @pagination.page,
          pages: @pagination.pages,
          total: @pagination.total
        )}</span>
        <.link
          :if={@pagination.page > 1}
          patch={~p"/admin/local-interest?#{%{locale: @locale, page: @pagination.page - 1}}"}
          class="underline"
        >{gettext("Previous")}</.link>
        <.link
          :if={@pagination.page < @pagination.pages}
          patch={~p"/admin/local-interest?#{%{locale: @locale, page: @pagination.page + 1}}"}
          class="underline"
        >{gettext("Next")}</.link>
      </nav>
    </Layouts.management>
    """
  end
end
