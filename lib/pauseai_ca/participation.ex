defmodule PauseAiCa.Participation do
  @moduledoc "One explicit signup request, separate purpose choices and one email-ownership confirmation. Local requests are not group membership."
  import Ecto.Query
  alias PauseAiCa.{Repo, Newsletters}
  alias PauseAiCa.Accounts.Onboarding
  alias PauseAiCa.Participation.{Request, Notifier}
  def change(attrs), do: Request.changeset(%Request{}, attrs)

  def request(attrs, context, url_fun) do
    changeset = change(attrs)

    if changeset.valid? do
      email = Ecto.Changeset.get_field(changeset, :email)
      confirmation = token()
      withdrawal = token()

      result =
        Repo.transaction(fn ->
          lock(email)
          now = DateTime.utc_now()

          recent =
            Repo.one(
              from r in Request,
                where: r.email == ^email,
                order_by: [desc: r.inserted_at],
                limit: 1
            )

          if recent && DateTime.diff(now, recent.inserted_at) < 60 do
            if recent.delivery_state == "failed", do: Repo.rollback(:confirmation_unavailable)
            values = Ecto.Changeset.apply_changes(changeset)
            fields = ~w(name fsa city help_text newsletter account local_kind locale)a

            if Map.take(recent, fields) == Map.take(values, fields),
              do: Repo.rollback(:cooldown),
              else: Repo.rollback(:changed_choices_cooldown)
          end

          Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
            "participation-confirmation-quota"
          ])

          hour = DateTime.add(now, -3600)

          if Repo.aggregate(from(r in Request, where: r.inserted_at > ^hour), :count) >= 100,
            do: Repo.rollback(:confirmation_unavailable)

          Repo.update_all(from(r in Request, where: r.email == ^email and r.state == "pending"),
            set: [state: "superseded", confirmation_hash: nil]
          )

          changeset
          |> Ecto.Changeset.change(
            confirmation_hash: digest(confirmation),
            withdrawal_hash: digest(withdrawal),
            expires_at: DateTime.add(now, 86400),
            context: context
          )
          |> Repo.insert!()
        end)

      case result do
        {:ok, request} -> deliver(request, confirmation, withdrawal, url_fun)
        {:error, :cooldown} -> {:ok, :pending}
        error -> error
      end
    else
      {:error, changeset}
    end
  end

  defp deliver(%{account: true} = request, _confirmation, withdrawal, url_fun) do
    context = Map.put(request.context, "participation_id", request.id)

    builder = fn user, url ->
      Notifier.build(request, url, url_fun.(:withdraw, withdrawal), user.email)
    end

    result =
      Onboarding.request(
        request.email,
        context,
        fn token, flow -> url_fun.(:account, {token, flow}) end,
        email_builder: if(request.newsletter || request.local_kind, do: builder)
      )

    case result do
      {:ok, user, _created, _flow} -> delivered(request, user.id, :accepted)
      {:error, :delivery, user, _created, _flow} -> delivered(request, user.id, :failed)
      _ -> delivered(request, nil, :failed)
    end
  end

  defp deliver(request, confirmation, withdrawal, url_fun) do
    email =
      Notifier.build(
        request,
        url_fun.(:confirm, confirmation),
        url_fun.(:withdraw, withdrawal),
        request.email
      )

    case PauseAiCa.Mailer.deliver(email) do
      {:ok, _} -> delivered(request, nil, :accepted)
      _ -> delivered(request, nil, :failed)
    end
  end

  defp delivered(request, user_id, state) do
    request
    |> Ecto.Changeset.change(delivery_state: to_string(state), user_id: user_id)
    |> Repo.update!()

    if state == :accepted, do: {:ok, :pending}, else: {:error, :confirmation_unavailable}
  end

  def capability(token, kind) when kind in [:confirm, :withdraw] do
    hash = digest(token)
    field = if kind == :confirm, do: :confirmation_hash, else: :withdrawal_hash
    request = Repo.one(from r in Request, where: field(r, ^field) == ^hash)

    cond do
      is_nil(request) ->
        {:error, :invalid_token}

      kind == :confirm &&
          (request.account || request.state != "pending" ||
             DateTime.compare(request.expires_at, DateTime.utc_now()) != :gt) ->
        {:error, :invalid_token}

      true ->
        {:ok, request}
    end
  end

  def confirm(token) do
    Repo.transaction(fn ->
      case capability(token, :confirm) do
        {:ok, request} -> apply_choices(request, nil)
        _ -> Repo.rollback(:invalid_token)
      end
    end)
  end

  def confirm_for_user(user, id) do
    Repo.transaction(fn ->
      request = Repo.get(Request, id)

      cond do
        !request || !request.account || request.user_id != user.id ||
            request.email != String.downcase(user.email) ->
          Repo.rollback(:invalid_request)

        request.state == "confirmed" ->
          request

        request.state != "pending" ||
            DateTime.compare(request.expires_at, DateTime.utc_now()) != :gt ->
          Repo.rollback(:invalid_request)

        true ->
          apply_choices(request, user)
      end
    end)
  end

  defp apply_choices(request, user) do
    lock(request.email)
    request = Repo.one!(from r in Request, where: r.id == ^request.id, lock: "FOR UPDATE")
    if request.state != "pending", do: Repo.rollback(:invalid_request)

    if request.newsletter do
      case Newsletters.request_signup(request.email, %{
             consent: true,
             locale: request.locale,
             name: request.name,
             fsa: request.fsa
           }) do
        {:ok, %{subscription: subscription, confirmation_token: nil}} ->
          profile =
            %{name: request.name, fsa: request.fsa, locale: request.locale}
            |> Map.reject(fn {_k, v} -> v in [nil, ""] end)

          subscription |> Ecto.Changeset.change(profile) |> Repo.update!()

          Repo.insert!(%Newsletters.ConsentEvent{
            subscription_id: subscription.id,
            kind: "profile_updated",
            actor_id: request.user_id,
            consent_version: subscription.consent_version,
            evidence: %{"participation_request_id" => request.id},
            inserted_at: DateTime.utc_now()
          })

        {:ok, %{confirmation_token: token}} ->
          case Newsletters.confirm(token) do
            {:ok, _} -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end

    if request.local_kind do
      Repo.update_all(
        from(r in Request,
          where:
            r.email == ^request.email and r.id != ^request.id and r.state == "confirmed" and
              not is_nil(r.local_kind) and
              fragment("lower(coalesce(nullif(btrim(?), ''), ?))", r.city, r.fsa) ==
                ^String.downcase(request.city || request.fsa || "")
        ),
        set: [state: "superseded_local"]
      )
    end

    if user do
      profile =
        %{name: request.name, city: nil, fsa: request.fsa}
        |> Map.reject(fn {_k, v} -> v in [nil, ""] end)

      user |> Ecto.Changeset.change(profile) |> Repo.update!()
    end

    request
    |> Ecto.Changeset.change(
      state: "confirmed",
      confirmed_at: DateTime.utc_now(),
      confirmation_hash: nil
    )
    |> Repo.update!()
  end

  def withdraw(token) do
    Repo.transaction(fn ->
      case capability(token, :withdraw) do
        {:ok, request} ->
          lock(request.email)

          changes = [
            local_kind: nil,
            help_text: nil,
            city: nil,
            followup_owner_id: nil,
            withdrawn_at: DateTime.utc_now()
          ]

          changes =
            if !request.account && !request.newsletter,
              do:
                changes ++
                  [
                    state: "withdrawn",
                    confirmation_hash: nil,
                    email: "withdrawn:" <> request.id,
                    name: nil,
                    fsa: nil,
                    context: %{}
                  ],
              else: changes

          request |> Ecto.Changeset.change(changes) |> Repo.update!()

        _ ->
          Repo.rollback(:invalid_token)
      end
    end)
  end

  def local_requests(scope, requested_page \\ 1) do
    if PauseAiCa.Volunteers.superadmin?(scope) do
      query =
        from r in Request,
          where: r.state == "confirmed" and not is_nil(r.local_kind) and is_nil(r.withdrawn_at)

      total = Repo.aggregate(query, :count)
      pages = max(1, Integer.ceil_div(total, 25))

      parsed =
        case Integer.parse(to_string(requested_page)) do
          {value, ""} -> value
          _ -> 1
        end

      page = min(max(parsed, 1), pages)

      entries =
        Repo.all(
          from r in query,
            order_by: [desc: r.confirmed_at, desc: r.id],
            limit: 25,
            offset: ^((page - 1) * 25)
        )

      {:ok, %{entries: entries, page: page, pages: pages, total: total}}
    else
      {:error, :unauthorized}
    end
  end

  def claim(scope, id) do
    with true <- PauseAiCa.Volunteers.superadmin?(scope),
         {:ok, id} <- Ecto.UUID.cast(id),
         %Request{state: "confirmed", withdrawn_at: nil, local_kind: kind} = request
         when not is_nil(kind) <- Repo.get(Request, id) do
      request |> Ecto.Changeset.change(followup_owner_id: scope.user.id) |> Repo.update()
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  defp digest(token) when is_binary(token) and byte_size(token) in 20..200,
    do: :crypto.hash(:sha256, token)

  defp digest(_), do: <<>>

  defp lock(email),
    do:
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        "participation:" <> email
      ])
end
