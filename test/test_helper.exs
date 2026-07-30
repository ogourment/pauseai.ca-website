ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(PauseAiCa.Repo, :manual)

if System.get_env("ATDD") == "true" do
  {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()

  {:ok, _} =
    Bandit.start_link(
      plug: PauseAiCaWeb.Endpoint,
      ip: {127, 0, 0, 1},
      port: System.get_env("ATDD_PORT", "4116") |> String.to_integer()
    )
end
