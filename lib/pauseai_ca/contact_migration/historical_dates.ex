defmodule PauseAiCa.ContactMigration.HistoricalDates do
  @moduledoc "Source timestamps retain their meaning and precision separately from migration activity."

  @kinds ~w(source_created notification_sent first_known_processing)

  def display_value(%{"value" => value, "precision" => "datetime"}) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} ->
        datetime
        |> DateTime.to_iso8601()
        |> String.replace("T", " ")
        |> String.replace("Z", " UTC")

      _ ->
        value
    end
  end

  def display_value(date), do: date["value"]

  # Render modern spreadsheet date serials as dates, without inventing a UTC
  # timestamp. The immutable source observation retains the original value.
  # Short numbers may be years; do not reinterpret those as early-1900s dates.
  def source_date_display(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {serial, ""} when serial >= 10_000 and serial < 2_958_466 ->
        ~D[1899-12-30] |> Date.add(floor(serial)) |> Date.to_iso8601()

      _ ->
        value
    end
  end

  def source_date_display(value) when is_number(value),
    do: source_date_display(to_string(value))

  def source_date_display(value), do: value

  def entries(source_data) do
    history = decode(source_data["historical_dates"])

    dates =
      for key <- ~w(signup_date processed_at),
          %{"value" => value} = date <- [history[key]],
          is_binary(value) do
        Map.merge(date, %{"kind" => key, "source" => source_data["source"] || "google_sheet"})
      end

    events =
      case history["events"] do
        events when is_list(events) ->
          Enum.filter(events, fn
            %{"kind" => kind, "value" => value, "source" => source}
            when kind in @kinds and is_binary(value) and is_binary(source) ->
              true

            _ ->
              false
          end)

        _ ->
          []
      end

    events ++ dates
  end

  defp decode(value) when is_map(value), do: value

  defp decode(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, history} when is_map(history) -> history
      _ -> %{}
    end
  end

  defp decode(_), do: %{}
end
