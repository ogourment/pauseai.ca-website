defmodule PauseAiCa.Assistant.Instructions do
  @moduledoc "Private, revisioned application coaching. Execution safeguards remain code-owned."
  import Ecto.Query
  import Bitwise, only: [band: 2]
  alias PauseAiCa.{Accounts.User, Repo}
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Assistant.{Instruction, InstructionRevision}

  @external_resource Path.expand("../../../priv/assistant/coaching.md", __DIR__)
  @fallback File.read!(@external_resource)

  # This setting deliberately lives outside provider configuration and audit policy.
  # Only trusted runtime configuration may supply it. Never serialize the list.
  def load_editors(nil), do: []

  def load_editors(path) when is_binary(path) do
    with {:ok, %{type: :regular, size: size, mode: mode, uid: uid}}
         when size <= 16_384 and band(mode, 0o077) == 0 and is_integer(uid) <- File.lstat(path),
         ^uid <- effective_uid(),
         {:ok, bytes} <- File.read(path),
         {:ok, emails} when is_list(emails) <- Jason.decode(bytes),
         true <-
           Enum.all?(
             emails,
             &(is_binary(&1) and byte_size(&1) <= 254 and String.contains?(&1, "@"))
           ) do
      Enum.map(emails, &normalize/1) |> Enum.uniq()
    else
      _ -> []
    end
  end

  def load_editors(_), do: []

  defp effective_uid do
    task = Task.async(&read_effective_uid/0)

    case Task.yield(task, 1000) || Task.shutdown(task, :brutal_kill) do
      {:ok, uid} -> uid
      _ -> nil
    end
  end

  defp read_effective_uid do
    case System.cmd("/usr/bin/id", ["-u"], stderr_to_stdout: true) do
      {output, 0} ->
        case Integer.parse(String.trim(output)) do
          {uid, ""} when uid >= 0 -> uid
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  def permitted?(%Scope{user: %{id: id}}) do
    case Repo.get(User, id) do
      %User{superadmin: true, confirmed_at: at, email: email} when not is_nil(at) ->
        normalize(email) in Application.get_env(:pauseai_ca, :assistant_instruction_editors, [])

      _ ->
        false
    end
  end

  def permitted?(_), do: false

  def get(scope) do
    if permitted?(scope), do: {:ok, current()}, else: {:error, :unauthorized}
  end

  def history(scope) do
    if permitted?(scope),
      do: {:ok, Repo.all(from r in InstructionRevision, order_by: [desc: r.revision], limit: 30)},
      else: {:error, :unauthorized}
  end

  def effective do
    case Repo.get(Instruction, 1) do
      %Instruction{published_source: source, published_revision: revision}
      when is_binary(source) ->
        {:ok, %{source: source, revision: revision, digest: digest(source)}}

      _ ->
        {:ok, %{source: @fallback, revision: 0, digest: digest(@fallback)}}
    end
  rescue
    _ -> {:error, :instructions_unavailable}
  end

  def save(scope, revision, source) when is_binary(source),
    do: change(scope, revision, :save, source)

  def save(_, _, _), do: {:error, :invalid}
  def publish(scope, revision), do: change(scope, revision, :publish, nil)

  defp change(scope, revision, action, source) do
    if permitted?(scope) do
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended('assistant-instructions', 0))")
        # Serialize with account revocation as well as other instruction writers.
        Repo.one!(from u in User, where: u.id == ^scope.user.id, lock: "FOR SHARE")
        unless permitted?(scope), do: Repo.rollback(:unauthorized)
        instruction = current()
        unless to_string(instruction.revision) == to_string(revision), do: Repo.rollback(:stale)

        if action == :publish and instruction.revision == 0, do: Repo.rollback(:draft_required)

        instruction =
          if instruction.__meta__.state == :built,
            do: Repo.insert!(instruction),
            else: instruction

        attrs =
          case action do
            :save ->
              %{source: source, updated_by: scope.user.id}

            :publish ->
              %{
                published_source: instruction.source,
                published_revision: instruction.revision + 1,
                published_by: scope.user.id,
                published_at: DateTime.utc_now(),
                updated_by: scope.user.id
              }
          end

        case PhoenixCMS.Revisions.update(
               Repo,
               Instruction.changeset(instruction, attrs),
               InstructionRevision,
               fn saved ->
                 %{
                   revision: saved.revision,
                   editor_id: scope.user.id,
                   action: to_string(action),
                   source: saved.source,
                   published_source: saved.published_source,
                   published_revision: saved.published_revision,
                   inserted_at: DateTime.utc_now()
                 }
               end
             ) do
          {:ok, saved} -> saved
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> notify(action)
    else
      {:error, :unauthorized}
    end
  end

  defp current, do: Repo.get(Instruction, 1) || %Instruction{id: 1, source: @fallback}

  defp notify({:ok, _} = result, :publish) do
    Phoenix.PubSub.broadcast(
      PauseAiCa.PubSub,
      "agent_assistant:settings",
      :assistant_settings_changed
    )

    result
  end

  defp notify(result, _), do: result
  defp normalize(email), do: email |> String.trim() |> String.downcase()
  defp digest(source), do: :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)
end
