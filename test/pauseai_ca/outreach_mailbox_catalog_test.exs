defmodule PauseAiCa.OutreachMailboxCatalogTest do
  use ExUnit.Case, async: true
  alias PauseAiCa.Outreach.Mailboxes

  @entry %{"id" => "new_team", "email" => "team@example.org", "name" => "Team", "locale" => "fr"}

  test "an arbitrary mailbox defaults to its own receiving address and requires activation" do
    assert [
             %{
               id: "new_team",
               receiving_addresses: ["team@example.org"],
               enabled?: false,
               verified?: false,
               owner_id: "owner"
             }
           ] = Mailboxes.catalog!([@entry], "owner")
  end

  test "ambiguous IDs and routes are rejected before use" do
    for other <- [
          Map.put(@entry, "email", "other@example.org"),
          Map.merge(@entry, %{
            "id" => "another",
            "email" => "other@example.org",
            "receiving_addresses" => ["TEAM@example.org"]
          })
        ] do
      assert_raise ArgumentError, fn -> Mailboxes.catalog!([@entry, other], nil) end
    end
  end

  test "invalid IDs, empty receiving routes and non-boolean activation are rejected" do
    for {key, value} <- [{"id", "Team?"}, {"receiving_addresses", []}, {"verified", "true"}] do
      assert_raise ArgumentError, fn -> Mailboxes.catalog!([Map.put(@entry, key, value)], nil) end
    end
  end
end
