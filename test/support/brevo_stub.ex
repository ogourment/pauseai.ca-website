defmodule PauseAiCa.BrevoStub do
  @moduledoc """
  Stands in for the Brevo contacts API during tests.

  Wired up as a `Req` plug in `config/test.exs`. The address selects the
  response: `taken@example.org` is already on the list, `location@example.org`
  has saved location data, and `broken@example.org` makes Brevo fail.
  """

  import Plug.Conn

  def call(conn, opts \\ [])

  def call(%Plug.Conn{method: "GET"} = conn, _opts) do
    cond do
      String.contains?(conn.request_path, "location") ->
        json(conn, 200, %{
          "email" => "location@example.org",
          "attributes" => %{"POSTAL_CODE" => "H2X 1Y4", "CITY" => "Montréal"}
        })

      String.contains?(conn.request_path, "broken") ->
        json(conn, 500, %{"message" => "server error"})

      true ->
        json(conn, 404, %{"code" => "document_not_found"})
    end
  end

  def call(%Plug.Conn{} = conn, _opts) do
    subscribe(conn)
  end

  defp subscribe(conn) do
    {:ok, body, conn} = read_body(conn)

    case Jason.decode(body) do
      {:ok, %{"email" => "taken@example.org"}} ->
        json(conn, 400, %{"code" => "duplicate_parameter", "message" => "Contact already exist"})

      {:ok, %{"email" => "broken@example.org"}} ->
        json(conn, 500, %{"message" => "server error"})

      {:ok,
       %{
         "email" => "located@example.org",
         "attributes" => %{"POSTAL_CODE" => "H2X 1Y4", "CITY" => "Montréal"}
       }} ->
        json(conn, 201, %{"id" => 2})

      {:ok, %{"email" => "located@example.org"}} ->
        json(conn, 422, %{"message" => "missing location attributes"})

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
