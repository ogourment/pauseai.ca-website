defmodule PauseAiCa.Newsletters.WithdrawalToken do
  @moduledoc "Hashed withdrawal capabilities remain valid across subscription renewals."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @derive {Inspect, except: [:token_hash]}
  schema "newsletter_withdrawal_tokens" do
    field :subscription_id, :binary_id
    field :token_hash, :binary
    field :inserted_at, :utc_datetime_usec
  end
end
