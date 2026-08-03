defmodule PauseAiCa.Campaigns.PendingLetter do
  @moduledoc """
  A letter held until its sender proves they own the address it replies to.

  Someone who is signed in with a confirmed address has already proved that, so
  their letters never come through here. Everyone else gets one email, and the
  letter goes to the member of parliament when they click the link in it.

  This is a queue, not a store. Rows are deleted the moment the letter is sent,
  and expired rows are swept, so an unconfirmed letter leaves nothing behind.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @hash_algorithm :sha256
  @rand_size 32
  @validity_hours 24

  schema "pending_letters" do
    field :token, :binary
    field :sender_name, :string
    field :sender_email, :string
    field :recipients, :string
    field :subject, :string
    field :body, :string
    field :locale, :string, default: "en"
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds a pending letter and the plaintext token to email.

  Only the hash is stored, so a leak of the table does not let anyone release
  someone else's letter.
  """
  @spec build(map()) :: {String.t(), Ecto.Changeset.t()}
  def build(attrs) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed = :crypto.hash(@hash_algorithm, token)

    expires_at =
      DateTime.utc_now() |> DateTime.add(@validity_hours, :hour) |> DateTime.truncate(:second)

    changeset =
      %__MODULE__{}
      |> cast(attrs, [:sender_name, :sender_email, :recipients, :subject, :body, :locale])
      |> validate_required([:sender_email, :recipients, :subject, :body])
      |> validate_length(:body, max: 8_000)
      |> put_change(:token, hashed)
      |> put_change(:expires_at, expires_at)

    {Base.url_encode64(token, padding: false), changeset}
  end

  @doc "Hashes a plaintext token for lookup."
  @spec hash(String.t()) :: {:ok, binary()} | :error
  def hash(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} -> {:ok, :crypto.hash(@hash_algorithm, decoded)}
      :error -> :error
    end
  end

  @doc "How long an unconfirmed letter survives."
  @spec validity_hours() :: pos_integer()
  def validity_hours, do: @validity_hours
end
