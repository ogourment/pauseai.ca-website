defmodule PauseAiCa.HealthPoolTest do
  use ExUnit.Case, async: false

  alias PauseAiCa.Repo

  test "readiness tolerates a briefly occupied pool without reporting a database outage" do
    config = Application.fetch_env!(:pauseai_ca, Repo)

    opts =
      Keyword.merge(config,
        name: :readiness_pool_test,
        pool: DBConnection.ConnectionPool,
        pool_size: 1
      )

    repo = start_supervised!({Repo, opts})
    parent = self()

    holder =
      Task.async(fn ->
        Repo.put_dynamic_repo(repo)

        Repo.checkout(fn ->
          send(parent, :connection_held)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :connection_held, 2_000
    # Release while the real bounded readiness query is waiting for a slot.
    Process.send_after(holder.pid, :release, 75)
    previous = Repo.put_dynamic_repo(repo)

    try do
      assert {:ok, %{database: "ok"}} = PauseAiCa.Health.check()
    after
      Repo.put_dynamic_repo(previous)
      send(holder.pid, :release)
      Task.await(holder)
    end
  end
end
