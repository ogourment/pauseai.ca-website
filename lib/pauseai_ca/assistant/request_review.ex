defmodule PauseAiCa.Assistant.RequestReview do
  @moduledoc "Freshly authorized, audited access and human decisions for retained exchanges."
  import Ecto.Query
  alias PauseAiCa.{Accounts, Assistant, Repo}
  alias PhoenixAgentAssistant.{AuditLog, Canonical, Store}
  alias PhoenixAgentAssistant.RequestReview, as: Review

  defmodule Confirmation do
    @moduledoc false
    @derive {Inspect, except: [:token]}
    defstruct [:token, :decision, :expires_at]
  end

  defmodule Notice do
    @moduledoc false
    @derive {Inspect, only: [:request_ref, :status]}
    defstruct [:request_ref, :status, :question]
  end

  @salt "assistant-held-answer-review-v1"
  @lifetime 300

  def read(scope, reference) do
    config = Assistant.configuration()

    with true <- Assistant.eligible?(scope),
         true <- AuditLog.keys_ready?(config[:audit_keys]),
         {:ok, %{entry: entry}} <-
           Store.record(
             Assistant.store(),
             scope.user.id,
             Ecto.UUID.generate(),
             %{"kind" => "audit_viewed", "projection" => "exchange", "request_id" => reference},
             config[:audit_keys],
             stream: "audit-access"
           ),
         :ok <- Assistant.anchor_entry(entry, config),
         {:ok, review} <-
           Review.read(
             Assistant.store(),
             reference,
             scope.user.id,
             config[:audit_keys],
             options(scope, config)
           ) do
      {:ok, review}
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  def confirmation(scope, review, decision) when decision in [:approve, :reject] do
    if Assistant.eligible?(scope) and review.status == :held and review.approvable do
      expires = DateTime.add(DateTime.utc_now(), @lifetime)

      payload = %{
        "reviewer" => scope.user.id,
        "request" => review.request_ref,
        "snapshot" => review.snapshot,
        "decision" => Atom.to_string(decision),
        "policy" => policy_binding(),
        "expires_at" => DateTime.to_iso8601(expires)
      }

      {:ok,
       %Confirmation{
         token: Phoenix.Token.sign(PauseAiCaWeb.Endpoint, @salt, payload),
         decision: decision,
         expires_at: expires
       }}
    else
      {:error, :forbidden}
    end
  end

  def decide(scope, reference, token, reason) do
    config = Assistant.configuration()

    with true <- Assistant.eligible?(scope),
         {:ok, payload} <-
           Phoenix.Token.verify(PauseAiCaWeb.Endpoint, @salt, token, max_age: @lifetime),
         true <- payload["reviewer"] == scope.user.id and payload["request"] == reference,
         true <- payload["policy"] == policy_binding(),
         {:ok, expires, 0} <- DateTime.from_iso8601(payload["expires_at"]),
         {:ok, decision} <- decision(payload["decision"]),
         {:ok, review} <-
           Review.decide(
             Assistant.store(),
             reference,
             scope.user.id,
             decision,
             reason,
             payload["snapshot"],
             config[:audit_keys],
             options(scope, config) ++ [expires_at: expires]
           ) do
      Phoenix.PubSub.broadcast(
        PauseAiCa.PubSub,
        "agent_assistant:review:" <> review.actor_id,
        {:assistant_review_decided, review.conversation,
         %Notice{request_ref: reference, status: review.status, question: review.question}}
      )

      {:ok, review}
    else
      false -> {:error, :confirmation_invalid}
      {:error, :expired} -> {:error, :confirmation_expired}
      {:error, :invalid} -> {:error, :confirmation_invalid}
      error -> error
    end
  rescue
    _ -> {:error, :review_unavailable}
  end

  defp options(scope, config) do
    [
      authorize: fn action, actor -> authorize(scope, action, actor) end,
      anchor: fn entry -> Assistant.anchor_entry(entry, config) end
    ]
  end

  defp authorize(scope, _action, actor) do
    if scope.user.id == actor do
      authorized =
        Repo.all(
          from u in Accounts.User,
            where: u.id == ^actor and u.superadmin == true and not is_nil(u.confirmed_at),
            lock: "FOR SHARE",
            select: u.id
        )

      if authorized == [actor], do: :ok, else: {:error, :forbidden}
    else
      {:error, :forbidden}
    end
  end

  defp policy_binding,
    do: Canonical.digest(%{"policy" => to_string(Assistant.configuration()[:safety_policy])})

  defp decision("approve"), do: {:ok, :approve}
  defp decision("reject"), do: {:ok, :reject}
  defp decision(_), do: {:error, :confirmation_invalid}
end
