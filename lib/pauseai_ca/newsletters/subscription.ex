defmodule PauseAiCa.Newsletters.Subscription do
  @moduledoc "Local newsletter-purpose consent, independent of account confirmation and provider membership."
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @derive {Inspect, except: [:confirmation_hash]}
  schema "newsletter_subscriptions" do
    field :email, :string
    field :name, :string
    field :fsa, :string
    field :state, :string
    field :locale, :string, default: "en"
    field :city, :string
    field :region, :string
    field :consent_version, :string
    field :requested_at, :utc_datetime_usec
    field :confirmed_at, :utc_datetime_usec
    field :withdrawn_at, :utc_datetime_usec
    field :confirmation_hash, :binary
    field :confirmation_expires_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def profile_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :fsa])
    |> update_change(:name, &String.trim/1)
    |> update_change(:fsa, &PauseAiCa.PostalArea.normalize/1)
    |> validate_length(:name, max: 160)
    |> validate_format(:fsa, PauseAiCa.PostalArea.pattern(),
      message: "must be the first three characters of a Canadian postal code"
    )
  end
end
