defmodule PauseAiCa.RepresentStub do
  @moduledoc """
  Stands in for Open North's Represent API during tests.

  Wired up as a `Req` plug in `config/test.exs` so no test reaches the network.
  The postal code selects the response:

    * `H2X 1Y4` — one member of parliament
    * `K1A 0A6` — a district with no member we can email
    * `X0A 0H0` — unknown to the service
    * anything else — the service is unavailable
  """

  import Plug.Conn

  def call(%Plug.Conn{request_path: path} = conn, _opts \\ []) do
    case postal_code(path) do
      "H2X1Y4" ->
        json(
          conn,
          200,
          member_payload(
            "Steven Guilbeault",
            "Laurier—Sainte-Marie",
            "Steven.Guilbeault@parl.gc.ca",
            ["French  English"]
          )
        )

      "V7A5J9" ->
        json(
          conn,
          200,
          member_payload("Parm Bains", "Richmond East—Steveston", "parm.bains@parl.gc.ca", [
            "English"
          ])
        )

      "J3B6X3" ->
        json(
          conn,
          200,
          member_payload("Christine Normandin", "Saint-Jean", "christine.normandin@parl.gc.ca", [
            "French"
          ])
        )

      "K1A0A6" ->
        json(conn, 200, %{"representatives_centroid" => []})

      "X0A0H0" ->
        json(conn, 404, %{"error" => "not found"})

      _other ->
        json(conn, 500, %{"error" => "unavailable"})
    end
  end

  defp postal_code(path) do
    path |> String.split("/", trim: true) |> List.last() |> to_string()
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp member_payload(name, district, email, preferred_languages) do
    %{
      "representatives_centroid" => [
        %{
          "name" => name,
          "district_name" => district,
          "email" => email,
          "party_name" => "Liberal",
          "url" => "https://www.ourcommons.ca/Members/en/steven-guilbeault(14171)",
          "extra" => %{"preferred_languages" => preferred_languages},
          "representative_set_name" => "House of Commons"
        },
        %{
          "name" => "A Provincial Member",
          "district_name" => "Sainte-Marie—Saint-Jacques",
          "email" => "provincial@example.org",
          "representative_set_name" => "Quebec National Assembly"
        }
      ]
    }
  end
end
