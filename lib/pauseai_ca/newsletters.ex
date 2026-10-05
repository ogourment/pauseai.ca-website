defmodule PauseAiCa.Newsletters do
  @moduledoc """
  Consumer-owned newsletter consent ledger. These operations never send mail,
  mutate Brevo, create accounts or infer consent from historical membership.
  Public signup and delivery adapters must separately enforce their limits.
  """
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Newsletters.{Subscription, ConsentEvent, WithdrawalToken}
  @consent_version "newsletter-2026-10-04"
  @confirmation_seconds 86_400

  @doc "Persists explicit newsletter opt-in. Tokens are returned only to the delivery adapter, never logged/stored in cleartext."
  def request_signup(email, attrs) do
    with {:ok, email} <- normalize(email), true <- attrs[:consent] == true do
      Repo.transaction(fn ->
        lock_address(email)
        current = Repo.one(from s in Subscription, where: s.email == ^email, lock: "FOR UPDATE")

        if current && current.state == "confirmed" do
          %{subscription: current, confirmation_token: nil, withdrawal_token: nil}
        else
          now = DateTime.utc_now()
          confirmation = token()
          withdrawal = token()

          values = %{
            email: email,
            state: "pending",
            locale: if(attrs[:locale] == "fr", do: "fr", else: "en"),
            city: text(attrs[:city]),
            region: text(attrs[:region]),
            consent_version: @consent_version,
            requested_at: now,
            confirmed_at: nil,
            confirmation_hash: digest(confirmation),
            confirmation_expires_at: DateTime.add(now, @confirmation_seconds)
          }

          saved = persist(current, values)

          Repo.insert!(%WithdrawalToken{
            subscription_id: saved.id,
            token_hash: digest(withdrawal),
            inserted_at: now
          })

          event(saved, "requested", nil, %{"explicit_opt_in" => true})
          %{subscription: saved, confirmation_token: confirmation, withdrawal_token: withdrawal}
        end
      end)
    else
      false -> {:error, :consent_required}
      error -> error
    end
  end

  @doc "Read-only capability inspection. Opening a mail link never confirms or withdraws consent."
  def capability(token, action) when action in [:confirm, :withdraw] do
    if is_binary(token) and byte_size(token) in 20..200 do
      hash = digest(token)

      query =
        case action do
          :confirm ->
            now = DateTime.utc_now()

            from s in Subscription,
              where:
                s.confirmation_hash == ^hash and s.state == "pending" and
                  s.confirmation_expires_at > ^now

          :withdraw ->
            from s in Subscription,
              join: t in WithdrawalToken,
              on: t.subscription_id == s.id,
              where: t.token_hash == ^hash
        end

      case Repo.one(query) do
        nil -> {:error, :invalid_token}
        subscription -> {:ok, %{locale: subscription.locale}}
      end
    else
      {:error, :invalid_token}
    end
  end

  def confirm(token) do
    token_transaction(token, :confirmation_hash, fn subscription ->
      if subscription.state != "pending" or
           DateTime.compare(subscription.confirmation_expires_at, DateTime.utc_now()) != :gt,
         do: Repo.rollback(:invalid_token)

      saved =
        persist(subscription, %{
          state: "confirmed",
          confirmed_at: DateTime.utc_now(),
          withdrawn_at: nil,
          confirmation_hash: nil,
          confirmation_expires_at: nil
        })

      event(saved, "confirmed", nil, %{})
      saved
    end)
  end

  @doc "Capability-based withdrawal; invalidates outstanding confirmation and takes effect locally even without Brevo."
  def withdraw(token) do
    withdrawal_transaction(token, fn subscription ->
      if subscription.state == "withdrawn" do
        subscription
      else
        saved =
          persist(subscription, %{
            state: "withdrawn",
            withdrawn_at: DateTime.utc_now(),
            confirmation_hash: nil,
            confirmation_expires_at: nil
          })

        event(saved, "withdrawn", nil, %{})
        saved
      end
    end)
  end

  @doc "Records source evidence for review, never granting consent or overwriting a local decision. No provider calls."
  def observe_legacy(scope, email, evidence) when is_map(evidence) do
    with true <- Volunteers.superadmin?(scope), {:ok, email} <- normalize(email) do
      Repo.transaction(fn ->
        actor =
          Repo.one(
            from u in PauseAiCa.Accounts.User, where: u.id == ^scope.user.id, lock: "FOR UPDATE"
          )

        if is_nil(actor) or not Volunteers.superadmin?(scope), do: Repo.rollback(:unauthorized)
        lock_address(email)

        saved =
          Repo.get_by(Subscription, email: email) ||
            persist(nil, %{email: email, state: "legacy_review"})

        event(saved, "legacy_observed", actor.id, evidence)
        saved
      end)
    else
      false -> {:error, :unauthorized}
      error -> error
    end
  end

  def history(scope, id) do
    if Volunteers.superadmin?(scope) and match?({:ok, _}, Ecto.UUID.cast(id)) do
      {:ok,
       Repo.all(
         from e in ConsentEvent,
           where: e.subscription_id == ^id,
           order_by: [asc: e.inserted_at, asc: e.id]
       )}
    else
      {:error, :unauthorized}
    end
  end

  @doc "Fresh local eligibility; account confirmation or a preferred address cannot authorize newsletter contact."
  def eligible?(email) do
    with {:ok, email} <- normalize(email),
         %Subscription{state: "confirmed"} <- Repo.get_by(Subscription, email: email),
         false <- PauseAiCa.Mail.suppressed?(email),
         false <- provider_blocked?(email) do
      aliases = linked_addresses(email)

      not Repo.exists?(
        from s in Subscription, where: s.email in ^aliases and not is_nil(s.withdrawn_at)
      )
    else
      _ -> false
    end
  end

  def audience(scope) do
    if Volunteers.superadmin?(scope) do
      {:ok, Repo.all(from s in Subscription, order_by: [asc: s.email])}
    else
      {:error, :unauthorized}
    end
  end

  @doc "Records an attributed provider observation; never creates consent or writes to Brevo."
  def observe_provider(scope, email, evidence) when is_map(evidence) do
    with true <- Volunteers.superadmin?(scope),
         {:ok, email} <- normalize(email),
         id when is_integer(id) and id > 0 <- evidence["provider_id"],
         blocked when is_boolean(blocked) <- evidence["email_blacklisted"],
         timestamp when is_binary(timestamp) <- evidence["observed_at"],
         {:ok, observed_at, _} <- DateTime.from_iso8601(timestamp) do
      Repo.transaction(fn ->
        actor =
          Repo.one(
            from u in PauseAiCa.Accounts.User, where: u.id == ^scope.user.id, lock: "FOR UPDATE"
          )

        if is_nil(actor) or not Volunteers.superadmin?(scope), do: Repo.rollback(:unauthorized)
        lock_address(email)

        subscription =
          Repo.get_by(Subscription, email: email) ||
            persist(nil, %{email: email, state: "legacy_review"})

        # Only explicitly supported metadata is retained: no provider credentials or payload bodies.
        event(subscription, "provider_observed", actor.id, %{
          "provider" => "brevo",
          "provider_id" => id,
          "email_blacklisted" => blocked,
          "observed_at" => DateTime.to_iso8601(observed_at)
        })

        subscription
      end)
    else
      false -> {:error, :unauthorized}
      {:error, :invalid_email} = error -> error
      _ -> {:error, :invalid_observation}
    end
  end

  def observe_provider(_, _, _), do: {:error, :invalid_observation}

  @doc "Latest provider observation by observation time, rather than arrival order."
  def provider_blocked?(email) do
    with {:ok, email} <- normalize(email) do
      provider_observations([email])[email] == true
    else
      _ -> true
    end
  end

  @doc "Superadmin-only, shareable audience filters and explicit exclusion counts. No mutations."
  def audience_page(scope, params) when is_map(params) do
    if Volunteers.superadmin?(scope) do
      region = filter_text(params["region"])
      term = filter_text(params["q"]) |> String.downcase()
      per = positive_integer(params["per"], 25)
      per = if per in [10, 25, 50, 100], do: per, else: 25
      query = from s in Subscription, order_by: [asc: s.email, asc: s.id]
      query = if region == "", do: query, else: from(s in query, where: s.region == ^region)

      query =
        if term == "",
          do: query,
          else:
            from(s in query,
              where:
                fragment("strpos(lower(?), ?) > 0", s.email, ^term) or
                  fragment("strpos(lower(coalesce(?, '')), ?) > 0", s.city, ^term)
            )

      subscriptions = Repo.all(query)
      emails = Enum.map(subscriptions, & &1.email)
      observations = provider_evidence(emails)

      provider =
        Map.new(observations, fn {email, evidence} -> {email, evidence["email_blacklisted"]} end)

      suppressed =
        MapSet.union(PauseAiCa.Mail.suppressed_emails(emails), withdrawn_aliases(emails))

      rows =
        Enum.map(subscriptions, fn subscription ->
          status =
            cond do
              subscription.state == "withdrawn" -> :withdrawn
              subscription.state == "legacy_review" -> :legacy_uncertain
              subscription.state != "confirmed" -> :unconfirmed
              provider[subscription.email] == true -> :provider_blocked
              MapSet.member?(suppressed, subscription.email) -> :suppressed
              true -> :included
            end

          %{
            subscription: subscription,
            status: status,
            provider: observations[subscription.email]
          }
        end)

      total = length(rows)
      pages = max(1, div(total + per - 1, per))
      page = min(positive_integer(params["page"], 1), pages)

      counts =
        Map.merge(
          Map.new(
            ~w(included withdrawn legacy_uncertain unconfirmed provider_blocked suppressed)a,
            &{&1, 0}
          ),
          Enum.frequencies_by(rows, & &1.status)
        )

      # Recheck after hydration, so revoked actors do not receive private results.
      if Volunteers.superadmin?(scope),
        do:
          {:ok,
           %{
             rows: Enum.slice(rows, (page - 1) * per, per),
             total: total,
             page: page,
             pages: pages,
             per: per,
             counts: counts,
             filters: %{"q" => term, "region" => region}
           }},
        else: {:error, :unauthorized}
    else
      {:error, :unauthorized}
    end
  end

  defp withdrawn_aliases(emails) do
    direct =
      Repo.all(
        from s in Subscription,
          where: s.email in ^emails and not is_nil(s.withdrawn_at),
          select: s.email
      )

    linked =
      Repo.all(
        from a in PhoenixCRM.Address,
          join: p in PhoenixCRM.Person,
          on: p.id == a.person_id,
          join: other_person in PhoenixCRM.Person,
          on:
            coalesce(other_person.canonical_id, other_person.id) == coalesce(p.canonical_id, p.id),
          join: other_address in PhoenixCRM.Address,
          on: other_address.person_id == other_person.id,
          join: s in Subscription,
          on: s.email == other_address.email,
          where: a.email in ^emails and not is_nil(s.withdrawn_at),
          select: a.email,
          distinct: true
      )

    MapSet.new(direct ++ linked)
  end

  defp provider_observations(emails),
    do:
      Map.new(provider_evidence(emails), fn {email, evidence} ->
        {email, evidence["email_blacklisted"]}
      end)

  defp provider_evidence(emails) do
    Repo.all(
      from e in ConsentEvent,
        join: s in Subscription,
        on: s.id == e.subscription_id,
        where: s.email in ^emails and e.kind == "provider_observed",
        order_by: [
          desc: fragment("(?->>'observed_at')::timestamptz", e.evidence),
          desc: e.inserted_at,
          desc: e.id
        ],
        select: {s.email, e.evidence}
    )
    |> Enum.reduce(%{}, fn {email, evidence}, result ->
      Map.put_new(result, email, evidence)
    end)
  end

  defp positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> min(number, 1_000_000)
      _ -> default
    end
  end

  defp positive_integer(_, default), do: default
  defp filter_text(value) when is_binary(value), do: String.trim(value) |> String.slice(0, 200)
  defp filter_text(_), do: ""

  defp linked_addresses(email) do
    canonical =
      Repo.one(
        from a in PhoenixCRM.Address,
          join: p in PhoenixCRM.Person,
          on: p.id == a.person_id,
          where: a.email == ^email,
          select: coalesce(p.canonical_id, p.id)
      )

    if canonical do
      Repo.all(
        from a in PhoenixCRM.Address,
          join: p in PhoenixCRM.Person,
          on: p.id == a.person_id,
          where: p.id == ^canonical or p.canonical_id == ^canonical,
          select: a.email
      )
    else
      [email]
    end
  end

  defp withdrawal_transaction(token, fun) when is_binary(token) and byte_size(token) == 43 do
    hash = digest(token)

    Repo.transaction(fn ->
      subscription =
        Repo.one(
          from s in Subscription,
            join: t in WithdrawalToken,
            on: t.subscription_id == s.id,
            where: t.token_hash == ^hash,
            lock: "FOR UPDATE"
        )

      if is_nil(subscription), do: Repo.rollback(:invalid_token)
      fun.(subscription)
    end)
  end

  defp withdrawal_transaction(_, _), do: {:error, :invalid_token}

  defp token_transaction(token, field, fun) when is_binary(token) and byte_size(token) == 43 do
    hash = digest(token)

    Repo.transaction(fn ->
      subscription =
        Repo.one(from s in Subscription, where: field(s, ^field) == ^hash, lock: "FOR UPDATE")

      if is_nil(subscription), do: Repo.rollback(:invalid_token)
      fun.(subscription)
    end)
  end

  defp token_transaction(_, _, _), do: {:error, :invalid_token}

  defp persist(nil, values),
    do: %Subscription{} |> Ecto.Changeset.change(values) |> Repo.insert!()

  defp persist(current, values), do: current |> Ecto.Changeset.change(values) |> Repo.update!()

  defp event(subscription, kind, actor, evidence) do
    Repo.insert!(%ConsentEvent{
      subscription_id: subscription.id,
      kind: kind,
      actor_id: actor,
      consent_version: subscription.consent_version,
      evidence: evidence,
      inserted_at: DateTime.utc_now()
    })
  end

  defp lock_address(email),
    do:
      Ecto.Adapters.SQL.query!(Repo, "SELECT pg_advisory_xact_lock(hashtext($1))", [
        "newsletter:" <> email
      ])

  defp token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  defp digest(token), do: :crypto.hash(:sha256, token)
  defp text(value) when is_binary(value), do: String.trim(value) |> String.slice(0, 200)
  defp text(_), do: nil

  defp normalize(email) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()

    if byte_size(email) <= 254 and Regex.match?(~r/^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$/, email),
      do: {:ok, email},
      else: {:error, :invalid_email}
  end

  defp normalize(_), do: {:error, :invalid_email}
end
