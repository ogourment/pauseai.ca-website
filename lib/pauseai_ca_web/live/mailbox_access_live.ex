defmodule PauseAiCaWeb.MailboxAccessLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Outreach

  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    socket =
      assign(socket,
        locale: locale,
        page_title: gettext("Mailbox access"),
        access: nil,
        error: nil,
        selected_manager_id: "",
        connected: connected?(socket)
      )

    {:ok, load(socket)}
  end

  def handle_event("select-manager", %{"access" => %{"user_id" => user_id}}, socket) do
    {:noreply, assign(socket, selected_manager_id: user_id, error: nil)}
  end

  def handle_event(
        "grant",
        %{"mailbox_ref" => ref, "user_id" => user_id, "revision" => revision},
        socket
      ) do
    mutate(socket, :grant, ref, user_id, revision)
  end

  def handle_event(
        "revoke",
        %{"mailbox_ref" => ref, "user_id" => user_id, "revision" => revision},
        socket
      ) do
    mutate(socket, :revoke, ref, user_id, revision)
  end

  defp mutate(socket, action, ref, user_id, revision) do
    with {expected, ""} <- Integer.parse(to_string(revision || "")),
         true <- expected >= 0,
         {:ok, _} <-
           apply(Outreach, if(action == :grant, do: :grant_mailbox, else: :revoke_mailbox), [
             socket.assigns.current_scope,
             ref,
             user_id,
             expected
           ]) do
      {:noreply, socket |> assign(error: nil) |> load()}
    else
      {:error, :unauthorized} ->
        {:noreply, denied(socket)}

      {:error, :stale} ->
        {:noreply,
         socket
         |> load()
         |> assign(
           error: gettext("Access changed. Review the current grants before trying again.")
         )}

      {:error, :not_eligible} ->
        {:noreply,
         socket
         |> load()
         |> assign(error: gettext("Choose a confirmed account that currently manages a group."))}

      _ ->
        {:noreply,
         socket
         |> load()
         |> assign(
           error:
             gettext(
               "Mailbox access could not be changed. Review the current grants and try again."
             )
         )}
    end
  end

  defp load(socket) do
    case Outreach.mailbox_access(socket.assigns.current_scope) do
      {:ok, access} -> assign(socket, access: access)
      _ -> denied(socket)
    end
  end

  defp denied(socket),
    do:
      socket
      |> assign(access: nil)
      |> put_flash(:error, gettext("Superadmin access required."))
      |> redirect(to: ~p"/dashboard")

  defp selected_revision(access, ref, user_id) do
    case Enum.find(access.grants, &(&1.mailbox_ref == ref and &1.user_id == user_id)) do
      nil -> 0
      grant -> grant.revision
    end
  end

  defp grant_for(access, ref, user_id),
    do: Enum.find(access.grants, &(&1.mailbox_ref == ref and &1.user_id == user_id))

  defp rows(access, selected) do
    granted = for grant <- access.grants, is_nil(grant.revoked_at), do: grant.user
    candidate = Enum.filter(access.eligible_managers, &(&1.id == selected))
    Enum.uniq_by(granted ++ candidate, & &1.id) |> Enum.sort_by(& &1.email)
  end

  defp label(user),
    do: if(user.name in [nil, ""], do: user.email, else: "#{user.name} · #{user.email}")

  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="mail"
    >
      <section
        :if={@access}
        id="mailbox-access"
        data-breadcrumb-label={gettext("Mailbox access")}
        class="crm-surface mx-auto max-w-6xl px-5 py-8"
      >
        <PauseAiCaWeb.MailNavigation.tabs
          current_scope={@current_scope}
          locale={@locale}
          active="access"
        />
        <h1 class="mt-5 text-3xl font-bold">{gettext("Mailbox access")}</h1>
        <p class="mt-3">
          {gettext(
            "Grant an existing confirmed group manager access to read and send from a mailbox. Removing their manager role also removes access."
          )}
        </p>
        <p class="mt-2 text-sm">
          {gettext(
            "Superadmins retain access to every configured mailbox. Grants do not create accounts or manager roles."
          )}
        </p>
        <p :if={@error} id="mailbox-access-error" role="alert" class="crm-error mt-4">{@error}</p>
        <.form
          for={to_form(%{"user_id" => @selected_manager_id}, as: "access")}
          id="mailbox-manager-picker"
          phx-change="select-manager"
          class="my-5 max-w-xl"
        >
          <.input
            type="select"
            disabled={!@connected}
            id="mailbox-manager-select"
            name="access[user_id]"
            value={@selected_manager_id}
            label={gettext("Manager account")}
            aria-label={gettext("Manager account")}
            prompt={gettext("Choose a manager")}
            options={Enum.map(@access.eligible_managers, &{label(&1), &1.id})}
          />
        </.form>
        <p :if={rows(@access, @selected_manager_id) == []} class="mt-4">
          {gettext("No delegated managers.")}
        </p>
        <div :if={rows(@access, @selected_manager_id) != []} class="overflow-x-auto mt-5">
          <table class="w-full text-sm">
            <thead>
              <tr>
                <th class="text-left p-3">{gettext("Manager account")}</th><th
                  :for={box <- @access.mailboxes}
                  class="p-3 break-all"
                >
                  {box.email}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={user <- rows(@access, @selected_manager_id)}
                id={"mailbox-manager-#{user.id}"}
                class="border-t"
              >
                <th scope="row" class="text-left p-3 min-w-48 font-normal break-words">
                  {label(user)}
                  <p :if={Map.get(user, :eligible?, true) == false} class="text-sm">
                    {gettext("Currently ineligible; access is blocked.")}
                  </p>
                </th>
                <td
                  :for={box <- @access.mailboxes}
                  class="p-3 text-center"
                  id={"mailbox-cell-#{box.id}-#{user.id}"}
                >
                  <%= if grant_for(@access, box.id, user.id) && is_nil(grant_for(@access, box.id, user.id).revoked_at) do %>
                    <button
                      type="button"
                      disabled={!@connected}
                      phx-click="revoke"
                      phx-value-mailbox_ref={box.id}
                      phx-value-user_id={user.id}
                      phx-value-revision={selected_revision(@access, box.id, user.id)}
                      class="underline min-h-11"
                      phx-disable-with={gettext("Updating…")}
                    >{gettext("Revoke")}</button>
                  <% else %>
                    <button
                      :if={Map.get(user, :eligible?, true)}
                      type="button"
                      disabled={!@connected}
                      phx-click="grant"
                      phx-value-mailbox_ref={box.id}
                      phx-value-user_id={user.id}
                      phx-value-revision={selected_revision(@access, box.id, user.id)}
                      class="crm-button min-h-11"
                      phx-disable-with={gettext("Updating…")}
                    >{gettext("Grant access")}</button>
                    <span :if={!Map.get(user, :eligible?, true)}>{gettext("Unavailable")}</span>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.management>
    """
  end
end
