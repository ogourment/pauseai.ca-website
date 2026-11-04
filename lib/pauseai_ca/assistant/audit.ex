defmodule PauseAiCa.Assistant.Audit do
  @moduledoc "Fresh superadmin authorization and durable access logging for metadata-only audit pages."
  import Ecto.Query
  alias PauseAiCa.{Assistant, Repo}
  alias PhoenixAgentAssistant.{AuditLog, Store}

  def page(scope, params) when is_map(params) do
    if Assistant.eligible?(scope) do
      config = Assistant.configuration()

      event = %{
        "kind" => "audit_viewed",
        "projection" => "metadata",
        "kind_filter" => safe_kind(params["kind"]),
        "actor_filter" => safe_actor(params["actor"]),
        "continuation" => is_binary(params["cursor"]) and params["cursor"] != ""
      }

      with true <- AuditLog.keys_ready?(config[:audit_keys]),
           {:ok, _} <-
             Store.record(
               Assistant.store(),
               scope.user.id,
               Ecto.UUID.generate(),
               event,
               config[:audit_keys],
               stream: "audit-access"
             ),
           true <- Assistant.eligible?(scope),
           {:ok, options} <- options(params, scope.user.id),
           {:ok, result} <- AuditLog.page(Assistant.store(), options, config[:audit_keys]),
           true <- Assistant.eligible?(scope) do
        {:ok, result}
      else
        {:error, {:audit_integrity_failed, reference}} ->
          integrity_intent(scope, reference, config)
          {:error, :audit_unavailable}

        {:error, :audit_chain_invalid} ->
          integrity_intent(scope, "audit-access-head", config)
          {:error, :audit_unavailable}

        false ->
          {:error, :audit_unavailable}

        _ ->
          {:error, :audit_unavailable}
      end
    else
      {:error, :forbidden}
    end
  end

  def page(_, _), do: {:error, :audit_unavailable}

  def accounts(scope, displayed_ids \\ [], selected_actor \\ nil) do
    if Assistant.eligible?(scope) do
      query =
        from(s in PhoenixAgentAssistant.Store.Stream,
          left_join: u in PauseAiCa.Accounts.User,
          on: fragment("?::text", u.id) == s.actor_id,
          where: s.namespace == ^Assistant.store().namespace,
          distinct: s.actor_id,
          order_by: s.actor_id,
          select: %{id: s.actor_id, email: u.email}
        )

      selected = safe_actor(selected_actor)

      recorded =
        if selected not in [nil, "invalid"],
          do: Repo.one(from(s in query, where: s.actor_id == ^selected, limit: 1))

      if selected == "invalid" or (selected != nil and recorded == nil) do
        {:error, :invalid_actor_filter}
      else
        choices = Repo.all(from(s in query, limit: 100))

        choices =
          if recorded && not Enum.any?(choices, &(&1.id == selected)),
            do: Enum.take(choices, 99) ++ [recorded],
            else: choices

        displayed = Repo.all(from(s in query, where: s.actor_id in ^Enum.take(displayed_ids, 25)))
        labels = Map.new(choices ++ displayed, &{&1.id, &1.email})

        if Assistant.eligible?(scope),
          do: {:ok, %{choices: choices, labels: labels}},
          else: {:error, :forbidden}
      end
    else
      {:error, :forbidden}
    end
  end

  defp integrity_intent(scope, reference, config) do
    if Assistant.eligible?(scope) do
      Store.queue_alert(
        Assistant.store(),
        scope.user.id,
        "audit-integrity/" <> reference,
        :audit_integrity_failed,
        config[:audit_keys],
        stream: "audit-integrity",
        correlation_id: reference,
        severity: "error"
      )
    end
  end

  defp options(params, viewer) do
    kind = safe_kind(params["kind"])
    actor = safe_actor(params["actor"])
    cursor = params["cursor"]

    if kind != "invalid" and actor != "invalid" and
         (is_nil(cursor) or (is_binary(cursor) and byte_size(cursor) <= 2048)),
       do: {:ok, [kind: kind, actor: actor, cursor: cursor, viewer: viewer]},
       else: :error
  end

  defp safe_kind(value) when value in [nil, ""], do: nil
  defp safe_kind(value), do: if(value in AuditLog.kinds(), do: value, else: "invalid")
  defp safe_actor(value) when value in [nil, ""], do: nil

  defp safe_actor(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> id
      _ -> "invalid"
    end
  end
end
