defmodule PauseAiCaWeb.AdminAccountsLive do
  use PauseAiCaWeb, :live_view

  alias PauseAiCa.Accounts
  alias PauseAiCa.Accounts.UserNotifier

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Accounts"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    count = Accounts.count_users()
    page_count = max(Integer.ceil_div(count, @per_page), 1)
    page = params |> Map.get("page", "1") |> parse_page() |> min(page_count)

    {:noreply,
     socket
     |> assign(:accounts, Accounts.list_users(page: page, per_page: @per_page))
     |> assign(:account_count, count)
     |> assign(:page, page)
     |> assign(:page_count, page_count)}
  end

  @impl true
  def handle_event("set-superadmin", %{"id" => id}, socket) do
    target = Accounts.get_user!(id)
    promote? = not target.superadmin

    case Accounts.set_superadmin(socket.assigns.current_scope.user, target, promote?) do
      {:ok, user} ->
        message =
          if promote?,
            do: gettext("Superadmin role granted."),
            else: gettext("Superadmin role removed.")

        {:noreply,
         socket
         |> reload_accounts()
         |> put_flash(:info, message)
         |> notify_new_superadmin(user, promote?)}

      {:error, :last_superadmin} ->
        {:noreply, put_flash(socket, :error, gettext("The last superadmin cannot be removed."))}

      {:error, :email_unconfirmed} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Confirm this account's email before granting superadmin access.")
         )}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Superadmin access required."))}
    end
  end

  defp reload_accounts(socket) do
    assign(
      socket,
      :accounts,
      Accounts.list_users(page: socket.assigns.page, per_page: @per_page)
    )
  end

  defp notify_new_superadmin(socket, _user, false), do: socket

  defp notify_new_superadmin(socket, user, true) do
    url = PauseAiCaWeb.Endpoint.url() <> "/admin/accounts"

    case UserNotifier.deliver_superadmin_granted(user, url) do
      {:ok, _email} ->
        socket

      {:error, _reason} ->
        put_flash(
          socket,
          :error,
          gettext("Role granted, but the notification email could not be sent.")
        )
    end
  end

  defp parse_page(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="admin-accounts" class="mx-auto max-w-6xl px-5 py-16">
        <p class="eyebrow">{gettext("Superadmin")}</p>
        <h1 class="mt-3 font-heading text-5xl text-stone-950">{gettext("Accounts")}</h1>
        <p class="mt-4 max-w-3xl text-stone-600">
          {gettext("Review registered accounts and manage access to the superadmin tools.")}
        </p>
        <nav class="mt-8 flex flex-wrap gap-3" aria-label={gettext("Superadmin tools")}>
          <.link navigate={~p"/admin/dashboard"} class={admin_link_class(false)}>
            {gettext("Dashboard")}
          </.link>
          <.link
            navigate={~p"/admin/accounts"}
            aria-current="page"
            class={admin_link_class(true)}
          >{gettext("Accounts")}</.link>
          <.link navigate={~p"/admin/contact-imports"} class={admin_link_class(false)}>
            {gettext("Contact imports")}
          </.link>
          <a href="/admin/versions" class={admin_link_class(false)}>{gettext("Deployment versions")}</a>
          <a href="/admin/acceptance" class={admin_link_class(false)}>{gettext("Acceptance evidence")}</a>
        </nav>

        <section class="mt-10 overflow-hidden rounded-3xl border border-stone-200 bg-white">
          <div class="flex flex-wrap items-baseline justify-between gap-3 border-b border-stone-200 px-6 py-5">
            <h2 class="font-heading text-3xl text-stone-950">{gettext("Registered accounts")}</h2>
            <p id="account-count" class="text-sm text-stone-600">
              {ngettext("%{count} account", "%{count} accounts", @account_count,
                count: @account_count
              )}
            </p>
          </div>
          <ul id="admin-users" class="divide-y divide-stone-100">
            <li
              :for={user <- @accounts}
              id={"admin-user-#{user.id}"}
              class="flex flex-wrap items-center gap-4 px-6 py-4"
            >
              <span class="min-w-0 flex-1 break-all font-medium text-stone-900">{user.email}</span>
              <span :if={user.superadmin} class="text-sm font-semibold text-brand-ink">
                {gettext("Superadmin")}
              </span>
              <span :if={is_nil(user.confirmed_at)} class="text-sm text-stone-500">
                {gettext("Email unconfirmed")}
              </span>
              <button
                id={"admin-toggle-#{user.id}"}
                phx-click="set-superadmin"
                phx-value-id={user.id}
                data-confirm={grant_confirmation(user)}
                disabled={!user.superadmin and is_nil(user.confirmed_at)}
                class="rounded-full border border-stone-300 px-4 py-2 text-sm font-semibold text-stone-800 transition-colors hover:border-brand focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand disabled:cursor-not-allowed disabled:opacity-40"
              >
                {if(user.superadmin,
                  do: gettext("Remove role"),
                  else: gettext("Make superadmin")
                )}
              </button>
            </li>
          </ul>
        </section>

        <nav
          :if={@page_count > 1}
          class="mt-6 flex items-center justify-between gap-4"
          aria-label={gettext("Account pages")}
        >
          <.link
            :if={@page > 1}
            patch={~p"/admin/accounts?#{[page: @page - 1]}"}
            class="rounded-full border border-stone-300 bg-white px-4 py-2 text-sm font-semibold text-stone-800 hover:border-brand"
          >{gettext("Previous")}</.link>
          <span :if={@page == 1}></span>
          <p id="account-page" class="text-sm text-stone-600">
            {gettext("Page %{page} of %{page_count}", page: @page, page_count: @page_count)}
          </p>
          <.link
            :if={@page < @page_count}
            patch={~p"/admin/accounts?#{[page: @page + 1]}"}
            class="rounded-full border border-stone-300 bg-white px-4 py-2 text-sm font-semibold text-stone-800 hover:border-brand"
          >{gettext("Next")}</.link>
          <span :if={@page == @page_count}></span>
        </nav>
      </section>
    </Layouts.app>
    """
  end

  defp grant_confirmation(%{superadmin: true}), do: nil

  defp grant_confirmation(user) do
    gettext(
      "Make %{email} a superadmin? They will receive an email with a link to the admin tools.",
      email: user.email
    )
  end

  defp admin_link_class(current?) do
    [
      "rounded-full border px-4 py-2 text-sm font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand",
      if(current?,
        do: "border-stone-900 bg-stone-900 text-white",
        else: "border-stone-300 bg-white text-stone-800 hover:border-brand"
      )
    ]
  end
end
