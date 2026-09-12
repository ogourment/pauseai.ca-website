# :atdd and :external reach outside the test process; opt in with --only.
ExUnit.start(exclude: [:external])
Ecto.Adapters.SQL.Sandbox.mode(PauseAiCa.Repo, :manual)

if System.get_env("ATDD") == "true" do
  phase_root = Path.join("tmp/atdd-phases", "session-#{System.system_time(:microsecond)}")
  File.mkdir_p!(phase_root)
  System.put_env("PAUSEAI_ATDD_PHASE_ROOT", phase_root)

  ExUnit.after_suite(fn _stats ->
    phases = Path.wildcard(Path.join(phase_root, "*/evidence.json")) |> Enum.map(&Path.dirname/1)

    ids =
      Enum.flat_map(phases, fn dir ->
        dir
        |> Path.join("evidence.json")
        |> File.read!()
        |> Jason.decode!()
        |> Map.fetch!("scenarios")
        |> Enum.map(&Map.fetch!(&1, "id"))
      end)
      |> Enum.uniq()

    if phases != [] do
      output = Path.join(phase_root, "assembled")
      :ok = AcceptanceHarness.EvidenceAssembly.assemble!(phases, output, ids)
      File.cp_r!(output, "tmp/atdd")
    end
  end)

  {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()

  {:ok, _} =
    Bandit.start_link(
      plug: PauseAiCaWeb.Endpoint,
      ip: {127, 0, 0, 1},
      port: System.get_env("ATDD_PORT", "4116") |> String.to_integer()
    )
end
