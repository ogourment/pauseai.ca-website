if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.PlaywrightProtocolTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PhoenixTest
    @moduletag :atdd

    test "a missing element returns a bounded assertion result without restarting the driver", %{
      conn: conn
    } do
      conn = visit(conn, "/en")
      connection = Process.whereis(PlaywrightEx.Supervisor.Connection)
      assert is_pid(connection)
      started = System.monotonic_time(:millisecond)

      assert {:ok, false} =
               PlaywrightEx.Frame.expect(conn.frame_id,
                 expression: "to.be.visible",
                 selector: "#absent-playwright-protocol-sentinel",
                 timeout: 2_000
               )

      elapsed = System.monotonic_time(:millisecond) - started
      assert elapsed < 3_000
      assert Process.whereis(PlaywrightEx.Supervisor.Connection) == connection

      assert {:ok, true} =
               PlaywrightEx.Frame.expect(conn.frame_id,
                 expression: "to.be.visible",
                 selector: "body",
                 timeout: 2_000
               )
    end
  end
end
