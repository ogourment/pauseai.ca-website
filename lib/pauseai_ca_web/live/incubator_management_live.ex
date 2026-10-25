defmodule PauseAiCaWeb.IncubatorManagementLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.{Incubators, Volunteers}
  alias PauseAiCaWeb.IncubatorsLive, as: UI

  @impl true
  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    socket =
      assign(socket,
        locale: locale,
        page_title: gettext("Local groups"),
        groups: [],
        group_id: nil,
        profile: nil,
        roster: [],
        events: [],
        error: nil,
        form: to_form(%{}, as: "profile"),
        superadmin: false
      )

    if enabled?() do
      if connected?(socket), do: Process.send_after(self(), :refresh_access, 30_000)
      {:ok, socket}
    else
      {:ok, redirect(socket, to: "/dashboard")}
    end
  end

  @impl true
  def handle_params(params, _, socket) do
    groups = Incubators.managed_groups(socket.assigns.current_scope)
    group_id = params["group"] || (List.first(groups) && List.first(groups).id)
    {:noreply, reload(assign(socket, groups: groups, group_id: group_id))}
  end

  @impl true
  def handle_event(event, params, socket) do
    if enabled?(),
      do: action(event, params, socket),
      else: {:noreply, redirect(socket, to: "/dashboard")}
  end

  defp action("group", %{"group" => group}, socket),
    do: {:noreply, push_patch(socket, to: management_path(group, socket.assigns.locale))}

  defp action("configure_validate", %{"profile" => attrs, "_group_ref" => ref}, socket) do
    with true <- ref == socket.assigns.group_id,
         {:ok, _} <- Incubators.configuration(socket.assigns.current_scope, ref) do
      {:noreply, assign(socket, form: to_form(attrs, as: "profile"))}
    else
      _ -> {:noreply, denied(socket)}
    end
  end

  defp action("configure", %{"profile" => attrs} = params, socket) do
    revision = socket.assigns.profile && socket.assigns.profile.revision

    result =
      if params["_group_ref"] == socket.assigns.group_id and
           params["_profile_revision"] == to_string(revision || "") do
        Incubators.configure(
          socket.assigns.current_scope,
          socket.assigns.group_id,
          attrs,
          revision
        )
      else
        {:error, :stale}
      end

    case result do
      {:ok, _} ->
        {:noreply, socket |> reload() |> put_flash(:info, gettext("Group configuration saved."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(attrs, as: "profile", errors: changeset.errors),
           error: UI.error_text(changeset)
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket, form: to_form(attrs, as: "profile"), error: UI.error_text(reason))}
    end
  end

  defp action("match", %{"member" => attrs}, socket) do
    command(socket, attrs, fn scope, group, id, revision ->
      Incubators.match_reference(scope, group, id, attrs["reference"], revision)
    end)
  end

  defp action("decide", %{"member" => attrs} = params, socket) do
    action =
      Map.get(
        %{
          "approve" => :approve,
          "admit" => :admit,
          "reject" => :reject,
          "suspend" => :suspend,
          "remove" => :remove
        },
        params["decision"]
      )

    if action,
      do:
        command(socket, attrs, fn scope, group, id, revision ->
          Incubators.decide(scope, group, id, action, attrs, revision)
        end),
      else: {:noreply, socket}
  end

  defp action("delegate", %{"member" => %{"role" => role} = attrs}, socket)
       when role in ~w(member coordinator manager) do
    command(socket, attrs, fn scope, group, id, revision ->
      Incubators.delegate(scope, group, id, role, revision)
    end)
  end

  defp action("confirm_removal", %{"id" => id, "revision" => revision}, socket) do
    command(socket, %{"id" => id, "revision" => revision}, &Incubators.confirm_removal/4)
  end

  defp action(_, _, socket), do: {:noreply, socket}

  defp command(socket, attrs, fun) do
    with {revision, ""} <- Integer.parse(attrs["revision"] || ""),
         {:ok, _} <-
           fun.(socket.assigns.current_scope, socket.assigns.group_id, attrs["id"], revision) do
      {:noreply,
       socket |> reload(false) |> put_flash(:info, gettext("Group membership updated."))}
    else
      {:error, reason} -> {:noreply, assign(socket, error: UI.error_text(reason))}
      _ -> {:noreply, assign(socket, error: UI.error_text(:stale))}
    end
  end

  @impl true
  def handle_info(:refresh_access, socket) do
    Process.send_after(self(), :refresh_access, 30_000)

    if enabled?() do
      scope = socket.assigns.current_scope
      groups = Incubators.managed_groups(scope)
      # Keep an in-progress configuration form; only refresh authorization and roster.
      with {:ok, _} <- Incubators.configuration(scope, socket.assigns.group_id),
           {:ok, roster} <- Incubators.roster(scope, socket.assigns.group_id) do
        {:noreply,
         assign(socket, groups: groups, roster: roster, superadmin: Volunteers.superadmin?(scope))}
      else
        _ -> {:noreply, denied(assign(socket, groups: groups))}
      end
    else
      {:noreply, redirect(socket, to: "/dashboard")}
    end
  end

  defp reload(socket, reset_form \\ true) do
    scope = socket.assigns.current_scope
    id = socket.assigns.group_id

    with true <- enabled?(),
         {:ok, profile} <- Incubators.configuration(scope, id),
         {:ok, roster} <- Incubators.roster(scope, id),
         {:ok, events} <- Incubators.activity(scope, id) do
      attrs =
        if profile do
          Map.from_struct(profile)
          |> Map.update!(:fsas, &Enum.join(&1, ", "))
          |> Map.new(fn {key, value} -> {to_string(key), value} end)
        else
          %{
            "name_en" => "",
            "name_fr" => "",
            "fsas" => "",
            "published" => false,
            "whatsapp_enabled" => false,
            "whatsapp_approval_confirmed" => false
          }
        end

      assign(socket,
        profile: if(reset_form, do: profile, else: socket.assigns.profile),
        roster: roster,
        events: events,
        form: if(reset_form, do: to_form(attrs, as: "profile"), else: socket.assigns.form),
        error: nil,
        superadmin: Volunteers.superadmin?(scope)
      )
    else
      _ -> denied(socket)
    end
  end

  defp denied(socket),
    do:
      assign(socket,
        profile: nil,
        roster: [],
        events: [],
        group_id: nil,
        error: gettext("This group is unavailable or your access has changed.")
      )

  defp enabled?, do: Application.get_env(:pauseai_ca, :incubators_enabled, false)

  defp management_path(id, locale),
    do: "/manage/groups?" <> URI.encode_query(%{group: id || "", locale: locale})

  defp event_label("configure"), do: gettext("Configuration updated")
  defp event_label("request"), do: gettext("Join request saved")
  defp event_label("reference_issued"), do: gettext("Private reference created")
  defp event_label("identifier_matched"), do: gettext("Identifier matched")
  defp event_label("approve"), do: gettext("Request approved")
  defp event_label("admit"), do: gettext("Admission confirmed")
  defp event_label("reject"), do: gettext("Request declined")
  defp event_label("suspend"), do: gettext("Membership suspended")
  defp event_label("remove"), do: gettext("Membership removed")
  defp event_label("withdraw"), do: gettext("Request withdrawn")
  defp event_label("external_removal_confirmed"), do: gettext("External removal confirmed")
  defp event_label("delegate"), do: gettext("Group role updated")
  defp event_label(_), do: gettext("Group updated")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="groups"
      translated_path={management_path(@group_id, if(@locale == "fr", do: "en", else: "fr"))}
    >
      <section
        id="incubator-management"
        class="mx-auto max-w-6xl px-5 py-6 space-y-6 [&_.label]:whitespace-normal [&_.label]:items-start [&_.label]:max-w-full [&_.checkbox]:shrink-0"
      >
        <header class="rounded-xl border border-base-300 bg-base-200 p-4 space-y-3">
          <div class="flex flex-wrap justify-between gap-3 items-center">
            <h1 class="text-2xl font-bold">{gettext("Local groups")}</h1><.link
              href={UI.directory(@locale)}
              class="underline"
            >{gettext("Public directory")}</.link>
          </div>
          <form :if={@groups != []} phx-change="group" phx-submit="group" id="incubator-group-form">
            <.input
              type="select"
              name="group"
              label={gettext("Group")}
              value={@group_id}
              prompt={gettext("Choose a group")}
              options={Enum.map(@groups, &{&1.name, &1.id})}
            />
          </form>
          <p :if={@groups == []}>{gettext("You do not manage any groups.")}</p>
        </header>
        <p :if={@error} role="alert" class="rounded border border-warning p-4">{@error}</p>
        <div :if={@group_id} class="space-y-8">
          <.form
            for={@form}
            phx-submit="configure"
            phx-change="configure_validate"
            id="incubator-config"
            class="rounded-xl border border-base-300 p-5 space-y-4"
          >
            <input type="hidden" name="_group_ref" value={@group_id} />
            <input type="hidden" name="_profile_revision" value={@profile && @profile.revision} />
            <h2 class="text-xl font-semibold">{gettext("Group configuration")}</h2>
            <div class="grid gap-4 md:grid-cols-2">
              <.input
                field={@form[:name_en]}
                label={gettext("English name")}
                required
                maxlength="100"
              /><.input
                field={@form[:name_fr]}
                label={gettext("French name")}
                required
                maxlength="100"
              />
            </div>
            <div class="grid gap-4 md:grid-cols-2">
              <.input
                field={@form[:summary_en]}
                type="textarea"
                label={gettext("English description")}
                maxlength="2000"
              /><.input
                field={@form[:summary_fr]}
                type="textarea"
                label={gettext("French description")}
                maxlength="2000"
              />
            </div>
            <.input
              field={@form[:fsas]}
              label={gettext("Postal areas")}
              aria-describedby="incubator-fsa-help"
            /><p id="incubator-fsa-help" class="text-sm">
              {gettext("FSA: the first three characters of your postal code, for example H2X.")} {gettext(
                "Separate multiple areas with commas. These areas describe the group; they do not grant membership."
              )}
            </p>
            <.input field={@form[:events_url]} type="url" label={gettext("Public events link")} />
            <.input
              field={@form[:moderator_contact]}
              label={gettext("Public manager contact")}
              maxlength="200"
            />
            <.input
              field={@form[:whatsapp_enabled]}
              type="checkbox"
              label={gettext("Offer a manager-approved WhatsApp group")}
            />
            <.input
              field={@form[:whatsapp_invite_url]}
              type="url"
              label={gettext("Private WhatsApp invitation link")}
            />
            <.input
              field={@form[:whatsapp_approval_confirmed]}
              type="checkbox"
              label={gettext("I confirmed that managers approve new members in WhatsApp.")}
            />
            <p class="text-sm">
              {gettext(
                "Website approval and WhatsApp admission are separate. Confirm admission manually after checking the external group."
              )}
            </p>
            <.input
              :if={@superadmin}
              field={@form[:published]}
              type="checkbox"
              label={gettext("Publish in the public directory")}
            />
            <p :if={!@superadmin} class="text-sm">
              {gettext("A superadmin publishes this group in the public directory.")}
            </p>
            <button type="submit" class="btn btn-primary">{gettext("Save configuration")}</button>
          </.form>
          <section class="space-y-4" id="incubator-roster">
            <h2 class="text-xl font-semibold">{gettext("Requests and members")}</h2><p :if={
              @roster == []
            }>
              {gettext("No requests yet.")}
            </p>
            <article
              :for={member <- @roster}
              id={"membership-#{member.id}"}
              class="rounded-xl border border-base-300 p-5 space-y-4"
              data-status={member.status}
              data-revision={member.revision}
            >
              <div>
                <h3 class="text-lg font-semibold">{member.display_name}</h3><p>
                  {UI.status(member.status)}
                </p><p :if={member.identifier} class="break-words">
                  {gettext("WhatsApp identifier")}: {member.identifier}
                </p><p :if={member.matched_at}>{gettext("Identifier matched")}</p>
              </div>
              <form
                :if={
                  (member.status == "pending" and !member.matched_at and @profile) &&
                    @profile.whatsapp_enabled
                }
                phx-submit="match"
                class="space-y-2"
                id={"match-#{member.id}"}
              >
                <input type="hidden" name="member[id]" value={member.id} /><input
                  type="hidden"
                  name="member[revision]"
                  value={member.revision}
                />
                <.input
                  name="member[reference]"
                  label={gettext("Reference received privately from this applicant")}
                  value=""
                  required
                  autocomplete="off"
                  maxlength="100"
                />
                <button class="btn btn-outline" type="submit">{gettext("Match identifier")}</button>
              </form>
              <form phx-submit="decide" class="space-y-3" id={"decision-#{member.id}"}>
                <input type="hidden" name="member[id]" value={member.id} /><input
                  type="hidden"
                  name="member[revision]"
                  value={member.revision}
                />
                <.input
                  name="member[reason]"
                  value=""
                  label={gettext("Private moderation reason")}
                  maxlength="1000"
                />
                <.input
                  :if={member.status == "approved"}
                  name="member[observed_admission]"
                  value={false}
                  type="checkbox"
                  label={gettext("I verified this member's admission in the external group.")}
                />
                <div class="flex flex-wrap gap-2">
                  <button
                    :if={member.status == "pending"}
                    name="decision"
                    value="approve"
                    class="btn btn-primary"
                    type="submit"
                  >{gettext("Approve request")}</button>
                  <button
                    :if={member.status == "pending"}
                    name="decision"
                    value="reject"
                    class="btn btn-outline"
                    type="submit"
                  >{gettext("Decline request")}</button>
                  <button
                    :if={member.status == "approved"}
                    name="decision"
                    value="admit"
                    class="btn btn-primary"
                    type="submit"
                  >{gettext("Confirm admission")}</button>
                  <button
                    :if={member.status in ["approved", "admitted"]}
                    name="decision"
                    value="suspend"
                    class="btn btn-outline"
                    type="submit"
                  >{gettext("Suspend membership")}</button>
                  <button
                    :if={member.status in ["pending", "approved", "admitted", "suspended"]}
                    name="decision"
                    value="remove"
                    class="btn btn-outline"
                    type="submit"
                  >{gettext("Remove membership")}</button>
                </div>
              </form>
              <div
                :if={member.external_removal_pending}
                class="rounded border border-warning p-3 space-y-2"
              >
                <p>
                  {gettext(
                    "Remove this person from the external group, then confirm completion here."
                  )}
                </p><button
                  type="button"
                  phx-click="confirm_removal"
                  phx-value-id={member.id}
                  phx-value-revision={member.revision}
                  class="btn btn-outline"
                >{gettext("Confirm external removal")}</button>
              </div>
              <form
                :if={member.status in ["approved", "admitted"]}
                phx-submit="delegate"
                class="flex flex-wrap items-end gap-3"
                id={"delegate-#{member.id}"}
              >
                <input type="hidden" name="member[id]" value={member.id} /><input
                  type="hidden"
                  name="member[revision]"
                  value={member.revision}
                />
                <.input
                  type="select"
                  name="member[role]"
                  label={gettext("Group role")}
                  value={member.role}
                  options={[
                    {gettext("Member"), "member"},
                    {gettext("Coordinator"), "coordinator"},
                    {gettext("Manager"), "manager"}
                  ]}
                />
                <button type="submit" class="btn btn-outline">{gettext("Save group role")}</button>
              </form>
            </article>
          </section>
          <section class="space-y-3" id="incubator-activity">
            <h2 class="text-xl font-semibold">{gettext("Activity")}</h2><p :if={@events == []}>
              {gettext("No activity yet.")}
            </p><ul class="divide-y divide-base-300">
              <li :for={event <- @events} class="py-3">
                <p>{event_label(event.action)}</p><time
                  class="text-sm"
                  datetime={DateTime.to_iso8601(event.inserted_at)}
                >{Calendar.strftime(event.inserted_at, "%Y-%m-%d %H:%M UTC")}</time>
              </li>
            </ul>
          </section>
        </div>
      </section>
    </Layouts.management>
    """
  end
end
