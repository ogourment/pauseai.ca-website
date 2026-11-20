defmodule PauseAiCaWeb.Plugs.ClientErrorBody do
  @moduledoc "Apply a small JSON body limit before the endpoint's general-purpose parsers."
  import Plug.Conn

  @parser Plug.Parsers.init(
            parsers: [:json],
            json_decoder: Jason,
            length: 2048,
            read_length: 2048
          )
  def init(opts), do: opts

  def call(%{method: "POST", request_path: "/client-errors"} = conn, _) do
    Plug.Parsers.call(conn, @parser)
  rescue
    Plug.Parsers.RequestTooLargeError -> conn |> send_resp(413, "") |> halt()
    Plug.Parsers.UnsupportedMediaTypeError -> conn |> send_resp(415, "") |> halt()
    Plug.Parsers.ParseError -> conn |> send_resp(400, "") |> halt()
  end

  def call(conn, _), do: conn
end
