defmodule PauseAiCaWeb.GroupResponsibilitiesComponent do
  use PauseAiCaWeb, :live_component
  alias PauseAiCa.Incubators

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket, mode: nil, editing: nil, form: to_form(%{}, as: "responsibility"), error: nil)}
  end

  @impl true
  def update(assigns, socket), do: {:ok, socket |> assign(assigns) |> load()}

  @impl true
  def handle_event("add", _, socket), do: {:noreply, open(socket, :add, nil)}

  def handle_event("edit", %{"id" => id}, socket), do: choose(socket, id, :edit)
  def handle_event("end", %{"id" => id}, socket), do: choose(socket, id, :end)
  def handle_event("cancel", _, socket), do: {:noreply, open(socket, nil, nil)}

  def handle_event("change", %{"responsibility" => attrs}, socket) do
    {:noreply, assign(socket, form: to_form(attrs, as: "responsibility"))}
  end

  def handle_event("save", %{"responsibility" => attrs}, socket) do
    case save(socket.assigns, attrs) do
      {:ok, _} ->
        {:noreply, socket |> open(nil, nil) |> load()}

      {:error, :forbidden} ->
        {:noreply, socket |> open(nil, nil) |> load()}

      {:error, reason} ->
        {:noreply,
         assign(socket, form: to_form(attrs, as: "responsibility"), error: error(reason))}
    end
  end

  defp choose(socket, id, mode) do
    case Enum.find(socket.assigns.records, &(&1.id == id && is_nil(&1.ends_on))) do
      nil -> {:noreply, assign(socket, error: error(:stale))}
      record -> {:noreply, open(socket, mode, record)}
    end
  end

  defp load(socket) do
    case Incubators.responsibilities(socket.assigns.scope, socket.assigns.group_id) do
      {:ok, records} -> assign(socket, accessible: true, records: records)
      _ -> socket |> open(nil, nil) |> assign(accessible: false, records: [], roster: [])
    end
  end

  defp open(socket, mode, record) do
    values =
      if record,
        do: %{"title" => record.title, "starts_on" => Date.to_iso8601(record.starts_on)},
        else: %{}

    assign(socket,
      mode: mode,
      editing: record,
      form: to_form(values, as: "responsibility"),
      error: nil
    )
  end

  defp save(%{mode: :add} = assigns, attrs) do
    with [id, raw_revision] <- String.split(attrs["member"] || "", ":", parts: 2),
         {revision, ""} <- Integer.parse(raw_revision),
         {:ok, date} <- Date.from_iso8601(attrs["starts_on"] || "") do
      Incubators.add_responsibility(assigns.scope, assigns.group_id, id, revision, %{
        title: attrs["title"],
        starts_on: date
      })
    else
      :error -> {:error, :inactive_membership}
      _ -> {:error, :invalid_date}
    end
  end

  defp save(%{mode: :edit, editing: record} = assigns, attrs) do
    with {:ok, date} <- Date.from_iso8601(attrs["starts_on"] || "") do
      Incubators.edit_responsibility(
        assigns.scope,
        assigns.group_id,
        record.id,
        record.revision,
        %{
          title: attrs["title"],
          starts_on: date
        }
      )
    end
  end

  defp save(%{mode: :end, editing: record} = assigns, attrs) do
    with {:ok, date} <- Date.from_iso8601(attrs["ends_on"] || "") do
      Incubators.end_responsibility(
        assigns.scope,
        assigns.group_id,
        record.id,
        record.revision,
        date
      )
    end
  end

  defp save(_, _), do: {:error, :stale}

  defp error(:stale),
    do: gettext("This responsibility changed. Review the latest values before saving again.")

  defp error(:inactive_membership), do: gettext("Choose a current group member.")
  defp error(:end_before_start), do: gettext("Enter an end date on or after the start date.")
  defp error(:invalid_title), do: gettext("Enter a responsibility title of up to 120 characters.")
  defp error(_), do: gettext("Check the title and dates.")

  defp members(roster) do
    for member <- roster, member.status in ~w(approved admitted) do
      {member.display_name, member.id <> ":" <> Integer.to_string(member.revision)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="group-responsibilities" class="space-y-4">
      <%= if @accessible do %>
        <h2 class="text-xl font-semibold">{gettext("Responsibilities")}</h2>
        <button
          :if={is_nil(@mode) and members(@roster) != []}
          type="button"
          class="btn btn-outline"
          phx-click="add"
          phx-target={@myself}
        >{gettext("Add responsibility")}</button>
        <p :if={@records == []}>{gettext("No responsibilities yet.")}</p>
        <ul class="divide-y divide-base-300">
          <li :for={record <- @records} id={"responsibility-#{record.id}"} class="py-3">
            <p><strong>{record.title}</strong> · {record.membership.display_name}</p>
            <p>
              <time datetime={Date.to_iso8601(record.starts_on)}>{Date.to_iso8601(record.starts_on)}</time>
              <span :if={record.ends_on}>–
              <time datetime={Date.to_iso8601(record.ends_on)}>{Date.to_iso8601(record.ends_on)}</time></span>
            </p>
            <div :if={is_nil(record.ends_on) and is_nil(@mode)} class="flex flex-wrap gap-2">
              <button
                :if={record.membership.status in ~w(approved admitted)}
                type="button"
                phx-click="edit"
                phx-value-id={record.id}
                phx-target={@myself}
                class="btn btn-outline"
              >{gettext("Edit")}</button>
              <button
                type="button"
                phx-click="end"
                phx-value-id={record.id}
                phx-target={@myself}
                class="btn btn-outline"
              >{gettext("End responsibility")}</button>
            </div>
          </li>
        </ul>
        <.form
          :if={@mode}
          for={@form}
          id="group-responsibility-form"
          phx-change="change"
          phx-submit="save"
          phx-target={@myself}
          class="space-y-3"
        >
          <.input
            :if={@mode == :add}
            field={@form[:member]}
            type="select"
            options={members(@roster)}
            prompt={gettext("Choose a member")}
            label={gettext("Member")}
            required
          />
          <.input
            :if={@mode != :end}
            field={@form[:title]}
            label={gettext("Responsibility")}
            maxlength="120"
            required
          />
          <.input
            :if={@mode != :end}
            field={@form[:starts_on]}
            type="date"
            label={gettext("Start date")}
            required
          />
          <.input
            :if={@mode == :end}
            field={@form[:ends_on]}
            type="date"
            label={gettext("End date")}
            required
          />
          <button type="submit" class="btn btn-primary">{gettext("Save responsibility")}</button>
          <button type="button" class="btn btn-outline" phx-click="cancel" phx-target={@myself}>{gettext(
            "Cancel"
          )}</button>
        </.form>
        <p :if={@error} role="alert">{@error}</p>
      <% end %>
    </section>
    """
  end
end
