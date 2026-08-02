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
      "H2X1Y4" -> json(conn, 200, member_payload())
      "K1A0A6" -> json(conn, 200, %{"representatives_centroid" => []})
      "X0A0H0" -> json(conn, 404, %{"error" => "not found"})
      _other -> json(conn, 500, %{"error" => "unavailable"})
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

  defp member_payload do
    %{
      "representatives_centroid" => [
        %{
          "name" => "Steven Guilbeault",
          "district_name" => "Laurier—Sainte-Marie",
          "email" => "Steven.Guilbeault@parl.gc.ca",
          "party_name" => "Liberal",
          "url" => "https://www.ourcommons.ca/Members/en/steven-guilbeault(14171)",
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
