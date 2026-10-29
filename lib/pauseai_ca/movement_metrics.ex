defmodule PauseAiCa.MovementMetrics do
  @moduledoc "Read-only movement aggregates with separate units for mail, memberships and tasks."
  import Ecto.Query
  alias PauseAiCa.Repo
  alias PauseAiCa.Newsletters.{Batch, Delivery, ResultSnapshot}
  alias PauseAiCa.Incubators.{Membership, Profile}

  def summary do
    attempted = from d in Delivery, where: not is_nil(d.attempted_at), select: d.batch_id

    campaigns =
      from b in Batch,
        where: b.delivery_environment == "production" and b.id in subquery(attempted)

    reports =
      from s in ResultSnapshot,
        join: b in subquery(campaigns),
        on: b.id == s.batch_id

    newsletter =
      Repo.one(
        from s in reports,
          select: %{
            reported_opens: coalesce(sum(fragment("(?->>'opened')::integer", s.observed)), 0),
            proxy_opens: coalesce(sum(fragment("(?->>'proxy_opened')::integer", s.observed)), 0),
            reports: count(s.batch_id),
            partial_reports: filter(count(s.batch_id), s.partial == true),
            oldest_refresh: min(s.refreshed_at)
          }
      )
      |> Map.put(:campaigns, Repo.aggregate(campaigns, :count))

    memberships =
      Repo.one(
        from m in Membership,
          select: %{
            approved: filter(count(m.id), m.status in ["approved", "admitted"]),
            pending: filter(count(m.id), m.status == "pending")
          }
      )

    tasks =
      Repo.one(
        from t in PauseAiCa.Tasks.Task,
          select: %{
            active: filter(count(t.id), t.status in ["open", "in_progress", "in_review"]),
            completed: filter(count(t.id), t.status == "done")
          }
      )

    %{
      newsletter: newsletter,
      incubators: %{
        published: Repo.aggregate(from(p in Profile, where: p.published == true), :count),
        approved_memberships: memberships.approved,
        pending_requests: memberships.pending
      },
      tasks: tasks
    }
  end
end
