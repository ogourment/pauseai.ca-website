defmodule PauseAiCa.Outreach.Mailboxes do
  @moduledoc "Consumer-owned, explicitly enabled and verified outreach sender configuration."
  alias PauseAiCa.{Volunteers, Repo, Accounts}
  alias PauseAiCa.Outreach.Access

  def all(scope) do
    authorization = Access.facts(scope)

    if match?(%{confirmed?: true, full_access?: true}, authorization) or
         match?(%{confirmed?: true, eligible?: true}, authorization),
       do:
         {:ok,
          Enum.filter(
            configured(),
            &PhoenixMailWorkflow.MailboxAccess.allowed?(authorization, &1.id)
          )},
       else: {:error, :unauthorized}
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
      valid_ref?(box.id) and box.locale in ["en", "fr"] and
        valid_email?(box.email) and is_binary(box.name) and
        not String.contains?(box.name, ["\r", "\n"])
    end)
  end

  def authorized_actor(id, ref \\ nil) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Accounts.User{} = user <- Repo.get(Accounts.User, uuid),
         true <-
           if(is_nil(ref),
             do: Volunteers.superadmin?(Accounts.Scope.for_user(user)),
             else: Access.allowed?(Accounts.Scope.for_user(user), ref)
           ) do
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

  def valid_ref?(ref), do: is_binary(ref) and Regex.match?(~r/\A[a-z][a-z0-9_]{0,63}\z/, ref)

  def catalog!(entries, owner) when is_list(entries) do
    boxes =
      Enum.map(entries, fn
        %{"id" => id, "email" => email, "name" => name, "locale" => locale} = entry ->
          aliases = Map.get(entry, "receiving_addresses", [email])
          enabled = Map.get(entry, "enabled", false)
          verified = Map.get(entry, "verified", false)

          unless valid_ref?(id) and valid_email?(email) and is_binary(name) and
                   String.trim(name) != "" and not String.contains?(name, ["\r", "\n"]) and
                   locale in ["en", "fr"] and is_list(aliases) and aliases != [] and
                   Enum.all?(aliases, &valid_email?/1) and
                   is_boolean(enabled) and is_boolean(verified) do
            raise ArgumentError, "Invalid outreach mailbox configuration"
          end

          %{
            id: id,
            name: name,
            email: email,
            locale: locale,
            receiving_addresses: aliases,
            enabled?: enabled,
            verified?: verified,
            owner_id: owner
          }

        _ ->
          raise ArgumentError, "Missing outreach mailbox configuration fields"
      end)

    ids = Enum.map(boxes, & &1.id)

    addresses =
      Enum.flat_map(boxes, fn box ->
        [box.email | box.receiving_addresses] |> Enum.map(&String.downcase/1) |> Enum.uniq()
      end)

    unless Enum.uniq(ids) == ids and Enum.uniq(addresses) == addresses do
      raise ArgumentError, "Overlapping outreach mailbox IDs or addresses"
    end

    boxes
  end

  def catalog!(_, _), do: raise(ArgumentError, "Expected an array of outreach mailboxes")

  def valid_email?(email),
    do:
      is_binary(email) and byte_size(email) <= 160 and
        Regex.match?(~r/\A[^@,;\s<>]+@[^@,;\s<>]+\z/u, email)

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
