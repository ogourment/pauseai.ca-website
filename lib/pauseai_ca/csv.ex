defmodule PauseAiCa.CSV do
  @moduledoc "Small CSV encoder for spreadsheet-safe text exports."

  def encode(rows) do
    rows
    |> Enum.map(fn row -> [Enum.intersperse(Enum.map(row, &cell/1), ","), "\r\n"] end)
    |> IO.iodata_to_binary()
  end

  defp cell(value) do
    value = to_string(value || "")

    value =
      if Regex.match?(~r/\A[\s\x00-\x20\x{FEFF}]*[=+@-]/u, value),
        do: "'" <> value,
        else: value

    ["\"", String.replace(value, "\"", "\"\""), "\""]
  end
end
