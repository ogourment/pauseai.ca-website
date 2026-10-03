defmodule PauseAiCaWeb.AdministratorsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.{AccountManagement, Volunteers, MailSafety}

  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Volunteers.superadmin?(socket.assigns.current_scope) do
      {:ok,
       socket
       |> assign(
         locale: locale,
         page_title: gettext("Administrators"),
         staging?: MailSafety.environment() == :staging,
         email: "",
         error: nil,
         saved: false
       )
       |> reload()}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Superadmin access required."))
       |> redirect(to: ~p"/dashboard")}
    end
  end

  def handle_event("allow-sign-in", %{"access" => %{"email" => email}}, socket),
    do: set_access(socket, email, true)

  def handle_event("remove-sign-in", %{"email" => email}, socket),
    do: set_access(socket, email, false)

  defp set_access(socket, email, allowed) do
    case AccountManagement.set_staging_login(socket.assigns.current_scope, email, allowed) do
      {:ok, _} ->
        {:noreply, socket |> assign(email: "", error: nil, saved: true) |> reload()}

      {:error, :confirmed_account_required} ->
        {:noreply,
         assign(socket,
           email: email,
           saved: false,
           error: gettext("Choose an existing account with a confirmed email.")
         )}

      _ ->
        {:noreply,
         assign(socket, email: email, saved: false, error: gettext("Superadmin access required."))}
    end
  end

  defp reload(socket),
    do: assign(socket, :roster, AccountManagement.access_roster(socket.assigns.current_scope))

  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="administrators"
    >
      <section id="administrators" class="mx-auto max-w-5xl space-y-6 px-5 py-10">
        <h1 class="text-3xl font-bold">{gettext("Administrators")}</h1>
        <p>{gettext("Open an account to change its role or managed groups.")}</p>
        <section id="superadmin-list" class="space-y-3 rounded-xl border bg-white p-5">
          <h2 class="text-xl font-bold">{gettext("Superadmins")}</h2>
          <p :if={@roster.superadmins == []}>{gettext("No accounts found.")}</p>
          <p :for={user <- @roster.superadmins}>
            <.link navigate={~p"/manage/accounts/#{user.id}?locale=#{@locale}"} class="underline">{user.email}</.link>
            <span :if={is_nil(user.confirmed_at)}>{gettext("Email unconfirmed")}</span>
          </p>
        </section>
        <section id="group-manager-list" class="space-y-3 rounded-xl border bg-white p-5">
          <h2 class="text-xl font-bold">{gettext("Group managers")}</h2>
          <p :if={@roster.managers == []}>{gettext("No group managers assigned.")}</p>
          <p :for={manager <- @roster.managers}>
            <.link
              navigate={~p"/manage/accounts/#{manager.user_id}?locale=#{@locale}"}
              class="underline"
            >{manager.user.email}</.link>
            · {manager.group.name}
          </p>
          <.link navigate={~p"/manage/accounts/import?locale=#{@locale}"} class="underline">{gettext(
            "Groups and managers"
          )}</.link>
        </section>
        <section :if={@staging?} id="staging-sign-in" class="space-y-3 rounded-xl border bg-white p-5">
          <h2 class="text-xl font-bold">{gettext("Staging sign-in whitelist")}</h2>
          <p>
            {gettext(
              "Superadmins and group managers can already sign in. Add other reviewers here for magic-link emails only. This grants no admin role and does not allow campaign mail."
            )}
          </p>
          <.form
            for={to_form(%{"email" => @email}, as: "access")}
            id="staging-sign-in-form"
            phx-submit="allow-sign-in"
            class="max-w-xl space-y-3"
          >
            <.input
              name="access[email]"
              id="staging-sign-in-email"
              value={@email}
              type="email"
              required
              label={gettext("Account email")}
              errors={if @error, do: [@error], else: []}
            />
            <.button
              phx-disable-with={gettext("Saving…")}
              class="rounded-lg bg-[#254c3b] px-4 py-2 font-semibold text-white hover:bg-[#1d3c2f] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
            >{gettext("Allow sign-in")}</.button>
            <p :if={@saved} id="staging-access-saved" role="status">
              {gettext("Saved. No email sent.")}
            </p>
          </.form>
          <p :if={@roster.staging_signins == []}>{gettext("No additional reviewers allowed.")}</p>
          <ul class="space-y-3">
            <li :for={user <- @roster.staging_signins} class="flex flex-wrap items-center gap-4">
              <.link navigate={~p"/manage/accounts/#{user.id}?locale=#{@locale}"} class="underline">{user.email}</.link>
              <button
                phx-click="remove-sign-in"
                phx-value-email={user.email}
                class="rounded-lg border px-3 py-2"
                aria-label={gettext("Remove staging sign-in for %{email}", email: user.email)}
              >{gettext("Remove")}</button>
            </li>
          </ul>
        </section>
      </section>
    </Layouts.management>
    """
  end
end
