defmodule PauseAiCa.BrevoStub do
  @moduledoc """
  Stands in for the Brevo contacts API during tests.

  Wired up as a `Req` plug in `config/test.exs`. The address selects the
  response: `taken@example.org` is already on the list, `broken@example.org`
  makes Brevo fail, anything else subscribes.
  """

  import Plug.Conn

  def call(%Plug.Conn{} = conn, _opts \\ []) do
    {:ok, body, conn} = read_body(conn)

    case Jason.decode(body) do
      {:ok, %{"email" => "taken@example.org"}} ->
        json(conn, 400, %{"code" => "duplicate_parameter", "message" => "Contact already exist"})

      {:ok, %{"email" => "broken@example.org"}} ->
        json(conn, 500, %{"message" => "server error"})

      _other ->
        json(conn, 201, %{"id" => 1})
    end
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
