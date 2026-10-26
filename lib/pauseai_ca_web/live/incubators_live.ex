defmodule PauseAiCaWeb.IncubatorsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Incubators

  @impl true
  def mount(params, session, socket) do
    locale =
      case socket.assigns.live_action do
        :fr -> "fr"
        :en -> "en"
        _ -> PauseAiCaWeb.Site.locale(params, socket)
      end

    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    socket =
      assign(socket,
        locale: locale,
        page_title: gettext("Local groups"),
        participation_context:
          PauseAiCa.Accounts.Onboarding.context(
            Map.put(params, "locale", locale),
            session["learning_visitor_id"]
          ),
        groups: [],
        group: nil,
        membership: nil,
        reference: nil,
        invitation: nil,
        error: nil,
        form: to_form(%{}, as: "application")
      )

    if Application.get_env(:pauseai_ca, :incubators_enabled, false) do
      if connected?(socket), do: Process.send_after(self(), :refresh_access, 30_000)
      {:ok, socket}
    else
      {:ok, redirect(socket, to: "/#{locale}")}
    end
  end

  @impl true
  def handle_params(params, _, socket) do
    if socket.assigns.live_action == :join do
      with {:ok, group} <- Incubators.public_group(params["id"]),
           {:ok, membership} <- Incubators.mine(socket.assigns.current_scope, params["id"]) do
        {:noreply,
         socket
         |> assign(
           group: group,
           membership: membership,
           reference: nil,
           invitation: nil,
           error: nil
         )
         |> application_form()}
      else
        _ ->
          {:noreply,
           socket
           |> put_flash(:error, gettext("This group is unavailable or your access has changed."))
           |> redirect(to: directory(socket.assigns.locale))}
      end
    else
      {:noreply, assign(socket, groups: Incubators.public_groups(), group: nil)}
    end
  end

  @impl true
  def handle_event(event, params, socket) do
    cond do
      !Application.get_env(:pauseai_ca, :incubators_enabled, false) ->
        {:noreply, redirect(socket, to: directory(socket.assigns.locale))}

      is_nil(socket.assigns.group) ->
        {:noreply, socket}

      true ->
        action(event, params, socket)
    end
  end

  defp action("save", %{"application" => attrs}, socket) do
    result =
      Incubators.request(
        socket.assigns.current_scope,
        socket.assigns.group.group_id,
        attrs,
        revision(socket)
      )

    case result do
      {:ok, membership} ->
        {:noreply,
         socket
         |> assign(membership: membership, reference: nil, invitation: nil, error: nil)
         |> application_form()
         |> put_flash(:info, gettext("Your request has been saved."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(attrs, as: "application", errors: changeset.errors),
           error: error_text(changeset)
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket, form: to_form(attrs, as: "application"), error: error_text(reason))}
    end
  end

  defp action("reload", _, socket) do
    with {:ok, group} <- Incubators.public_group(socket.assigns.group.group_id),
         {:ok, membership} <-
           Incubators.mine(socket.assigns.current_scope, socket.assigns.group.group_id) do
      {:noreply,
       socket
       |> assign(
         group: group,
         membership: membership,
         reference: nil,
         invitation: nil,
         error: nil
       )
       |> application_form()}
    else
      _ -> {:noreply, redirect(socket, to: directory(socket.assigns.locale))}
    end
  end

  defp action("reference", _, socket) do
    case Incubators.issue_reference(
           socket.assigns.current_scope,
           socket.assigns.group.group_id,
           revision(socket)
         ) do
      {:ok, receipt} ->
        {:noreply,
         assign(socket, membership: receipt.membership, reference: receipt.reference, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: error_text(reason))}
    end
  end

  defp action("withdraw", _, socket) do
    case Incubators.withdraw(
           socket.assigns.current_scope,
           socket.assigns.group.group_id,
           revision(socket)
         ) do
      {:ok, membership} ->
        {:noreply,
         socket
         |> assign(membership: membership, reference: nil, invitation: nil, error: nil)
         |> application_form()
         |> put_flash(:info, gettext("Your request has been withdrawn."))}

      {:error, reason} ->
        {:noreply, assign(socket, error: error_text(reason))}
    end
  end

  defp action("invitation", _, socket) do
    case Incubators.invitation(socket.assigns.current_scope, socket.assigns.group.group_id) do
      {:ok, url} when is_binary(url) and url != "" ->
        {:noreply, assign(socket, invitation: url, error: nil)}

      _ ->
        {:noreply,
         assign(socket,
           invitation: nil,
           error: gettext("An invitation is not available yet. Contact the group manager.")
         )}
    end
  end

  defp action(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:refresh_access, socket) do
    Process.send_after(self(), :refresh_access, 30_000)

    if Application.get_env(:pauseai_ca, :incubators_enabled, false) do
      if socket.assigns.group do
        with {:ok, group} <- Incubators.public_group(socket.assigns.group.group_id),
             {:ok, membership} <-
               Incubators.mine(socket.assigns.current_scope, socket.assigns.group.group_id) do
          if (membership && membership.revision) == revision(socket) do
            {:noreply, assign(socket, group: group, invitation: nil)}
          else
            {:noreply,
             assign(socket,
               group: group,
               invitation: nil,
               reference: nil,
               error: error_text(:stale)
             )}
          end
        else
          _ -> {:noreply, redirect(socket, to: directory(socket.assigns.locale))}
        end
      else
        {:noreply, assign(socket, groups: Incubators.public_groups())}
      end
    else
      {:noreply, redirect(socket, to: "/#{socket.assigns.locale}")}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp application_form(socket) do
    m = socket.assigns.membership
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    attrs =
      if m,
        do: %{"display_name" => m.display_name, "identifier" => m.identifier},
        else: %{"display_name" => user && user.name, "identifier" => ""}

    assign(socket, form: to_form(attrs, as: "application"))
  end

  defp revision(socket), do: socket.assigns.membership && socket.assigns.membership.revision
  defp editable?(nil), do: true

  defp editable?(m),
    do: m.status in ~w(pending withdrawn rejected removed) and not m.external_removal_pending

  def directory("fr"), do: "/fr/groupes"
  def directory(_), do: "/en/groups"
  defp title(group, "fr"), do: group.name_fr
  defp title(group, _), do: group.name_en
  defp summary(group, "fr"), do: group.summary_fr
  defp summary(group, _), do: group.summary_en

  def status("pending"), do: gettext("Pending review")
  def status("approved"), do: gettext("Approved")
  def status("admitted"), do: gettext("Admission confirmed")
  def status("withdrawn"), do: gettext("Withdrawn")
  def status("rejected"), do: gettext("Declined")
  def status("suspended"), do: gettext("Suspended")
  def status("removed"), do: gettext("Removed")
  def status(_), do: gettext("Unavailable")

  def error_text(%Ecto.Changeset{}),
    do: gettext("Check the required fields, postal areas and secure links, then try again.")

  def error_text(:stale), do: gettext("This record changed. Reload the page before trying again.")

  def error_text(:cooldown),
    do: gettext("Please wait one minute before requesting another reference.")

  def error_text(:invalid_reference),
    do:
      gettext(
        "This reference is invalid, expired or already used. Ask the applicant for a new one."
      )

  def error_text(:last_manager),
    do: gettext("Assign another confirmed manager before removing the last manager.")

  def error_text(:identifier_collision),
    do:
      gettext(
        "This identifier is already linked to another approved member. Resolve the match before approving."
      )

  def error_text(:removal_pending),
    do: gettext("A manager must confirm removal from the external group before a new request.")

  def error_text(_),
    do:
      gettext(
        "This action is unavailable. Check the member status, required confirmation and your current access."
      )

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      translated_path={directory(if @locale == "fr", do: "en", else: "fr")}
    >
      <section
        class="mx-auto max-w-4xl px-5 py-8 space-y-6 [&_.label]:whitespace-normal [&_.label]:items-start [&_.label]:max-w-full [&_.checkbox]:shrink-0"
        id="incubators"
      >
        <nav aria-label={gettext("Breadcrumbs")} class="text-sm">
          <.link href={"/#{@locale}"} class="underline">{gettext("Home")}</.link>
          / <.link href={directory(@locale)} class="underline">{gettext("Local groups")}</.link>
        </nav>
        <h1 class="text-3xl font-bold">
          {if @group, do: title(@group, @locale), else: gettext("Local groups")}
        </h1>
        <div :if={@error} role="alert" class="rounded-lg border border-warning p-4">{@error}</div>
        <button
          :if={@error && @group}
          phx-click="reload"
          data-confirm={gettext("Reload and discard unsaved request changes?")}
          class="btn btn-outline"
        >{gettext("Reload request")}</button>
        <div :if={!@group} class="space-y-4">
          <p>{gettext("Find a local group, see its activities and request to join.")}</p>
          <p :if={@groups == []}>
            {gettext("Join a local waitlist below or offer to help start an incubator in your area.")}
          </p>
          <article
            :for={group <- @groups}
            class="rounded-xl border border-base-300 p-5 space-y-3"
            id={"group-#{group.group_id}"}
          >
            <h2 class="text-xl font-semibold">{title(group, @locale)}</h2>
            <p class="whitespace-pre-line">{summary(group, @locale)}</p>
            <p :if={group.fsas != []} class="text-sm">
              {gettext("Postal areas")}: {Enum.join(group.fsas, ", ")}<br />{gettext(
                "FSA: the first three characters of your postal code, for example H2X."
              )}
            </p>
            <div class="flex flex-wrap gap-4 items-center">
              <.link
                href={"/groups/#{group.group_id}/join?#{URI.encode_query(%{locale: @locale})}"}
                class="btn btn-primary"
              >{gettext("Request to join")}</.link>
              <button
                type="button"
                phx-click="choose-group"
                phx-value-group-id={group.group_id}
                phx-target="#participation"
                class="btn btn-outline"
              >{gettext("Join the waitlist")}</button>
              <.link
                :if={group.events_url not in [nil, ""]}
                href={group.events_url}
                class="underline"
                target="_blank"
                rel="noopener noreferrer"
              >{gettext("Group events")}</.link>
            </div>
          </article>
          <div id="group-participation" class="rounded-xl border border-base-300 p-5">
            <.live_component
              module={PauseAiCaWeb.ParticipationForm}
              id="groups-participation-entry"
              locale={@locale}
              current_scope={@current_scope}
              context={@participation_context}
              intent="waitlist"
              city=""
              registration={false}
              show_ctas={false}
              group_focused={true}
              group_cities={Application.get_env(:pauseai_ca, :local_waitlist_cities, [])}
            />
          </div>
        </div>
        <div :if={@group} class="space-y-5">
          <p class="whitespace-pre-line">{summary(@group, @locale)}</p>
          <p :if={@group.moderator_contact not in [nil, ""]}>
            {gettext("Group manager")}: <span class="break-words">{@group.moderator_contact}</span>
          </p>
          <div :if={@membership} class="rounded-xl bg-base-200 p-4 space-y-2" id="my-membership">
            <p>{gettext("Your request")}: <strong>{status(@membership.status)}</strong></p>
            <p :if={@membership.external_removal_pending}>
              {gettext("External removal is awaiting manager confirmation.")}
            </p>
            <button
              :if={@membership.status == "pending" and @group.whatsapp_enabled}
              phx-click="reference"
              class="btn btn-outline"
            >{gettext("Create private matching reference")}</button>
            <p :if={@reference} class="space-y-2" id="matching-reference">
              <strong class="break-all">{@reference}</strong><br />{gettext(
                "Send this reference privately to the group manager using your WhatsApp account. It expires after 15 minutes and can be used once."
              )}
            </p>
            <button
              :if={
                @group.whatsapp_enabled and @membership.status in ["approved", "admitted"] and
                  @membership.matched_at
              }
              phx-click="invitation"
              class="btn btn-primary"
            >{gettext("Show my invitation")}</button>
            <.link
              :if={@invitation}
              href={@invitation}
              target="_blank"
              rel="noopener noreferrer"
              class="underline"
            >{gettext("Open WhatsApp invitation")}</.link>
            <p :if={@invitation}>
              {gettext(
                "The group manager must approve admission in WhatsApp. Website approval does not add you automatically."
              )}
            </p>
            <button
              :if={@membership.status in ["pending", "approved", "admitted", "suspended"]}
              phx-click="withdraw"
              data-confirm={gettext("Withdraw your request and group access?")}
              class="btn btn-ghost"
            >{gettext("Withdraw request")}</button>
          </div>
          <.form
            :if={editable?(@membership)}
            for={@form}
            id="incubator-application"
            phx-submit="save"
            class="rounded-xl border border-base-300 p-5 space-y-4"
          >
            <h2 class="text-xl font-semibold">
              {if @membership && @membership.status == "pending",
                do: gettext("Edit your request"),
                else: gettext("Request to join")}
            </h2>
            <.input field={@form[:display_name]} label={gettext("Name")} required maxlength="100" />
            <.input
              :if={@group.whatsapp_enabled}
              field={@form[:identifier]}
              label={gettext("Your WhatsApp identifier")}
              required
              maxlength="100"
            />
            <p :if={@group.whatsapp_enabled} class="text-sm">
              {gettext(
                "Use the phone number or identifier the manager can recognize in WhatsApp. Only group managers can review it."
              )}<br />{gettext(
                "When joining with a phone number, other WhatsApp group members can see that number. Use an active username where supported."
              )}
            </p>
            <p>
              {gettext(
                "Respect others, protect personal information and follow the group manager's conduct guidance."
              )}
            </p>
            <.input
              name="application[conduct]"
              type="checkbox"
              value={false}
              label={gettext("I agree to follow these conduct rules.")}
              required
            />
            <p :if={Keyword.has_key?(@form.errors, :conduct_at)} class="text-error" role="alert">
              {gettext("Please agree to the conduct rules before saving your request.")}
            </p>
            <button type="submit" class="btn btn-primary">{gettext("Save request")}</button>
          </.form>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
