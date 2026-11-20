defmodule PauseAiCaWeb.GroupsParticipationLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Incubators, Newsletters, Participation, Repo, Volunteers}

  for stage <- ["active", "incubator"] do
    test "#{stage} group interest reaches its organizer only after email confirmation", %{
      conn: conn
    } do
      admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
      scope = Accounts.Scope.for_user(admin)
      organizer = user_fixture()
      other = user_fixture()
      {:ok, group} = Volunteers.create_group(scope, %{name: "Ottawa"})
      {:ok, second} = Volunteers.create_group(scope, %{name: "Toronto"})
      {:ok, _} = Volunteers.assign_manager(scope, group.id, organizer.email)
      {:ok, _} = Volunteers.assign_manager(scope, second.id, other.email)

      {:ok, _} =
        Incubators.configure(scope, group.id, %{
          name_en: "Ottawa",
          name_fr: "Ottawa",
          stage: unquote(stage),
          published: true
        })

      {:ok, view, _} = live(conn, "/en/groups")
      view |> element("#group-#{group.id} a", "Get involved") |> render_click()
      assert has_element?(view, "#participation-selected-group", "Ottawa")

      view
      |> form("#participation-form",
        participation: %{
          name: "Review volunteer",
          email: "editor@example.org",
          interests: ["video_editing", "translation"],
          help_text: "I can caption the march video."
        }
      )
      |> render_submit()

      assert has_element?(view, "#account-email-pending")
      request = Repo.get_by!(Participation.Request, email: "editor@example.org")
      assert request.state == "pending"
      assert request.context["interests"] == ["video_editing", "translation"]
      assert request.context["incubator_group_id"] == group.id
      organizer_conn = log_in_user(build_conn(), organizer)
      path = "/manage/local-interest?locale=en"
      {:ok, pending, _} = live(organizer_conn, path)
      refute has_element?(pending, "#local-request-#{request.id}")
      assert_receive {:email, %{to: [{"", "editor@example.org"}]} = mail}
      [url] = Regex.run(~r{https?://[^\s]+/participation/confirm\?[^\s]+}, mail.text_body)

      token =
        url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("token")

      assert {:ok, _} = Participation.confirm(token)
      {:ok, review, _} = live(organizer_conn, path)
      row = "#local-request-#{request.id}"
      assert has_element?(review, row, "Video editing")
      assert has_element?(review, row, "caption the march video")
      review |> element(row <> " button", "I’ll follow up") |> render_click()
      assert has_element?(review, row <> " a", "Email the volunteer")
      assert has_element?(review, row <> " a", "Check onboarding calls")
      assert has_element?(review, row <> " a[href='/groups/#{group.id}/join?locale=en']")

      {:ok, foreign, _} = live(log_in_user(build_conn(), other), path)
      refute has_element?(foreign, row)

      assert {:error, :unauthorized} =
               Participation.claim(Accounts.Scope.for_user(other), request.id)

      :ok =
        Volunteers.revoke_manager(
          scope,
          Repo.get_by!(Volunteers.Manager, user_id: organizer.id).id
        )

      assert {:error, :unauthorized} =
               Participation.claim(Accounts.Scope.for_user(organizer), request.id)

      assert Repo.aggregate(Incubators.Membership, :count) == 0
      assert Repo.aggregate(Newsletters.Subscription, :count) == 0
      refute Accounts.get_user_by_email("editor@example.org")
    end
  end
end
