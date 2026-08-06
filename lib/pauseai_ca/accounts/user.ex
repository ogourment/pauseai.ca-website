defmodule PauseAiCa.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true
    field :superadmin, :boolean, default: false
    field :fsa, :string
    field :local_updates, :boolean, default: false
    field :saved_resources, {:array, :string}, default: []
    field :belief_answers, :map, default: %{}
    field :postal_code, :string
    field :city, :string
    field :representative, :map
    field :custom_resource_urls, {:array, :string}, default: []

    timestamps(type: :utc_datetime)
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  def registration_changeset(user, attrs) do
    user
    |> email_changeset(attrs)
    |> cast(attrs, [:postal_code, :city])
    |> update_change(:postal_code, &normalize_postal_code/1)
    |> update_change(:city, &String.trim/1)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, PauseAiCa.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Argon2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  def local_context_changeset(user, attrs) do
    user
    |> cast(attrs, [:fsa, :local_updates])
    |> update_change(:fsa, fn value ->
      value |> String.upcase() |> String.replace(~r/\s+/, "") |> String.slice(0, 3)
    end)
    |> validate_required([:fsa])
    |> validate_format(:fsa, ~r/^[ABCEGHJKLMNPRSTVXY]\d[ABCEGHJKLMNPRSTVWXYZ]$/,
      message: "must be the first three characters of a Canadian postal code"
    )
  end

  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:postal_code, :city, :local_updates])
    |> update_change(:postal_code, fn value ->
      value |> String.upcase() |> String.replace(~r/[^A-Z0-9]/, "")
    end)
    |> update_change(:city, &String.trim/1)
    |> validate_required([:postal_code])
    |> validate_format(:postal_code, ~r/^[ABCEGHJ-NPRSTVXY]\d[A-Z]\d[A-Z]\d$/,
      message: "must be a complete Canadian postal code"
    )
    |> then(fn changeset ->
      case get_field(changeset, :postal_code) do
        value when is_binary(value) and byte_size(value) >= 3 ->
          put_change(changeset, :fsa, String.slice(value, 0, 3))

        _ ->
          changeset
      end
    end)
  end

  defp normalize_postal_code(value) do
    value |> String.upcase() |> String.replace(~r/[^A-Z0-9]/, "")
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Argon2.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%PauseAiCa.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Argon2.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Argon2.no_user_verify()
    false
  end
end
