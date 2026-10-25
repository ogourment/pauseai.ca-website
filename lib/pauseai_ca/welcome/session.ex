defmodule PauseAiCa.Welcome.Session do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "welcome_sessions" do
    belongs_to :group, PauseAiCa.Volunteers.Group
    belongs_to :host, PauseAiCa.Accounts.User
    belongs_to :creator, PauseAiCa.Accounts.User
    field :title, :string
    field :language, :string, default: "en"
    field :timezone, :string, default: "America/Toronto"
    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec
    field :meeting_url, :string, redact: true
    field :status, :string, default: "scheduled"
    field :revision, :integer, default: 1
    has_many :participants, PauseAiCa.Welcome.Participant
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :title,
      :host_id,
      :language,
      :timezone,
      :starts_at,
      :ends_at,
      :meeting_url,
      :status
    ])
    |> update_change(:title, &String.trim/1)
    |> validate_required([
      :title,
      :host_id,
      :language,
      :timezone,
      :starts_at,
      :ends_at,
      :meeting_url,
      :status
    ])
    |> validate_length(:title, max: 200)
    |> validate_length(:meeting_url, max: 2000)
    |> validate_inclusion(:language, ~w(en fr))
    |> validate_inclusion(:status, ~w(scheduled cancelled completed))
    |> validate_change(:meeting_url, fn field, url ->
      case URI.parse(url) do
        %URI{scheme: "https", host: host, userinfo: nil} when is_binary(host) and host != "" -> []
        _ -> [{field, "must be an HTTPS meeting link"}]
      end
    end)
  end
end
