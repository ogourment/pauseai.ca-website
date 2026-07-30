ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(PauseAiCa.Repo, :manual)

if System.get_env("ATDD") == "true" do
  {:ok, _} = Application.ensure_all_started(:playwright)
end
