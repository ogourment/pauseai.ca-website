defmodule PauseAiCa.ContactMigration.CSV do
  @moduledoc false

  @known ~w(status name email city discord discord_user_id signup_date source email_verified skills_interests bio welcomed_date welcomed_by notes processed_at intro next_meetup meetups_attended)

  def source_headers, do: @known

  def parse(contents) when is_binary(contents) do
    with {:ok, [headers | data]} <- rows(contents),
         normalized = Enum.map(headers, &normalize_header/1),
         true <- "email" in normalized do
      parsed =
        data
        |> Enum.reject(&Enum.all?(&1, fn value -> String.trim(value) == "" end))
        |> Enum.with_index(2)
        |> Enum.map(&to_row(&1, normalized))

      {:ok, parsed, normalized -- @known}
    else
      false -> {:error, :missing_email}
      {:ok, []} -> {:error, :empty}
      {:error, reason} -> {:error, reason}
    end
  end

  defp rows(contents) do
    contents
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> parse_chars([], [], "", false)
  end

  defp parse_chars(<<>>, row, rows, field, false),
    do: {:ok, Enum.reverse([Enum.reverse([field | row]) | rows])}

  defp parse_chars(<<>>, _row, _rows, _field, true), do: {:error, :unterminated_quote}

  defp parse_chars(<<"\"\"", rest::binary>>, row, rows, field, true),
    do: parse_chars(rest, row, rows, field <> "\"", true)

  defp parse_chars(<<"\"", rest::binary>>, row, rows, field, true),
    do: parse_chars(rest, row, rows, field, false)

  defp parse_chars(<<"\"", rest::binary>>, row, rows, "", false),
    do: parse_chars(rest, row, rows, "", true)

  defp parse_chars(<<",", rest::binary>>, row, rows, field, false),
    do: parse_chars(rest, [field | row], rows, "", false)

  defp parse_chars(<<"\n", rest::binary>>, row, rows, field, false),
    do: parse_chars(rest, [], [Enum.reverse([field | row]) | rows], "", false)

  defp parse_chars(<<char::utf8, rest::binary>>, row, rows, field, quoted),
    do: parse_chars(rest, row, rows, field <> <<char::utf8>>, quoted)

  defp to_row({values, line}, headers) do
    values = values ++ List.duplicate("", max(length(headers) - length(values), 0))
    row = headers |> Enum.zip(values) |> Map.new(fn {key, value} -> {key, String.trim(value)} end)

    Map.merge(row, %{
      "row" => line,
      "id" => Integer.to_string(line),
      "valid" => valid_email?(row["email"])
    })
  end

  defp normalize_header(header),
    do: header |> String.trim() |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_")

  defp valid_email?(email),
    do: is_binary(email) and Regex.match?(~r/^[^@,;\s]+@[^@,;\s]+$/, email)
end
