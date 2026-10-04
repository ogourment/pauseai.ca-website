defmodule PauseAiCa.Newsletters.Subscription do
  @moduledoc "Local newsletter-purpose consent, independent of account confirmation and provider membership."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @derive {Inspect, except: [:confirmation_hash]}
  schema "newsletter_subscriptions" do
    field :email, :string
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
end
