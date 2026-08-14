defmodule PauseAiCa.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias PauseAiCa.Repo

  alias PauseAiCa.Accounts.{User, UserToken, UserNotifier}
  alias PauseAiCa.Campaigns.Subscription

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    changeset = User.email_changeset(%User{}, attrs)

    if changeset.valid? do
      attrs
      |> import_subscriber_location(Ecto.Changeset.get_field(changeset, :email))
      |> then(&User.registration_changeset(%User{}, &1))
      |> Repo.insert()
    else
      {:error, changeset}
    end
  end

  defp import_subscriber_location(attrs, email) do
    case Subscription.location_for(email) do
      {:ok, location} ->
        imported = Map.new(location, fn {key, value} -> {Atom.to_string(key), value} end)
        Map.merge(imported, attrs)

      {:error, _reason} ->
        attrs
    end
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `PauseAiCa.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `PauseAiCa.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens(bootstrap_superadmin?: true)
  end

  def list_users(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 25)

    Repo.all(
      from u in User,
        order_by: [asc: u.email],
        limit: ^per_page,
        offset: ^((page - 1) * per_page)
    )
  end

  def count_users, do: Repo.aggregate(User, :count)

  def set_superadmin(%User{superadmin: true}, %User{} = target, false) do
    if Repo.aggregate(from(u in User, where: u.superadmin), :count) == 1 and target.superadmin do
      {:error, :last_superadmin}
    else
      target |> Ecto.Changeset.change(superadmin: false) |> Repo.update()
    end
  end

  def set_superadmin(%User{superadmin: true}, %User{confirmed_at: nil}, true),
    do: {:error, :email_unconfirmed}

  def set_superadmin(%User{superadmin: true}, %User{} = target, value) when is_boolean(value) do
    target |> Ecto.Changeset.change(superadmin: value) |> Repo.update()
  end

  def set_superadmin(%User{}, %User{}, _value), do: {:error, :unauthorized}

  def change_user_local_context(%User{} = user, attrs \\ %{}) do
    User.local_context_changeset(user, attrs)
  end

  def update_user_local_context(%User{} = user, attrs) do
    user |> User.local_context_changeset(attrs) |> Repo.update()
  end

  @legacy_saved_resources ~w(risk pause coordination agency)

  def save_resource(%User{} = user, resource) do
    if resource in @legacy_saved_resources or PauseAiCa.Library.resource(resource) do
      saved_resources = Enum.uniq(user.saved_resources ++ [resource])
      user |> Ecto.Changeset.change(saved_resources: saved_resources) |> Repo.update()
    else
      {:error, :unknown_resource}
    end
  end

  def save_belief_answers(%User{} = user, answers) when is_map(answers) do
    allowed = answers |> Map.take(~w(risk pause coordination)) |> Enum.into(%{})
    user |> Ecto.Changeset.change(belief_answers: allowed) |> Repo.update()
  end

  def change_user_profile(%User{} = user, attrs \\ %{}), do: User.profile_changeset(user, attrs)

  def update_user_profile(%User{} = user, attrs, representative) when is_map(representative) do
    user
    |> User.profile_changeset(attrs)
    |> Ecto.Changeset.put_change(:representative, representative)
    |> Repo.update()
  end

  def remove_saved_resource(%User{} = user, resource) do
    user
    |> Ecto.Changeset.change(saved_resources: List.delete(user.saved_resources, resource))
    |> Repo.update()
  end

  def add_custom_resource(%User{} = user, url) when is_binary(url) do
    with %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) <-
           URI.parse(url) do
      urls = Enum.uniq(user.custom_resource_urls ++ [url])
      user |> Ecto.Changeset.change(custom_resource_urls: urls) |> Repo.update()
    else
      _ -> {:error, :invalid_url}
    end
  end

  def remove_custom_resource(%User{} = user, url) do
    user
    |> Ecto.Changeset.change(custom_resource_urls: List.delete(user.custom_resource_urls, url))
    |> Repo.update()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset, opts \\ []) do
    Repo.transact(fn ->
      if opts[:bootstrap_superadmin?] == true do
        # Serialize only the one-time bootstrap decision. A table lock can
        # deadlock unrelated password updates that already hold row locks.
        Repo.query!("SELECT pg_advisory_xact_lock(706175001)")
      end

      with {:ok, user} <- Repo.update(changeset) do
        user =
          if opts[:bootstrap_superadmin?] == true and not is_nil(user.confirmed_at) and
               not Repo.exists?(from(u in User, where: u.superadmin)) do
            user |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
          else
            user
          end

        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
