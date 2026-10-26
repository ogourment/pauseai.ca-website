defmodule PauseAiCaWeb.WelcomeCallsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Welcome

  def mount(_, _, socket) do
    locale = if socket.assigns.live_action == :fr, do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Application.get_env(:pauseai_ca, :welcome_calls_enabled, false) do
      {:ok,
       assign(socket,
         locale: locale,
         page_title: gettext("My welcome calls"),
         calls: [],
         keys: %{},
         error: nil
       )}
    else
      {:ok, redirect(socket, to: ~p"/dashboard")}
    end
  end

  def handle_params(_, _, socket), do: {:noreply, load(socket)}

  def handle_event(
        "respond",
        %{"id" => id, "reply" => reply, "revision" => revision, "key" => key},
        socket
      ) do
    revision =
      case Integer.parse(revision || "") do
        {n, ""} -> n
        _ -> -1
      end

    case Welcome.respond(socket.assigns.current_scope, id, reply, revision, key) do
      {:ok, _} ->
        {:noreply, load(socket)}

      {:error, _} ->
        {:noreply,
         assign(socket,
           error: gettext("This invitation changed or is unavailable. Reload before replying.")
         )}
    end
  end

  defp load(socket) do
    case Welcome.mine(socket.assigns.current_scope) do
      {:ok, calls} ->
        assign(socket,
          calls: calls,
          keys: Map.new(calls, &{&1.id, Ecto.UUID.generate()}),
          error: nil
        )

      _ ->
        socket |> assign(calls: []) |> redirect(to: ~p"/dashboard")
    end
  end

  defp name(user), do: if(user.name in [nil, ""], do: gettext("Host"), else: user.name)

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      translated_path={if @locale == "fr", do: ~p"/en/welcome-calls", else: ~p"/fr/appels-accueil"}
    >
      <section id="my-welcome-calls" class="mx-auto max-w-3xl px-5 py-10 space-y-6">
        <h1 class="text-3xl font-bold">{gettext("My welcome calls")}</h1>
        <p>
          {gettext(
            "Choose whether to attend. Your reply does not subscribe you to a newsletter or grant group membership."
          )}
        </p>
        <p :if={@error} role="alert">{@error}</p>
        <p :if={@calls == []}>{gettext("No welcome invitations yet.")}</p>
        <article
          :for={p <- @calls}
          id={"my-welcome-" <> p.id}
          data-revision={p.revision}
          class="rounded-xl border border-base-300 p-5 space-y-3"
        >
          <h2 class="text-2xl font-semibold">{p.session.title}</h2>
          <p>{p.group.name}</p>
          <p>{gettext("Starts")}: {Welcome.display_time(p.session.starts_at, p.session.timezone)}</p>
          <p>{gettext("Ends")}: {Welcome.display_time(p.session.ends_at, p.session.timezone)}</p>
          <p>
            {gettext("Session language")}: {if(p.session.language == "fr",
              do: gettext("French"),
              else: gettext("English")
            )} · {gettext("Host")}: {name(p.session.host)}
          </p>
          <p id={"welcome-rsvp-" <> p.id}>
            {gettext("Your reply")}: {case p.rsvp do
              "accepted" -> gettext("Accepted")
              "declined" -> gettext("Declined")
              "withdrawn" -> gettext("Withdrawn")
              _ -> gettext("Pending")
            end}
          </p>
          <%= if p.invitation_state == "invited" and p.session.status == "scheduled" and Map.get(p, :active, true) do %>
            <div class="flex flex-wrap gap-3">
              <button
                :for={
                  {reply, label} <- [
                    {"accepted", gettext("Accept")},
                    {"declined", gettext("Decline")},
                    {"withdrawn", gettext("Withdraw from this group’s welcome calls")}
                  ]
                }
                phx-click="respond"
                phx-value-id={p.id}
                phx-value-reply={reply}
                phx-value-revision={p.revision}
                phx-value-key={@keys[p.id]}
                class={if reply == "withdrawn", do: "min-w-0 max-w-full text-left text-sm underline whitespace-normal", else: "btn btn-outline"}
              >{label}</button>
            </div>
            <a
              :if={p.rsvp == "accepted"}
              href={p.session.meeting_url}
              class="inline-block font-semibold underline"
            >{gettext("Join the call")}</a>
          <% else %>
            <p>{gettext("This invitation is no longer active.")}</p>
            <div
              :if={
                p.invitation_state == "invited" and p.session.status == "scheduled" and
                  not Map.get(p, :active, true)
              }
              class="flex flex-wrap gap-3"
            >
              <button
                :for={
                  {reply, label} <- [
                    {"declined", gettext("Decline")},
                    {"withdrawn", gettext("Withdraw from this group’s welcome calls")}
                  ]
                }
                phx-click="respond"
                phx-value-id={p.id}
                phx-value-reply={reply}
                phx-value-revision={p.revision}
                phx-value-key={@keys[p.id]}
                class={if reply == "withdrawn", do: "min-w-0 max-w-full text-left text-sm underline whitespace-normal", else: "btn btn-outline"}
              >{label}</button>
            </div>
          <% end %>
        </article>
      </section>
    </Layouts.app>
    """
  end
end
