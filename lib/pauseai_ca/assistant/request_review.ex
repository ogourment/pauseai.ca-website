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
    defstruct [:request_ref, :status, :question, :followup_ref, :phase]
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

  def confirmation(scope, review, decision) when decision in [:approve, :reject, :resume] do
    if Assistant.eligible?(scope) and
         ((review.status == :held and review.approvable) or
            (decision == :resume and review.status == :input_approved)) do
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
    reason = PhoenixAgentAssistant.Redactor.redact(reason)

    with true <- Assistant.eligible?(scope),
         true <-
           is_binary(reason) and String.valid?(reason) and byte_size(reason) <= 2000 and
             String.length(reason) <= 500,
         {:ok, payload} <-
           Phoenix.Token.verify(PauseAiCaWeb.Endpoint, @salt, token, max_age: @lifetime),
         true <- payload["reviewer"] == scope.user.id and payload["request"] == reference,
         true <- payload["policy"] == policy_binding(),
         {:ok, expires, 0} <- DateTime.from_iso8601(payload["expires_at"]),
         {:ok, decision} <- decision(payload["decision"]),
         {:ok, review} <-
           apply_decision(
             scope,
             reference,
             decision,
             reason,
             payload["snapshot"],
             config,
             expires
           ) do
      Phoenix.PubSub.broadcast(
        PauseAiCa.PubSub,
        "agent_assistant:review:" <> review.actor_id,
        {:assistant_review_decided, review.conversation,
         %Notice{
           request_ref: reference,
           status: notice_status(review),
           question: review.question,
           followup_ref: if(review.request_ref != reference, do: review.request_ref),
           phase: review.phase
         }}
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

  defp apply_decision(scope, reference, :resume, reason, snapshot, config, expires) do
    event = %{
      "kind" => "human_review_requested",
      "request_id" => reference,
      "reviewer" => scope.user.id,
      "decision" => "resume",
      "phase" => "input",
      "reason" => reason,
      "snapshot" => snapshot,
      "expires_at" => DateTime.to_iso8601(expires)
    }

    with {:ok, review} <- read(scope, reference),
         true <- review.snapshot == snapshot and review.status == :input_approved,
         {:ok, %{entry: entry}} <-
           Store.record(
             Assistant.store(),
             scope.user.id,
             "input-resume/" <> Canonical.digest(event),
             event,
             config[:audit_keys],
             stream: "human-reviews"
           ),
         :ok <- Assistant.anchor_entry(entry, config) do
      resume(scope, reference)
    else
      _ -> {:error, :review_changed}
    end
  end

  defp apply_decision(scope, reference, decision, reason, snapshot, config, expires) do
    with {:ok, review} <-
           Review.decide(
             Assistant.store(),
             reference,
             scope.user.id,
             decision,
             reason,
             snapshot,
             config[:audit_keys],
             options(scope, config) ++ [expires_at: expires]
           ) do
      if review.status == :input_approved do
        case resume(scope, reference) do
          {:ok, child} -> {:ok, child}
          {:error, reason} -> {:error, {:input_approved, review, reason}}
        end
      else
        {:ok, review}
      end
    end
  end

  defp notice_status(%{status: :released}), do: :approved
  defp notice_status(%{status: :held, phase: :output}), do: :output_held
  defp notice_status(review), do: review.status

  def resume(scope, reference) do
    config = Assistant.configuration()

    with {:ok, review} <- read(scope, reference),
         true <- review.status == :input_approved and review.phase == :input,
         %Accounts.User{} = requester <- Repo.get(Accounts.User, review.actor_id),
         requester_scope = Accounts.Scope.for_user(requester),
         true <- Assistant.visible?(requester_scope),
         {:ok, mode} <-
           PhoenixAgentAssistant.Modes.resolve(
             review.mode,
             config[:models],
             config[:allowed_modes] || ~w(fast normal high)
           ),
         true <- mode.model == review.model,
         {:ok, request} <-
           Assistant.refresh_reviewed_context(requester_scope, review.request, config) do
      config =
        config
        |> Keyword.put(:preference, review.mode)
        |> Keyword.put(:correlation_id, review.resume_ref)
        |> Keyword.put(:conversation_ref, review.conversation)
        |> Keyword.put(:review_feedback, :phase)
        |> Keyword.put(:input_review_approval, %{
          request_ref: reference,
          reviewer: scope.user.id,
          snapshot: review.snapshot,
          execution_digest: Canonical.digest(request)
        })

      result =
        PhoenixAgentAssistant.Runner.run(
          requester_scope,
          review.resume_ref,
          request,
          Assistant,
          config
        )

      case read(scope, review.resume_ref) do
        {:ok, child} ->
          {:ok, child}

        _ ->
          case result do
            {:error, reason} -> {:error, reason}
            _ -> {:error, :review_unavailable}
          end
      end
    else
      false -> {:error, :review_changed}
      error -> error
    end
  end

  def reviewer_current?(config) do
    case config[:input_review_approval] do
      nil ->
        true

      %{reviewer: id} ->
        Repo.exists?(
          from u in Accounts.User,
            where: u.id == ^id and u.superadmin == true and not is_nil(u.confirmed_at)
        )

      _ ->
        false
    end
  end

  def approved_input(requester_scope, request, config) do
    with %{
           request_ref: reference,
           reviewer: reviewer,
           snapshot: snapshot,
           execution_digest: execution_digest
         } <- config[:input_review_approval],
         %Accounts.User{} = user <- Repo.get(Accounts.User, reviewer),
         scope = Accounts.Scope.for_user(user),
         {:ok, review} <- read(scope, reference),
         true <- review.status == :input_approved and review.phase == :input,
         true <- review.actor_id == requester_scope.user.id,
         true <- review.resume_ref == config[:correlation_id],
         true <- review.snapshot == snapshot and Canonical.digest(request) == execution_digest,
         true <-
           Map.take(review.request, ["text", "attachments"]) ==
             Map.take(request, ["text", "attachments"]),
         true <-
           get_in(review.request, ["context", "history"]) ==
             get_in(request, ["context", "history"]),
         true <-
           get_in(review.input_review, ["decision", "policy"]) ==
             to_string(config[:safety_policy] || :strict_v1),
         true <-
           get_in(review.runtime_policy || %{}, ["instructions"]) ==
             json(config[:instruction_binding]),
         true <-
           get_in(review.runtime_policy || %{}, ["bindings"]) == json(config[:bindings] || %{}),
         :ok <- authorize(scope, :resume, review.actor_id) do
      decision = put_in(review.input_review, ["decision", "action"], "allow")

      {:ok,
       decision
       |> Map.put("human_review", true)
       |> Map.put("approved_request_ref", reference)
       |> Map.put("approval_snapshot", review.snapshot)}
    else
      _ -> {:error, :review_changed}
    end
  end

  defp json(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp options(scope, config) do
    [
      authorize: fn action, actor -> authorize(scope, action, actor) end,
      anchor: fn entry -> Assistant.anchor_entry(entry, config) end
    ]
  end

  defp authorize(scope, _action, _requester) do
    reviewer = scope.user.id

    authorized =
      Repo.all(
        from u in Accounts.User,
          where: u.id == ^reviewer and u.superadmin == true and not is_nil(u.confirmed_at),
          lock: "FOR SHARE",
          select: u.id
      )

    if authorized == [reviewer], do: :ok, else: {:error, :forbidden}
  end

  defp policy_binding,
    do: Canonical.digest(%{"policy" => to_string(Assistant.configuration()[:safety_policy])})

  defp decision("resume"), do: {:ok, :resume}
  defp decision("approve"), do: {:ok, :approve}
  defp decision("reject"), do: {:ok, :reject}
  defp decision(_), do: {:error, :confirmation_invalid}
end
