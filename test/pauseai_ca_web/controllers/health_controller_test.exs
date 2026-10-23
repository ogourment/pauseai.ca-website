defmodule PauseAiCaWeb.HealthControllerTest do
  use PauseAiCaWeb.ConnCase

  test "readiness queries the database while preserving release identity", %{conn: conn} do
    payload = conn |> get("/health") |> json_response(200)
    assert payload["status"] == "ok"
    assert payload["database"] == "ok"
    assert Map.has_key?(payload, "release_id")
    assert Map.has_key?(payload, "pipeline_id")
  end

  test "database connection errors, unexpected results and exits fail closed" do
    probes = [
      fn -> {:error, RuntimeError.exception("private connection details")} end,
      fn -> raise "private connection details" end,
      fn -> exit(:timeout) end,
      fn -> {:ok, %{rows: []}} end
    ]

    for probe <- probes do
      assert {:service_unavailable, payload} = PauseAiCa.Health.check(probe)
      assert payload.status == "unavailable"
      assert payload.database == "unavailable"
      refute inspect(payload) =~ "private connection"
    end
  end
end
