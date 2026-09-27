defmodule PauseAiCa.ReportingCalendar do
  @moduledoc "Canadian reporting days, using PostgreSQL's maintained IANA timezone rules."
  alias PauseAiCa.Repo
  @zone "America/Toronto"
  def zone, do: @zone

  def today(now \\ DateTime.utc_now()) do
    %{rows: [[day]]} = Repo.query!("SELECT ($1::timestamptz AT TIME ZONE $2)::date", [now, @zone])
    day
  end

  def starts_at(%Date{} = day) do
    %{rows: [[utc]]} =
      Repo.query!("SELECT ($1::timestamp AT TIME ZONE $2) AT TIME ZONE 'UTC'", [
        NaiveDateTime.new!(day, ~T[00:00:00]),
        @zone
      ])

    DateTime.from_naive!(utc, "Etc/UTC")
  end
end
