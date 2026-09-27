defmodule PauseAiCa.Donations.Pledge do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "donation_pledges" do
    field :name, :string, redact: true
    field :email, :string, redact: true
    field :amount_cad, :decimal
    field :frequency, :string, default: "one_time"
    field :notes, :string, redact: true, default: ""
    field :locale, :string
    field :consented_at, :utc_datetime
    field :contact_consent, :boolean, virtual: true
    timestamps(type: :utc_datetime)
  end

  def changeset(pledge, attrs) do
    pledge
    |> cast(attrs, [:name, :email, :amount_cad, :notes, :contact_consent, :locale, :frequency])
    |> update_change(:name, &String.trim/1)
    |> update_change(:email, &String.downcase(String.trim(&1)))
    |> validate_required([:name, :email, :locale, :frequency])
    |> validate_length(:name, max: 160)
    |> validate_length(:email, max: 160)
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+\.[^@,;\s]+$/)
    |> validate_length(:notes, max: 2000)
    |> validate_number(:amount_cad, greater_than: 0, less_than: 1_000_000_000)
    |> validate_change(:amount_cad, fn field, amount ->
      if Decimal.equal?(amount, Decimal.round(amount, 2)),
        do: [],
        else: [{field, "must have at most two decimal places"}]
    end)
    |> validate_inclusion(:locale, ~w(en fr))
    |> validate_inclusion(:frequency, ~w(one_time monthly))
    |> validate_acceptance(:contact_consent)
    |> unique_constraint(:email)
  end
end
