defmodule PauseAiCa.Mailer do
  use Swoosh.Mailer, otp_app: :pauseai_ca

  defoverridable deliver_many: 2

  @doc "Authentication-only single delivery, guarded separately from campaign mail."
  def deliver_sign_in(email, user_id) do
    with {:ok, prepared} <- PauseAiCa.MailSafety.prepare_sign_in(email, user_id) do
      instrument(:deliver, %{email: prepared, config: []}, fn ->
        Swoosh.Mailer.deliver(prepared, parse_config([]))
      end)
    end
  end

  def deliver(email, opts) do
    with {:ok, prepared} <- PauseAiCa.MailSafety.prepare(email, opts) do
      super(prepared, Keyword.delete(opts, :admin_actor_id))
    end
  end

  def deliver_many(emails, opts) do
    prepared = Enum.map(emails, &PauseAiCa.MailSafety.prepare(&1, opts))

    case Enum.find(prepared, &match?({:error, _}, &1)) do
      nil ->
        super(
          Enum.map(prepared, fn {:ok, email} -> email end),
          Keyword.delete(opts, :admin_actor_id)
        )

      error ->
        error
    end
  end
end
