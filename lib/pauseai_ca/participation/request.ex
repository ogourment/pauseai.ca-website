defmodule PauseAiCa.Participation.Request do
  use Ecto.Schema
  import Ecto.Changeset
  use Gettext, backend: PauseAiCaWeb.Gettext
  @primary_key {:id, :binary_id, autogenerate: true}
  @derive {Inspect, except: [:confirmation_hash, :withdrawal_hash, :help_text, :context]}
  schema "participation_requests" do
    field :email, :string
    field :name, :string
    field :phone, :string
    field :fsa, :string
    field :location, :string, virtual: true
    field :city, :string
    field :help_text, :string
    field :locale, :string, default: "en"
    field :newsletter, :boolean, default: false
    field :account, :boolean, default: false
    field :local, :boolean, virtual: true, default: false
    field :local_kind, :string
    field :state, :string, default: "pending"
    field :delivery_state, :string, default: "reserved"
    field :confirmation_hash, :binary
    field :withdrawal_hash, :binary
    field :expires_at, :utc_datetime_usec
    field :confirmed_at, :utc_datetime_usec
    field :withdrawn_at, :utc_datetime_usec
    field :context, :map, default: %{}
    belongs_to :user, PauseAiCa.Accounts.User, type: :binary_id
    belongs_to :followup_owner, PauseAiCa.Accounts.User, type: :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(request, attrs, allow_empty \\ false) do
    request
    |> cast(attrs, [
      :email,
      :name,
      :phone,
      :fsa,
      :location,
      :city,
      :help_text,
      :locale,
      :newsletter,
      :account,
      :local,
      :local_kind
    ])
    |> update_change(:email, &String.downcase(String.trim(&1)))
    |> update_change(:name, &String.trim/1)
    |> PauseAiCa.Accounts.User.validate_phone()
    |> update_change(:city, &String.trim/1)
    |> location()
    |> update_change(:fsa, &PauseAiCa.PostalArea.normalize/1)
    |> validate_required([:email, :locale])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> validate_length(:name, max: 160)
    |> validate_length(:city, max: 160)
    |> validate_length(:help_text, max: 2000)
    |> validate_format(:fsa, PauseAiCa.PostalArea.pattern(),
      message: "must be the first three characters of a Canadian postal code"
    )
    |> validate_inclusion(:locale, ~w(en fr))
    |> validate_inclusion(:local_kind, ~w(waitlist help))
    |> choices(allow_empty)
  end

  defp location(c) do
    case get_change(c, :location) do
      nil -> c
      value -> put_change(c, :fsa, PauseAiCa.PostalArea.normalize(value))
    end
  end

  defp choices(c, allow_empty) do
    c =
      if get_field(c, :newsletter) && get_field(c, :fsa) in [nil, ""],
        do:
          add_error(
            c,
            :location,
            dgettext_noop("errors", "enter the first three characters of your postal code")
          ),
        else: c

    c =
      if get_field(c, :local_kind) && get_field(c, :city) in [nil, ""] &&
           get_field(c, :fsa) in [nil, ""],
         do:
           add_error(
             c,
             :city,
             dgettext_noop("errors", "enter a city or postal area for local follow-up")
           ),
         else: c

    if allow_empty || get_field(c, :newsletter) || get_field(c, :account) ||
         get_field(c, :local_kind),
       do: c,
       else: add_error(c, :newsletter, dgettext_noop("errors", "choose at least one option"))
  end
end
