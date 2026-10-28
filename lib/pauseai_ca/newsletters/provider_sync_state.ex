defmodule PauseAiCa.Newsletters.ProviderSyncState do
  use Ecto.Schema
  @primary_key {:id, :string, autogenerate: false}
  schema "newsletter_provider_sync_states" do
    field :cursor_at, :utc_datetime_usec
    field :last_full_scan_at, :utc_datetime_usec
    field :full_scan, :boolean, default: false
    field :window_start, :date
    field :window_end, :date
    field :offset, :integer, default: 0
    field :partial, :boolean, default: false
    field :last_attempt_at, :utc_datetime_usec
    field :last_success_at, :utc_datetime_usec
    field :last_error, :string
    field :counts, :map, default: %{}
  end
end
