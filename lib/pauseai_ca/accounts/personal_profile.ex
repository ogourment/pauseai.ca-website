defmodule PauseAiCa.Accounts.PersonalProfile do
  @moduledoc false

  import Ecto.Changeset, except: [change: 1, change: 2]
  import Ecto.Query
  use Gettext, backend: PauseAiCaWeb.Gettext

  alias PauseAiCa.{PostalArea, Repo, Volunteers.Profile}
  alias PauseAiCa.Accounts.User

  @contact_fields [
    :country,
    :contact_preference,
    :discord_handle,
    :signal_number,
    :whatsapp_number,
    :contact_notes
  ]
  @channel_fields %{
    "discord" => :discord_handle,
    "signal" => :signal_number,
    "whatsapp" => :whatsapp_number
  }
  @fields [:name, :phone, :city, :postal_code, :local_updates, :confirm_city | @contact_fields]
  @types Map.merge(Map.new(@fields, &{&1, :string}), %{
           local_updates: :boolean,
           confirm_city: :boolean
         })

  def editor(%User{} = user) do
    {draft, details} =
      case Repo.get_by(Profile, user_id: user.id) do
        %Profile{draft: draft, details: details} -> {draft, details}
        nil -> {%{}, %{}}
      end

    legacy = Map.merge(details, draft)
    contact = user.profile_contact || legacy

    values =
      Map.new(@contact_fields, &{&1, present(contact[Atom.to_string(&1)])})
      |> Map.merge(%{
        name: user.name,
        phone: user.phone,
        city: present(user.city) || if(is_nil(user.profile_contact), do: present(legacy["city"])),
        postal_code: display_postal(user.postal_code || user.fsa),
        local_updates: user.local_updates,
        confirm_city: false
      })

    city_alternatives =
      if contact["city_reviewed"] do
        []
      else
        [present(draft["city"]), present(details["city"])]
        |> Enum.uniq()
        |> Enum.reject(&(&1 in [nil, values.city]))
      end

    {values, city_alternatives}
  end

  def change(values, attrs \\ %{}) do
    {values, @types}
    |> cast(attrs, @fields)
    |> update_change(:name, &present/1)
    |> validate_length(:name, max: 160)
    |> update_change(:city, &present/1)
    |> validate_length(:city, max: 255)
    |> update_change(:postal_code, fn value -> value && PostalArea.normalize(value) end)
    |> validate_change(:postal_code, fn :postal_code, value ->
      if PostalArea.valid?(value) or full_postal?(value),
        do: [],
        else: [
          postal_code:
            dgettext_noop(
              "errors",
              "enter the first three characters or a full Canadian postal code"
            )
        ]
    end)
    |> update_change(:contact_preference, &present/1)
    |> validate_inclusion(:contact_preference, ~w(email discord signal whatsapp))
    |> User.validate_phone()
    |> validate_contact()
    |> validate_preferred_channel()
  end

  def update(%User{id: id}, baseline, attrs) do
    submitted = change(baseline, attrs)

    with {:ok, _} <- apply_action(submitted, :update) do
      # A form submits every field. Apply only the edits from this form to the
      # latest row so a save in another tab does not undo unrelated changes.
      changed_attrs = Map.take(attrs, Enum.map(Map.keys(submitted.changes), &Atom.to_string/1))

      Repo.transact(fn ->
        user = Repo.one!(from u in User, where: u.id == ^id, lock: "FOR UPDATE")
        {values, city_alternatives} = editor(user)
        profile = change(values, changed_attrs)

        with {:ok, updated} <- apply_action(profile, :update) do
          user
          |> user_changeset(updated, profile, city_alternatives)
          |> Repo.update()
        end
      end)
    end
  end

  def cache_representative(%User{id: id}, postal_code, representative) do
    from(u in User, where: u.id == ^id and u.postal_code == ^postal_code)
    |> Repo.update_all(
      set: [representative: representative, updated_at: DateTime.utc_now(:second)]
    )

    Repo.get!(User, id)
  end

  def display_postal(<<prefix::binary-size(3), suffix::binary-size(3)>>),
    do: prefix <> " " <> suffix

  def display_postal(value), do: value

  def full_postal?(value) do
    case value do
      <<prefix::binary-size(3), suffix::binary-size(3)>> ->
        PostalArea.valid?(prefix) and Regex.match?(~r/^\d[ABCEGHJKLMNPRSTVWXYZ]\d$/, suffix)

      _ ->
        false
    end
  end

  defp user_changeset(user, values, profile, city_alternatives) do
    postal =
      if changed?(profile, :postal_code), do: postal_changes(values.postal_code, user), else: %{}

    contact =
      Map.new(@contact_fields, &{Atom.to_string(&1), Map.fetch!(values, &1)})
      |> Map.put("city_reviewed", city_reviewed?(user, values, profile, city_alternatives))

    attrs =
      values
      |> Map.take([:name, :city, :phone, :local_updates])
      |> Map.put(:profile_contact, contact)
      |> Map.merge(postal)

    Ecto.Changeset.change(user, attrs)
  end

  defp city_reviewed?(user, values, profile, city_alternatives) do
    (user.profile_contact || %{})["city_reviewed"] == true ||
      changed?(profile, :city) || (city_alternatives != [] && values.confirm_city)
  end

  defp postal_changes(nil, _user), do: %{postal_code: nil, fsa: nil, representative: nil}

  defp postal_changes(<<fsa::binary-size(3)>>, _user),
    do: %{fsa: fsa, postal_code: nil, representative: nil}

  defp postal_changes(<<fsa::binary-size(3), _::binary-size(3)>> = full, user) do
    %{
      fsa: fsa,
      postal_code: full,
      representative: if(full == user.postal_code, do: user.representative)
    }
  end

  defp validate_contact(changeset) do
    Enum.reduce(@contact_fields -- [:contact_preference], changeset, fn field, acc ->
      acc
      |> update_change(field, &present/1)
      |> validate_length(field, max: 4000)
    end)
  end

  defp validate_preferred_channel(changeset) do
    field = @channel_fields[get_field(changeset, :contact_preference)]

    if field && (changed?(changeset, :contact_preference) || changed?(changeset, field)) &&
         is_nil(get_field(changeset, field)) do
      add_error(changeset, field, dgettext_noop("errors", "can't be blank"))
    else
      changeset
    end
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_), do: nil
end
