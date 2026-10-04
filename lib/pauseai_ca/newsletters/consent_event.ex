defmodule PauseAiCa.Newsletters.ConsentEvent do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "newsletter_consent_events" do
    field :subscription_id, :binary_id
    field :kind, :string
    field :consent_version, :string
    field :actor_id, :binary_id
    field :evidence, :map, default: %{}
    field :inserted_at, :utc_datetime_usec
  end
end
