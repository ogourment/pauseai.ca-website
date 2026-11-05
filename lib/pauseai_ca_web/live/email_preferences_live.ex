defmodule PauseAiCaWeb.EmailPreferencesLive do
  use PauseAiCaWeb, :live_view
  import Ecto.Query
  alias PauseAiCa.{CRM, Newsletters, Repo, Volunteers}

  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Volunteers.superadmin?(socket.assigns.current_scope) do
      {:ok,
       assign(socket,
         locale: locale,
         page_title: gettext("Email preferences"),
         addresses: [],
         withdrawn: MapSet.new(),
         contact_id: nil,
         subscription_id: nil,
         form: to_form(%{}, as: "withdrawal"),
         saved: []
       )}
    else
      {:ok, redirect(socket, to: ~p"/dashboard")}
    end
  end

  def handle_params(params, _, socket) do
    case addresses(socket.assigns.current_scope, params["contact_id"], params["subscription_id"]) do
      {:ok, emails} ->
        {:noreply,
         assign(socket,
           addresses: emails,
           withdrawn: withdrawn(emails),
           contact_id: params["contact_id"],
           subscription_id: params["subscription_id"]
         )}

      _ ->
        {:noreply, redirect(socket, to: ~p"/dashboard")}
    end
  end

  def handle_event("record-withdrawal", %{"withdrawal" => attrs}, socket) do
    scope = socket.assigns.current_scope

    with {:ok, allowed} <-
           addresses(scope, socket.assigns.contact_id, socket.assigns.subscription_id),
         emails when is_list(emails) and emails != [] and length(emails) <= 25 <-
           selected(attrs, allowed),
         true <- allowed == [] or Enum.all?(emails, &(&1 in allowed)),
         {:ok, saved} <-
           Repo.transaction(fn ->
             Enum.map(Enum.sort(Enum.uniq(emails)), fn email ->
               case Newsletters.record_withdrawal(scope, email, attrs["reason"]) do
                 {:ok, subscription} -> subscription.email
                 {:error, reason} -> Repo.rollback(reason)
               end
             end)
           end) do
      {:noreply,
       assign(socket,
         saved: saved,
         withdrawn: withdrawn(socket.assigns.addresses),
         form: to_form(%{}, as: "withdrawal")
       )}
    else
      _ ->
        {:noreply,
         socket
         |> assign(form: to_form(attrs, as: "withdrawal"))
         |> put_flash(
           :error,
           gettext(
             "Could not record the request. Check the email address, request details and your access."
           )
         )}
    end
  end

  defp selected(attrs, []), do: [attrs["email"]]
  defp selected(attrs, _), do: attrs["emails"] || []

  defp addresses(scope, contact_id, subscription_id) do
    if Volunteers.superadmin?(scope) do
      cond do
        contact_id ->
          with {:ok, _} <- Ecto.UUID.cast(contact_id),
               {:ok, record} <- CRM.get(scope, contact_id) do
            {:ok, Enum.map(record.addresses, & &1.email)}
          end

        subscription_id ->
          with {:ok, id} <- Ecto.UUID.cast(subscription_id),
               subscription when not is_nil(subscription) <-
                 Repo.get(Newsletters.Subscription, id) do
            {:ok, [subscription.email]}
          else
            _ -> {:error, :not_found}
          end

        true ->
          {:ok, []}
      end
    else
      {:error, :unauthorized}
    end
  end

  defp withdrawn(emails) do
    Repo.all(
      from s in Newsletters.Subscription,
        where: s.email in ^emails and not is_nil(s.withdrawn_at),
        select: s.email
    )
    |> MapSet.new()
  end

  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="mail"
    >
      <section id="email-preferences" class="crm-surface mx-auto max-w-4xl px-5 py-8">
        <PauseAiCaWeb.MailNavigation.tabs
          current_scope={@current_scope}
          locale={@locale}
          active="preferences"
        />
        <h1 class="text-3xl font-bold">{gettext("Email preferences")}</h1>
        <.link
          :if={@contact_id}
          href={~p"/admin/contacts/#{@contact_id}?locale=#{@locale}"}
          class="underline"
        >{gettext("Back to contact")}</.link>
        <p class="my-4">
          {gettext(
            "Select the addresses covered by the unsubscribe request. Newsletter and manual outreach sends will exclude them. Account emails remain available. No email is sent."
          )}
        </p>
        <div :if={@saved != []} id="withdrawal-result" role="status">
          <p>{gettext("Unsubscribe request recorded.")}</p>
          <ul>
            <li :for={email <- @saved}>{email} · {gettext("Withdrawn")}</li>
          </ul>
        </div>
        <.form
          for={@form}
          id="newsletter-withdrawal"
          phx-submit="record-withdrawal"
          class="mt-4 space-y-4"
        >
          <fieldset :if={@addresses != []}>
            <legend>{gettext("Email addresses")}</legend>
            <label :for={email <- @addresses} class="block py-2 break-all">
              <input
                type="checkbox"
                name="withdrawal[emails][]"
                value={email}
                checked={email in (@form.params["emails"] || [])}
              />
              {email} · {if MapSet.member?(@withdrawn, email),
                do: gettext("Withdrawn"),
                else: gettext("No withdrawal recorded")}
            </label>
          </fieldset>
          <.input
            :if={@addresses == []}
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            required
          />
          <.input
            field={@form[:reason]}
            type="textarea"
            label={gettext("Request details")}
            required
            maxlength="2000"
          />
          <button
            type="submit"
            class="crm-button"
            data-confirm={
              gettext(
                "Unsubscribe the selected addresses? Pending sends will check withdrawal before dispatch."
              )
            }
          >{gettext("Unsubscribe")}</button>
        </.form>
      </section>
    </Layouts.management>
    """
  end
end
