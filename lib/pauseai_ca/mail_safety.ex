defmodule PauseAiCa.MailSafety do
  @moduledoc """
  Final delivery boundary. Staging redirects exclusively to a currently confirmed
  admin resolved from the local database, never an address supplied by a caller.
  Persist admin_actor_id with scheduled operations and recheck it at dispatch.
  """
  alias PauseAiCa.{Accounts.User, Repo}

  def environment, do: Application.get_env(:pauseai_ca, :mail_environment, :blocked)

  def prepare(email, opts) do
    case environment() do
      mode when mode in [:dev, :test, :production] -> {:ok, email}
      :staging -> prepare_staging(email, Keyword.get(opts, :admin_actor_id))
      _ -> {:error, :mail_environment_blocked}
    end
  end

  def provider_writes_allowed?(), do: environment() in [:production, :test]

  defp prepare_staging(email, actor_id) when is_binary(actor_id) do
    case Ecto.UUID.cast(actor_id) do
      {:ok, id} ->
        case Repo.get(User, id) do
          %User{confirmed_at: confirmed, email: address} = user
          when not is_nil(confirmed) ->
            if PauseAiCa.Volunteers.allowed?(PauseAiCa.Accounts.Scope.for_user(user)) do
              {:ok,
               %{
                 email
                 | to: [{"Staging admin", address}],
                   cc: [],
                   bcc: [],
                   reply_to: nil,
                   subject: "[STAGING] " <> (email.subject || "")
               }}
            else
              {:error, :staging_admin_required}
            end

          _ ->
            {:error, :staging_admin_required}
        end

      _ ->
        {:error, :staging_admin_required}
    end
  end

  defp prepare_staging(_email, _actor), do: {:error, :staging_admin_required}
end
