defmodule PauseAiCaWeb.AssistantAuditLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Assistant
  alias PauseAiCa.Assistant.{Audit, RequestReview}
  alias PhoenixAgentAssistant.{AuditLog, Components}

  @impl true
  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if connected?(socket) and is_binary(params["request_ref"]),
      do: Process.send_after(self(), :review_access_refresh, 15_000)

    socket =
      assign(socket,
        locale: locale,
        page_title: gettext("Activity & security"),
        rows: [],
        accounts: [],
        error: nil,
        exchange: nil,
        reviewer_label: nil,
        exchange_loading: false,
        exchange_error: nil,
        confirmation: nil,
        decision_pending: false,
        decision_error: nil,
        decision_reason: "",
        decision_confirmed: false,
        request_ref: nil,
        next_cursor: nil,
        has_more: false,
        scan_limited: false,
        filters: %{"actor" => "", "kind" => ""}
      )

    if Assistant.eligible?(socket.assigns.current_scope),
      do: {:ok, socket},
      else: {:ok, deny(socket)}
  end

  @impl true
  def handle_params(params, _, socket) do
    scope = socket.assigns.current_scope

    if Assistant.eligible?(scope) do
      case Audit.page(scope, params) do
        {:ok, page} ->
          case Audit.accounts(scope, Enum.map(page.rows, & &1.actor_id), params["actor"]) do
            {:ok, %{choices: accounts, labels: labels}} ->
              rows =
                Enum.map(page.rows, fn row ->
                  Map.merge(row, %{
                    actor_label: Map.get(labels, row.actor_id) || gettext("Unlisted account"),
                    time_label: Calendar.strftime(row.inserted_at, "%Y-%m-%d %H:%M:%S UTC"),
                    activity_label: activity(row.kind),
                    outcome_label: event_outcome(row),
                    request_href: request_path(row.request_ref, socket.assigns.locale),
                    details: review_details(row)
                  })
                end)

              socket = load_exchange(socket, params["request_ref"])

              {:noreply,
               assign(socket,
                 rows: rows,
                 request_ref: params["request_ref"],
                 accounts: accounts,
                 next_cursor: page.next_cursor,
                 has_more: page.has_more,
                 scan_limited: page.scan_limited,
                 error: nil,
                 filters: %{"actor" => params["actor"] || "", "kind" => params["kind"] || ""}
               )}

            _ ->
              {:noreply, deny(socket)}
          end

        {:error, :forbidden} ->
          {:noreply, deny(socket)}

        _ ->
          {:noreply,
           assign(socket,
             rows: [],
             accounts: [],
             next_cursor: nil,
             has_more: false,
             scan_limited: false,
             error: gettext("Activity cannot be loaded securely.")
           )}
      end
    else
      {:noreply, deny(socket)}
    end
  end

  @impl true
  def handle_info(:review_access_refresh, socket) do
    if Assistant.eligible?(socket.assigns.current_scope) do
      Process.send_after(self(), :review_access_refresh, 15_000)

      socket =
        if match?(%{status: :running}, socket.assigns.exchange) and
             not socket.assigns.decision_pending,
           do:
             load_exchange(
               assign(socket, exchange: nil, exchange_loading: false),
               socket.assigns.request_ref
             ),
           else: socket

      {:noreply, socket}
    else
      {:noreply, deny(socket)}
    end
  end

  defp load_exchange(socket, reference) do
    if connected?(socket) and is_binary(reference) and
         (socket.assigns.request_ref != reference or
            (is_nil(socket.assigns.exchange) and not socket.assigns.exchange_loading)) do
      scope = socket.assigns.current_scope

      socket
      |> assign(
        exchange: nil,
        exchange_loading: true,
        exchange_error: nil,
        confirmation: nil,
        decision_pending: false,
        decision_error: nil
      )
      |> start_async({:load_exchange, reference}, fn -> RequestReview.read(scope, reference) end)
    else
      socket
    end
  end

  @impl true
  def handle_async({:load_exchange, reference}, {:ok, result}, socket) do
    cond do
      not Assistant.eligible?(socket.assigns.current_scope) ->
        {:noreply, deny(socket)}

      reference != socket.assigns.request_ref ->
        {:noreply, socket}

      true ->
        case result do
          {:ok, exchange} ->
            {:noreply,
             assign(socket,
               exchange: exchange,
               reviewer_label: reviewer_label(exchange),
               exchange_loading: false,
               exchange_error: nil
             )}

          {:error, :forbidden} ->
            {:noreply,
             assign(socket,
               exchange: nil,
               exchange_loading: false,
               exchange_error:
                 gettext("Superadmin permission is required to review this exchange.")
             )}

          _ ->
            {:noreply,
             assign(socket,
               exchange: nil,
               exchange_loading: false,
               exchange_error:
                 gettext(
                   "The saved exchange could not be loaded securely. Its activity is available below."
                 )
             )}
        end
    end
  end

  def handle_async({:load_exchange, _reference}, {:exit, _}, socket),
    do:
      {:noreply,
       assign(socket,
         exchange_loading: false,
         exchange_error:
           gettext(
             "The saved exchange could not be loaded securely. Its activity is available below."
           )
       )}

  def handle_async(:decide_exchange, {:ok, result}, socket) do
    if Assistant.eligible?(socket.assigns.current_scope) do
      case result do
        {:ok, exchange} ->
          updated =
            assign(socket,
              exchange: exchange,
              reviewer_label: reviewer_label(exchange),
              confirmation: nil,
              decision_pending: false,
              decision_error: nil,
              decision_reason: "",
              decision_confirmed: false
            )

          updated =
            if exchange.request_ref != socket.assigns.request_ref,
              do:
                push_patch(updated,
                  to: activity_path(exchange.request_ref, %{"locale" => socket.assigns.locale})
                ),
              else: updated

          {:noreply, updated}

        {:error, {:input_approved, exchange, reason}} ->
          {:noreply,
           assign(socket,
             exchange: exchange,
             confirmation: nil,
             decision_pending: false,
             decision_error: decision_error(reason)
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             decision_pending: false,
             decision_error: decision_error(reason)
           )}

        _ ->
          {:noreply,
           assign(socket,
             decision_pending: false,
             decision_error: decision_error(:unavailable)
           )}
      end
    else
      {:noreply, deny(socket)}
    end
  end

  def handle_async(:decide_exchange, {:exit, _}, socket),
    do:
      {:noreply,
       assign(socket, decision_pending: false, decision_error: decision_error(:unavailable))}

  @impl true
  def handle_event("prepare-decision", %{"decision" => action}, socket) do
    decision =
      case action do
        "approve" -> :approve
        "resume" -> :resume
        _ -> :reject
      end

    case socket.assigns.exchange do
      %{status: status, approvable: true} = exchange when status in [:held, :input_approved] ->
        case RequestReview.confirmation(socket.assigns.current_scope, exchange, decision) do
          {:ok, confirmation} ->
            {:noreply,
             assign(socket,
               confirmation: confirmation,
               decision_error: nil,
               decision_reason: "",
               decision_confirmed: false
             )}

          _ ->
            {:noreply, deny(socket)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel-decision", _, socket) do
    if Assistant.eligible?(socket.assigns.current_scope),
      do:
        {:noreply,
         assign(socket,
           confirmation: nil,
           decision_error: nil,
           decision_reason: "",
           decision_confirmed: false
         )},
      else: {:noreply, deny(socket)}
  end

  def handle_event("change-decision", %{"review" => params}, socket) do
    if Assistant.eligible?(socket.assigns.current_scope),
      do:
        {:noreply,
         assign(socket,
           decision_reason: params["reason"] || "",
           decision_confirmed: params["confirmed"] == "true",
           decision_error: nil
         )},
      else: {:noreply, deny(socket)}
  end

  def handle_event("confirm-decision", %{"review" => params}, socket) do
    scope = socket.assigns.current_scope
    confirmation = socket.assigns.confirmation
    reason = params["reason"] || ""

    cond do
      not Assistant.eligible?(scope) ->
        {:noreply, deny(socket)}

      socket.assigns.decision_pending ->
        {:noreply, socket}

      is_nil(confirmation) or params["token"] != confirmation.token ->
        {:noreply, assign(socket, decision_error: decision_error(:confirmation_invalid))}

      params["confirmed"] != "true" ->
        {:noreply,
         assign(socket,
           decision_reason: reason,
           decision_confirmed: false,
           decision_error:
             if(socket.assigns.exchange.phase == :input,
               do:
                 gettext(
                   "Confirm that you reviewed the displayed question and input review results."
                 ),
               else: gettext("Confirm that you reviewed the displayed answer.")
             )
         )}

      true ->
        reference = socket.assigns.request_ref
        token = confirmation.token

        {:noreply,
         socket
         |> assign(
           decision_pending: true,
           decision_error: nil,
           decision_reason: reason,
           decision_confirmed: true
         )
         |> start_async(:decide_exchange, fn ->
           RequestReview.decide(scope, reference, token, reason)
         end)}
    end
  end

  def handle_event(event, params, socket) do
    if Assistant.eligible?(socket.assigns.current_scope) do
      query =
        case event do
          "filter" ->
            if(is_map(params["audit"]),
              do: Map.take(params["audit"], ["actor", "kind"]),
              else: %{}
            )

          "next" ->
            Map.put(socket.assigns.filters, "cursor", socket.assigns.next_cursor)

          _ ->
            socket.assigns.filters
        end

      {:noreply,
       push_patch(socket,
         to:
           activity_path(
             socket.assigns.request_ref,
             Map.put(query, "locale", socket.assigns.locale)
           )
       )}
    else
      {:noreply, deny(socket)}
    end
  end

  defp deny(socket),
    do:
      socket
      |> assign(rows: [], accounts: [], next_cursor: nil, exchange: nil, confirmation: nil)
      |> redirect(to: "/")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="assistant"
      breadcrumb_context={
        PauseAiCaWeb.Navigation.assistant_breadcrumb_context(@current_scope, @locale)
      }
    >
      <div
        id="assistant-audit"
        data-breadcrumb-label={gettext("Activity & security")}
        class="crm-surface space-y-5"
      >
        <div class="management-controls space-y-3">
          <.link navigate={~p"/admin/assistant?#{[locale: @locale]}"}>{gettext("Back to assistant")}</.link>
          <h1 class="text-2xl font-bold">{gettext("Activity & security")}</h1>
          <p :if={is_nil(@request_ref)}>
            {gettext(
              "Choose a request to see what happened, whether an answer reached the user and whether anyone needs to act."
            )}
          </p>
          <div :if={@request_ref} id="assistant-request-timeline">
            <h2 class="text-lg font-semibold">{gettext("Request activity")}</h2>
            <p class="break-all">{gettext("Request reference")}: {@request_ref}</p>
            <p
              :if={@exchange_loading or (is_nil(@exchange) and is_nil(@exchange_error))}
              role="status"
            >
              {gettext("Loading the protected exchange…")}
            </p>
            <p :if={@exchange_error} id="assistant-exchange-error" role="alert">{@exchange_error}</p>
            <.exchange_review
              :if={@exchange}
              exchange={@exchange}
              confirmation={@confirmation}
              decision_pending={@decision_pending}
              decision_error={@decision_error}
              decision_reason={@decision_reason}
              decision_confirmed={@decision_confirmed}
              locale={@locale}
              reviewer_label={@reviewer_label}
            />
            <.link navigate={~p"/admin/assistant/activity?#{[locale: @locale]}"}>{gettext(
              "All activity"
            )}</.link>
          </div>
          <form id="assistant-audit-filters" phx-change="filter" class="flex flex-wrap gap-3">
            <.input
              type="select"
              id="audit-kind"
              name="audit[kind]"
              label={gettext("Activity")}
              value={@filters["kind"]}
              options={
                [{gettext("All activity"), ""}] ++ Enum.map(AuditLog.kinds(), &{activity(&1), &1})
              }
            />
            <.input
              type="select"
              id="audit-actor"
              name="audit[actor]"
              label={gettext("Account")}
              value={@filters["actor"]}
              options={
                [{gettext("All accounts"), ""}] ++
                  Enum.map(@accounts, &{&1.email || gettext("Unlisted account"), &1.id})
              }
            />
          </form>
        </div>
        <p :if={@error} role="alert">{@error}</p>
        <Components.audit_table
          id="assistant-audit-table"
          eligible={@error == nil}
          rows={@rows}
          local_times={true}
          locale={@locale}
          labels={
            %{
              time: gettext("Time"),
              actor: gettext("Account"),
              activity: gettext("Activity"),
              outcome: gettext("Outcome"),
              tokens: gettext("Tokens"),
              details: gettext("Review details")
            }
          }
        />
        <p :if={@error == nil and @rows == []} id="assistant-audit-empty">
          {if @has_more,
            do: gettext("No matching activity on this page. Continue to search older records."),
            else: gettext("No matching activity in the remaining records.")}
        </p>
        <p :if={@scan_limited}>
          {gettext("This page searched a bounded set of protected records. More records remain.")}
        </p>
        <details class="text-sm opacity-70">
          <summary class="min-h-11 cursor-pointer">{gettext("About this view")}</summary>
          <p>
            {gettext(
              "Up to 100 recorded accounts appear in the filter, including former administrators. — means token usage is unknown."
            )}
          </p>
          <p>
            {gettext(
              "Each displayed activity record is checked for authenticity. Exchange review verifies its complete conversation chain. Times use your browser’s timezone; the original UTC value is available on hover. These database times are separate from protected event timestamps."
            )}
          </p>
        </details>
        <div class="flex gap-3">
          <button
            id="assistant-audit-first"
            type="button"
            phx-click="first"
            class="btn btn-outline min-h-11"
          >{gettext("Newest")}</button>
          <button
            :if={@has_more}
            id="assistant-audit-next"
            type="button"
            phx-click="next"
            class="btn btn-outline min-h-11"
          >{gettext("Older")}</button>
        </div>
      </div>
    </Layouts.management>
    """
  end

  defp reviewer_label(%{decision: %{"reviewer" => id}}) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %PauseAiCa.Accounts.User{email: email} <- PauseAiCa.Repo.get(PauseAiCa.Accounts.User, id) do
      email
    else
      _ -> gettext("Unlisted account")
    end
  end

  defp reviewer_label(_), do: nil

  attr :exchange, :map, required: true
  attr :confirmation, :any, required: true
  attr :decision_pending, :boolean, required: true
  attr :decision_error, :any, required: true
  attr :decision_reason, :string, required: true
  attr :decision_confirmed, :boolean, required: true

  attr :locale, :string, required: true
  attr :reviewer_label, :any, required: true

  defp exchange_review(assigns) do
    ~H"""
    <section id="assistant-exchange" class="assistant-review-exchange paa">
      <h2 class="text-xl font-semibold">{gettext("Question and answer")}</h2>
      <p id="assistant-exchange-status" role="status">{review_status(@exchange)}</p>
      <h3 class="font-semibold">{gettext("Question")}</h3>
      <div id="assistant-review-question" class="paa-message" data-role="user">
        <p>{@exchange.question}</p>
      </div>
      <h3 :if={@exchange.answer} class="font-semibold">
        {if @exchange.status in [:approved, :released],
          do: gettext("Answer"),
          else: gettext("Held answer")}
      </h3>
      <div
        :if={@exchange.answer}
        id="assistant-review-answer"
        class="paa-message paa-markdown"
        data-role="assistant"
      >
        {PhoenixAgentAssistant.ResponseMarkdown.render(@exchange.answer)}
      </div>
      <p :if={is_nil(@exchange.answer) and @exchange.phase != :input}>
        {gettext("No generated answer was retained for this request.")}
      </p>
      <details class="assistant-review-scores">
        <summary>{gettext("Automated review results")}</summary>
        <div :for={
          {label, event} <- [
            {gettext("Input"), @exchange.input_review},
            {gettext("Output"), @exchange.output_review}
          ]
        }>
          <h3 class="font-semibold">{label}</h3>
          <dl :if={event && event["decision"]}>
            <div>
              <dt>{gettext("Review action")}</dt><dd>
                {action(get_in(event, ["decision", "action"]))}
              </dd>
            </div>
            <div>
              <dt>{gettext("Review policy")}</dt><dd>
                {policy(get_in(event, ["decision", "policy"]))}
              </dd>
            </div>
            <div>
              <dt>{gettext("Low-risk yes probability")}</dt><dd>
                {probability(get_in(event, ["decision", "jev", "probabilities", "low"]))}
              </dd>
            </div>
            <div>
              <dt>{gettext("Malicious yes probability")}</dt><dd>
                {probability(get_in(event, ["decision", "jev", "probabilities", "block"]))}
              </dd>
            </div>
            <div>
              <dt>{gettext("Moderation flagged")}</dt><dd>
                {flagged(get_in(event, ["decision", "moderation", "flagged"]))}
              </dd>
            </div>
          </dl>
        </div>
        <p :if={@exchange.model}>{gettext("Generation model")}: {@exchange.model}</p>
      </details>
      <p :if={@exchange.decision} id="assistant-human-review-receipt">
        {gettext("Reviewed by %{account}", account: @reviewer_label || gettext("Unlisted account"))}
        <time
          :if={@exchange.decision["decided_at"]}
          id="assistant-human-review-time"
          datetime={@exchange.decision["decided_at"]}
          data-locale={@locale}
          phx-hook="PhoenixAgentAssistantTime"
        >{@exchange.decision["decided_at"]}</time>. {gettext(
          "A human review decision is recorded for this exact exchange."
        )}
        <span :if={@exchange.decision["reason"] != ""}>{@exchange.decision["reason"]}</span>
      </p>
      <div
        :if={
          @exchange.status in [:held, :input_approved] and @exchange.approvable and
            is_nil(@confirmation)
        }
        class="assistant-review-actions"
      >
        <button
          id="assistant-review-approve"
          type="button"
          phx-click="prepare-decision"
          phx-value-decision={if @exchange.status == :input_approved, do: "resume", else: "approve"}
          class="assistant-review-approve"
        ><.icon name="hero-check" /> {if @exchange.phase == :input,
          do: gettext("Approve request and generate answer"),
          else: gettext("Approve answer")}</button>
        <button
          :if={@exchange.status == :held}
          id="assistant-review-reject"
          type="button"
          phx-click="prepare-decision"
          phx-value-decision="reject"
          class="assistant-review-reject"
        ><.icon name="hero-x-mark" /> {if @exchange.phase == :input,
          do: gettext("Reject request"),
          else: gettext("Reject answer")}</button>
      </div>
      <.link
        :if={@exchange.continuation_exists}
        navigate={activity_path(@exchange.resume_ref, %{"locale" => @locale})}
        id="assistant-review-continuation"
      >{gettext("View continued request")}</.link>
      <p :if={@exchange.status == :held and not @exchange.approvable}>
        {gettext(
          "This request has no completed output review that is eligible for an answer approval. Its recorded reason is in the activity below."
        )}
      </p>
      <form
        :if={@confirmation}
        id="assistant-review-confirmation"
        phx-submit="confirm-decision"
        phx-change="change-decision"
        class="assistant-review-confirmation"
      >
        <fieldset disabled={@decision_pending}>
          <legend class="text-lg font-semibold">
            {cond do
              @exchange.phase == :input and @confirmation.decision != :reject ->
                gettext("Approve this request and generate an answer?")

              @exchange.phase == :input ->
                gettext("Reject this request?")

              @confirmation.decision == :approve ->
                gettext("Release this answer?")

              true ->
                gettext("Keep this answer withheld?")
            end}
          </legend>
          <p>
            {cond do
              @exchange.phase == :input and @confirmation.decision != :reject ->
                gettext(
                  "The saved question and conversation history will be sent for generation with current application guidance and the original model. Current permissions and credits are checked. Generation uses the requester's credits and the answer still passes output review."
                )

              @exchange.phase == :input ->
                gettext("The request will stay withheld. No answer will be generated.")

              @confirmation.decision == :approve ->
                gettext("The displayed answer will be added to its conversation history.")

              true ->
                gettext("The answer will remain withheld and the rejection will be recorded.")
            end}
          </p>
          <p>
            {gettext("Confirmation valid until")}
            <time
              id="assistant-review-expiry"
              datetime={DateTime.to_iso8601(@confirmation.expires_at)}
              data-locale={@locale}
              phx-hook="PhoenixAgentAssistantTime"
            >{Calendar.strftime(@confirmation.expires_at, "%Y-%m-%d %H:%M:%S UTC")}</time>
          </p>
          <input type="hidden" name="review[token]" value={@confirmation.token} />
          <label for="assistant-review-confirmed"><input
            type="checkbox"
            id="assistant-review-confirmed"
            aria-invalid={not is_nil(@decision_error) and not @decision_confirmed}
            aria-describedby={if @decision_error, do: "assistant-review-decision-error"}
            name="review[confirmed]"
            value="true"
            checked={@decision_confirmed}
            phx-mounted={Phoenix.LiveView.JS.focus()}
          /> {if @exchange.phase == :input,
            do: gettext("I reviewed the displayed question and input review results."),
            else: gettext("I reviewed the displayed question, answer and review results.")}</label>
          <label for="assistant-review-reason">{gettext("Reason (optional)")}</label>
          <textarea
            id="assistant-review-reason"
            name="review[reason]"
            rows="2"
            maxlength="500"
            aria-describedby={if @decision_error, do: "assistant-review-decision-error"}
          >{@decision_reason}</textarea>
          <p :if={@decision_error} id="assistant-review-decision-error" role="alert">
            {@decision_error}
          </p>
          <p :if={@decision_pending} role="status">
            {if @exchange.phase == :input,
              do: gettext("Recording approval and generating the answer…"),
              else: gettext("Recording the decision…")}
          </p>
          <div class="assistant-review-actions">
            <button id="assistant-review-confirm" type="submit" class="assistant-review-approve">{if @confirmation.decision in [
                                                                                                       :approve,
                                                                                                       :resume
                                                                                                     ],
                                                                                                     do:
                                                                                                       gettext(
                                                                                                         "Confirm approval"
                                                                                                       ),
                                                                                                     else:
                                                                                                       gettext(
                                                                                                         "Confirm rejection"
                                                                                                       )}</button>
            <button type="button" phx-click="cancel-decision" class="assistant-review-reject">{gettext(
              "Cancel"
            )}</button>
          </div>
        </fieldset>
      </form>
      <p :if={not is_nil(@decision_error) and is_nil(@confirmation)} role="alert">
        {@decision_error}
      </p>
    </section>
    """
  end

  defp review_status(%{input_review: %{"error" => %{"stage" => "jev", "code" => code}}}) do
    gettext(
      "%{cause} The Assistant stopped before answering. There is no decision to approve. If this repeats, give the site operator the request reference.",
      cause: jev_problem(code)
    )
  end

  defp review_status(%{output_review: %{"error" => %{"stage" => "jev", "code" => code}}}) do
    gettext(
      "%{cause} The Assistant had generated an answer, but the check failed before it could be shown. If this repeats, give the site operator the request reference.",
      cause: jev_problem(code)
    )
  end

  defp review_status(%{input_review: %{"error" => _}}) do
    gettext(
      "A required check of the question failed. The Assistant stopped before answering. There is no decision to approve. If this continues, give the site operator the request reference."
    )
  end

  defp review_status(%{status: :held, phase: :input}),
    do: gettext("Input held for superadmin review. Approve the request to generate an answer.")

  defp review_status(%{status: :input_approved}),
    do: gettext("Input approved. Continue generation of the retained request.")

  defp review_status(%{status: :rejected, phase: :input}),
    do: gettext("Request rejected. No answer will be generated.")

  defp review_status(%{status: :held, answer: nil}),
    do: gettext("This request stopped before an answer was retained.")

  defp review_status(%{status: status}), do: review_status(status)

  defp review_status(:running),
    do: gettext("Generation has started. Its final result has not been recorded yet.")

  defp review_status(:held), do: gettext("Answer held for human review.")

  defp review_status(:approved),
    do: gettext("Approved · The answer is available in its conversation history.")

  defp review_status(:rejected), do: gettext("Rejected · The answer remains withheld.")
  defp review_status(:released), do: gettext("The answer was released automatically.")
  defp review_status(_), do: gettext("This exchange cannot be reviewed securely.")

  defp jev_problem(code) when code in ["checker_timeout", "transport_timeout"],
    do: gettext("JEV did not respond in time.")

  defp jev_problem("transport_closed"),
    do: gettext("The connection to JEV closed before the check finished.")

  defp jev_problem("transport_dns_failed"),
    do: gettext("The site could not find the network address for JEV.")

  defp jev_problem("transport_tls_failed"),
    do: gettext("The site could not establish a secure connection to JEV.")

  defp jev_problem("transport_refused"), do: gettext("The connection to JEV was refused.")

  defp jev_problem("checker_unauthorized"),
    do:
      gettext(
        "JEV rejected the site's credentials. Ask the operator to verify the site's access to JEV."
      )

  defp jev_problem("rate_limited"),
    do: gettext("JEV received too many requests and asked the site to slow down.")

  defp jev_problem("transport_failed"),
    do: gettext("The Assistant could not communicate with its second safety checker (JEV).")

  defp jev_problem(_), do: gettext("The site did not get a usable safety decision from JEV.")

  defp decision_error(:confirmation_expired),
    do: gettext("This confirmation expired. Cancel and review the answer again.")

  defp decision_error(:review_changed),
    do:
      gettext(
        "This answer already has a decision or changed since you reviewed it. Reload the request to see its current status."
      )

  defp decision_error(:forbidden),
    do: gettext("Review permission changed. Reload this request to see its current status.")

  defp decision_error(:invalid_decision),
    do: gettext("The reason must be at most 500 characters.")

  defp decision_error(_),
    do:
      gettext(
        "The decision could not be completed securely. Your review inputs are retained. Try again or reload this request."
      )

  defp activity_path(nil, query), do: ~p"/admin/assistant/activity?#{query}"

  defp activity_path(reference, query),
    do: ~p"/admin/assistant/activity/requests/#{reference}?#{query}"

  defp request_path(nil, _locale), do: nil
  defp request_path(reference, locale), do: activity_path(reference, %{locale: locale})

  defp review_details(row) do
    base = if row.request_ref, do: [{gettext("Request reference"), row.request_ref}], else: []

    base =
      if row.hold_reason,
        do: base ++ [{gettext("Why it was held"), hold_reason(row.hold_reason)}],
        else: base

    if row.review do
      review = row.review

      base ++
        Enum.reject(
          [
            {gettext("Review direction"), direction(review.direction)},
            {gettext("Review action"), action(review.action)},
            {gettext("Review policy"), policy(review.policy)},
            {gettext("Low-risk yes probability"), probability(review.low)},
            {gettext("Malicious yes probability"), probability(review.malicious)},
            {gettext("Moderation flagged"), flagged(review.moderation_flagged)}
          ],
          fn {_, value} -> is_nil(value) end
        )
    else
      base
    end
  end

  defp direction("input"), do: gettext("Input")
  defp direction("output"), do: gettext("Output")
  defp direction(_), do: nil
  defp action("allow"), do: gettext("Allowed")
  defp action("review"), do: gettext("Held for review")
  defp action("block"), do: gettext("Blocked")
  defp action(_), do: nil
  defp policy("strict_v1"), do: gettext("Strict policy")
  defp policy("text_coaching_v1"), do: gettext("Text coaching policy")
  defp policy(_), do: nil
  defp probability(nil), do: nil
  defp probability(value), do: :erlang.float_to_binary(value / 1, decimals: 2)
  defp flagged(true), do: gettext("Yes")
  defp flagged(false), do: gettext("No")
  defp flagged(_), do: nil

  defp hold_reason("token_limit_unavailable"),
    do:
      gettext("The request could not fit the assistant’s configured per-request token allowance.")

  defp hold_reason("request_too_large"),
    do: gettext("The request exceeded the assistant’s per-request limit.")

  defp hold_reason("output_safety_review_required"),
    do: gettext("Answer withheld: output review needs attention.")

  defp hold_reason("output_safety_blocked"),
    do: gettext("Answer withheld: output safety checks blocked it.")

  defp hold_reason("output_safety_unavailable"),
    do: gettext("Answer withheld: output safety checks were unavailable.")

  defp hold_reason("safety_review_required"), do: gettext("Input review needs attention.")
  defp hold_reason("safety_blocked"), do: gettext("Input safety checks blocked the request.")

  defp hold_reason(reason) when reason in ["safety_unavailable", "input_safety_unavailable"],
    do:
      gettext(
        "A required check failed before the Assistant could answer. Open this request for details."
      )

  defp hold_reason(_), do: gettext("The request could not continue safely.")

  defp activity("human_review_requested"), do: gettext("Human review requested")
  defp activity("human_review_decided"), do: gettext("Human review decision")
  defp activity("request"), do: gettext("Request recorded")
  defp activity("request_reserved"), do: gettext("Budget reserved")
  defp activity("provider_output"), do: gettext("Response recorded")
  defp activity("provider_failure"), do: outcome("failed")
  defp activity("response_released"), do: gettext("Response released")
  defp activity("safety_review"), do: gettext("Safety review")
  defp activity("request_held"), do: gettext("Request held")
  defp activity("request_finished"), do: gettext("Request finished")
  defp activity("alert_queued"), do: gettext("Operator alert queued")
  defp activity("alert_outcome"), do: gettext("Alert intake outcome")
  defp activity("enabled_changed"), do: gettext("Assistant setting changed")
  defp activity("mode_changed"), do: gettext("Mode changed")
  defp activity("token_limit_changed"), do: gettext("Token limit changed")
  defp activity("conversation_started"), do: gettext("Conversation started")
  defp activity("spend_observation"), do: gettext("Provider usage recorded")
  defp activity("audit_viewed"), do: gettext("Audit accessed")
  defp activity(_), do: gettext("Recorded activity")
  defp outcome("approved"), do: gettext("Approved")
  defp outcome("rejected"), do: gettext("Rejected")
  defp outcome("released"), do: gettext("Released")
  defp outcome("held"), do: gettext("Held")
  defp outcome("reserved"), do: gettext("Reserved")
  defp outcome("succeeded"), do: gettext("Succeeded")
  defp outcome("failed"), do: gettext("Failed")
  defp outcome("unknown"), do: gettext("Unknown")
  defp outcome("accepted"), do: gettext("Accepted")
  defp outcome("pending"), do: gettext("Pending")
  defp outcome("submitting"), do: gettext("Submitting")
  defp outcome(_), do: gettext("Recorded")

  defp event_outcome(%{hold_reason: reason})
       when reason in ["safety_unavailable", "input_safety_unavailable"],
       do: gettext("Check failed before answer")

  defp event_outcome(%{kind: "provider_failure", outcome: details}), do: details
  defp event_outcome(row), do: outcome(row.outcome)
end
