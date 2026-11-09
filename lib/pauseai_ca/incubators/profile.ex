defmodule PauseAiCa.Incubators.Profile do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "incubator_profiles" do
    field :group_id, :binary_id
    field :name_en, :string
    field :name_fr, :string
    field :summary_en, :string, default: ""
    field :summary_fr, :string, default: ""
    field :fsas, {:array, :string}, default: []
    field :published, :boolean, default: false
    field :stage, :string, default: "active"
    field :events_url, :string
    field :next_event_title_en, :string
    field :next_event_title_fr, :string
    field :next_event_starts_at, :utc_datetime
    field :next_event_timezone, :string
    field :next_event_url, :string
    field :moderator_contact, :string
    field :whatsapp_enabled, :boolean, default: false
    field :whatsapp_invite_url, :string, redact: true
    field :whatsapp_approval_confirmed, :boolean, default: false
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end
end
