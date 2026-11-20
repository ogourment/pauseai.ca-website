if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.OperationalIncidentsTest do
    use AcceptanceHarness.Playwright.Case, async: false
    alias PauseAiCa.{Incidents, Repo}
    @moduletag :atdd
    test "browser errors and rejected promises reach the incident store without raw exception data",
         %{conn: conn} do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      :ets.delete_all_objects(:pauseai_incident_buffer)
      page = conn |> visit("/en/groups") |> assert_has("[data-phx-main].phx-connected")

      PhoenixTest.Playwright.evaluate(
        page,
        """
        (async () => {
          const original = window.fetch.bind(window)
          const results = []
          window.fetch = (url, opts) => {
            const response = original(url, opts)
            if (url === "/client-errors") results.push(response.then(r => r.status))
            return response
          }
          try {
            window.dispatchEvent(new ErrorEvent("error", {error:new TypeError("private address"), lineno:71}))
            window.dispatchEvent(new PromiseRejectionEvent("unhandledrejection", {promise:Promise.resolve(),reason:new RangeError("private token")}))
            return await Promise.all(results)
          } finally {window.fetch = original}
        })()
        """,
        fn codes -> assert codes == [204, 204] end
      )

      Incidents.flush()

      assert %{rows: [["exception/TypeError", "groups:71"], ["rejection/RangeError", "groups:0"]]} =
               Repo.query!(
                 "select category,location from operational_incidents where source='browser' order by category"
               )
    end
  end
end
