defmodule PauseAiCa.Mail.DeliveryReceipt do
  @moduledoc "Consumer-owned attribution for outbound mail. No body or authentication URL is stored."
  use Ecto.Schema
  alias PauseAiCa.Repo
  require Logger
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "mail_delivery_receipts" do
    field :actor_id, :binary_id
    field :newsletter_delivery_id, :binary_id
    field :recipients, {:array, :string}
    field :subject, :string
    field :sender_email, :string
    field :state, :string
    timestamps(type: :utc_datetime_usec)
  end

  def track(emails, opts, deliver) do
    if Keyword.get(opts, :newsletter_delivery_id),
      do: deliver.(),
      else: record(emails, opts, deliver)
  end

  defp record(emails, opts, deliver) do
    receipts =
      Enum.map(emails, fn email ->
        recipients =
          (email.to ++ email.cc ++ email.bcc)
          |> Enum.map(fn {_, address} -> String.downcase(String.trim(address)) end)
          |> Enum.uniq()

        {_, sender} = email.from

        Repo.insert!(%__MODULE__{
          actor_id: Keyword.get(opts, :admin_actor_id),
          newsletter_delivery_id: Keyword.get(opts, :newsletter_delivery_id),
          recipients: recipients,
          subject: email.subject,
          sender_email: sender,
          state: "attempted"
        })
      end)

    result = deliver.()
    state = if match?({:ok, _}, result), do: "accepted", else: "failed"

    Enum.each(receipts, fn receipt ->
      # Once the provider has replied, a receipt failure must not turn acceptance
      # into a retryable send error. The attempted receipt remains conservative.
      try do
        case Repo.update(Ecto.Changeset.change(receipt, state: state)) do
          {:ok, _} -> :ok
          {:error, _} -> Logger.error("Mail receipt outcome could not be recorded: #{receipt.id}")
        end
      rescue
        _ -> Logger.error("Mail receipt outcome could not be recorded: #{receipt.id}")
      end
    end)

    result
  end
end
