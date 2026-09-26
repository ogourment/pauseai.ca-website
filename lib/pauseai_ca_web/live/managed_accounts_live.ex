defmodule PauseAiCaWeb.ManagedAccountsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.{AccountManagement, Volunteers}
  alias PauseAiCaWeb.VolunteerForms

  @impl true
  def mount(params, _, socket) do
    locale = if params["locale"] == "fr", do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Volunteers.allowed?(socket.assigns.current_scope) do
      {:ok,
       assign(socket,
         locale: locale,
         page_title: gettext("Accounts"),
         records: [],
         search: "",
         page: 1,
         record: nil,
         form: to_form(%{}, as: "account"),
         errors: %{},
         batches: Volunteers.list_batches(socket.assigns.current_scope)
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Organizer access required."))
       |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_params(params, _, socket) do
    if id = params["id"] do
      case AccountManagement.get(socket.assigns.current_scope, id) do
        {:ok, record} ->
          values = %{
            "name" => record.user.name,
            "postal_code" => record.user.postal_code,
            "city" => record.user.city,
            "notes" => record.signup && record.signup.notes
          }

          {:noreply,
           assign(socket, record: record, form: to_form(values, as: "account"), errors: %{})}

        _ ->
          {:noreply,
           socket
           |> put_flash(:error, gettext("Account unavailable."))
           |> push_navigate(to: ~p"/manage/accounts?locale=#{socket.assigns.locale}")}
      end
    else
      search = params["q"] || ""

      page =
        case Integer.parse(params["page"] || "1") do
          {n, ""} when n > 0 -> n
          _ -> 1
        end

      {:noreply,
       assign(socket,
         record: nil,
         search: search,
         page: page,
         records: AccountManagement.list(socket.assigns.current_scope, search, page)
       )}
    end
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket),
    do:
      {:noreply,
       push_patch(socket, to: ~p"/manage/accounts?#{%{locale: socket.assigns.locale, q: search}}")}

  def handle_event("save", %{"account" => attrs}, socket) do
    case AccountManagement.update(
           socket.assigns.current_scope,
           socket.assigns.record.user.id,
           attrs
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Account saved."))
         |> push_navigate(
           to:
             ~p"/manage/accounts/#{socket.assigns.record.user.id}?locale=#{socket.assigns.locale}"
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(
           form: to_form(attrs, as: "account"),
           errors: if(is_map(reason), do: reason, else: %{})
         )
         |> put_flash(:error, gettext("Changes not saved. Check the fields and your access."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      promote_warning_shot={false}
      translated_path={~p"/manage/accounts?locale=#{if(@locale == "fr", do: "en", else: "fr")}"}
    >
      <section id="managed-accounts" class="mx-auto max-w-6xl space-y-6 px-5 py-12">
        <h1 class="text-4xl font-bold">{gettext("Accounts")}</h1>
        <%= if @record do %>
          <.link navigate={~p"/manage/accounts?locale=#{@locale}"} class="underline">{gettext(
            "Back to accounts"
          )}</.link>
          <h2 class="text-2xl font-bold">{@record.user.email}</h2>
          <p>
            {if @record.user.confirmed_at,
              do: gettext("Email confirmed"),
              else: gettext("Account created · email unconfirmed")}
          </p>
          <p :if={@record.group}>{gettext("Incubator / group")}: {@record.group.name}</p>
          <.form
            for={@form}
            id="managed-account-form"
            phx-submit="save"
            class="max-w-2xl space-y-4 rounded-xl border bg-white p-6"
          >
            <.input
              field={@form[:name]}
              label={gettext("Name")}
              errors={field_errors(@errors, "name")}
            />
            <.input
              field={@form[:postal_code]}
              label={gettext("Postal code")}
              errors={field_errors(@errors, "postal_code")}
            />
            <.input
              field={@form[:city]}
              label={gettext("City")}
              errors={field_errors(@errors, "city")}
            />
            <.input
              :if={@record.signup}
              field={@form[:notes]}
              type="textarea"
              label={gettext("Private organizer notes")}
              errors={field_errors(@errors, "notes")}
            />
            <.button>{gettext("Save account")}</.button>
          </.form>
          <div :if={@record.signup} class="space-y-3">
            <h2 class="text-xl font-bold">{gettext("Invitations")}</h2>
            <p :for={invitation <- @record.signup.invitations}>
              {VolunteerForms.status(invitation.status)}
              <VolunteerForms.timestamp
                id={"account-invitation-#{invitation.id}"}
                value={invitation.inserted_at}
                locale={@locale}
              />
            </p>
            <.link
              :if={Enum.any?(@batches, &(&1.id == @record.signup.batch_id))}
              navigate={
                ~p"/manage/accounts/import?#{%{batch: @record.signup.batch_id, locale: @locale}}"
              }
              class="underline"
            >{gettext("View batch and invitation actions")}</.link>
          </div>
        <% else %>
          <nav class="flex flex-wrap gap-3" aria-label={gettext("Account actions")}>
            <.link
              navigate={~p"/manage/accounts/new?locale=#{@locale}"}
              class="rounded-lg border px-4 py-2"
            >{gettext("Add account")}</.link>
            <.link
              navigate={~p"/manage/accounts/import?locale=#{@locale}"}
              class="rounded-lg border px-4 py-2"
            >{gettext("Add multiple accounts")}</.link>
          </nav>
          <.form for={to_form(%{}, as: "search")} phx-change="search" id="account-search">
            <.input
              name="search"
              id="account-search-input"
              value={@search}
              label={gettext("Search accounts")}
              phx-debounce="200"
            />
          </.form>
          <div class="overflow-x-auto">
            <table class="w-full text-left">
              <thead>
                <tr>
                  <th>{gettext("Name")}</th><th>{gettext("Email")}</th><th>
                    {gettext("Incubator / group")}
                  </th><th>{gettext("Status")}</th>
                </tr>
              </thead><tbody>
                <tr :for={record <- Enum.take(@records, 25)} class="border-t">
                  <td class="p-3">{record.user.name}</td><td class="p-3">
                    <.link
                      navigate={~p"/manage/accounts/#{record.user.id}?locale=#{@locale}"}
                      class="underline"
                    >{record.user.email}</.link>
                  </td><td class="p-3">{record.group && record.group.name}</td><td class="p-3">
                    {if record.user.confirmed_at,
                      do: gettext("Email confirmed"),
                      else: gettext("Account created · email unconfirmed")}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p :if={@records == []}>{gettext("No accounts found.")}</p>
          <nav class="flex gap-4" aria-label={gettext("Account pages")}>
            <.link
              :if={@page > 1}
              patch={~p"/manage/accounts?#{%{locale: @locale, q: @search, page: @page - 1}}"}
            >{gettext("Previous")}</.link>
            <span>{@page}</span>
            <.link
              :if={length(@records) > 25}
              patch={~p"/manage/accounts?#{%{locale: @locale, q: @search, page: @page + 1}}"}
            >{gettext("Next")}</.link>
          </nav>
          <section class="space-y-3">
            <h2 class="text-xl font-bold">{gettext("Saved batches and invitations")}</h2>
            <p :if={@batches == []}>{gettext("No saved batches yet.")}</p>
            <div :for={batch <- @batches}>
              <.link
                navigate={~p"/manage/accounts/import?#{%{batch: batch.id, locale: @locale}}"}
                class="underline"
              >{if batch.source == "", do: gettext("Untitled batch"), else: batch.source} · {if batch.state ==
                                                                                                  "draft",
                                                                                                do:
                                                                                                  gettext(
                                                                                                    "Draft"
                                                                                                  ),
                                                                                                else:
                                                                                                  gettext(
                                                                                                    "Confirmed"
                                                                                                  )}</.link>
            </div>
          </section>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp field_errors(errors, field),
    do: if(errors[field], do: [VolunteerForms.error(errors[field])], else: [])
end
