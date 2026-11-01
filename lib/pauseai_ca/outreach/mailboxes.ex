defmodule PauseAiCa.Outreach.Mailboxes do
  @moduledoc "Consumer-owned, explicitly enabled and verified outreach sender configuration."
  alias PauseAiCa.{Volunteers, Repo, Accounts}

  def all(scope) do
    if Volunteers.superadmin?(scope), do: {:ok, configured()}, else: {:error, :unauthorized}
  end

  def fetch(scope, ref) do
    with {:ok, mailboxes} <- all(scope),
         mailbox when not is_nil(mailbox) <- Enum.find(mailboxes, &(&1.id == ref)) do
      {:ok, mailbox}
    else
      nil -> {:error, :mailbox_unavailable}
      error -> error
    end
  end

  def sending(scope, ref) do
    with {:ok, mailbox} <- fetch(scope, ref),
         true <- mailbox.enabled? and mailbox.verified? do
      {:ok, mailbox}
    else
      false -> {:error, :mailbox_unavailable}
      error -> error
    end
  end

  def configured do
    Application.get_env(:pauseai_ca, :outreach_mailboxes, [])
    |> Enum.map(fn entry ->
      entry = Map.new(entry)

      %{
        id: value(entry, :id),
        name: value(entry, :name),
        email: value(entry, :email),
        locale: value(entry, :locale),
        owner_id: owner_id(entry),
        receiving_addresses: value(entry, :receiving_addresses) || [],
        enabled?: value(entry, :enabled?) == true,
        verified?: value(entry, :verified?) == true
      }
    end)
    |> Enum.filter(fn box ->
      box.id in ["outreach_en", "outreach_fr"] and box.locale in ["en", "fr"] and
        valid_email?(box.email) and is_binary(box.name) and
        not String.contains?(box.name, ["\r", "\n"])
    end)
  end

  def authorized_actor(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Accounts.User{} = user <- Repo.get(Accounts.User, uuid),
         true <- Volunteers.superadmin?(Accounts.Scope.for_user(user)) do
      user
    else
      _ -> nil
    end
  end

  defp owner_id(entry) do
    case value(entry, :owner_id) do
      id when is_binary(id) and id != "" ->
        id

      _ ->
        case value(entry, :owner_email) do
          email when is_binary(email) ->
            case Repo.get_by(Accounts.User, email: String.downcase(String.trim(email))) do
              %Accounts.User{} = user -> if authorized_actor(user.id), do: user.id
              _ -> nil
            end

          _ ->
            nil
        end
    end
  end

  def valid_email?(email),
    do:
      is_binary(email) and byte_size(email) <= 160 and
        Regex.match?(~r/\A[^@,;\s<>]+@[^@,;\s<>]+\z/u, email)

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
