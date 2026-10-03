defmodule PauseAiCa.Mail.ContactSource do
  @behaviour PhoenixMarkdownEditor.ContactSource
  alias PauseAiCa.{AccountManagement, Mail}

  def search(scope, query, _opts) do
    if PauseAiCa.Volunteers.allowed?(scope) do
      {:ok,
       AccountManagement.list(scope, query)
       |> Enum.take(20)
       |> Enum.flat_map(fn row ->
         case Mail.recipient(scope, row.user.id) do
           {:ok, contact} -> [contact]
           _ -> []
         end
       end)}
    else
      {:error, :unauthorized}
    end
  end

  def fetch(scope, id, _opts), do: Mail.recipient(scope, id)
end
