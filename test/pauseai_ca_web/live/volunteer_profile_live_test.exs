defmodule PauseAiCaWeb.VolunteerProfileLiveTest do
  use PauseAiCaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Volunteers.Profile

  setup :register_and_log_in_user

  test "opens directly to volunteering in both languages, with an optional location link", %{
    conn: conn
  } do
    for {profile, volunteer} <- [
          {"/en/profile", "/en/profile/volunteer"},
          {"/fr/profil", "/fr/profil/benevolat"}
        ] do
      assert {:ok, editor, _} = live(conn, volunteer)
      assert has_element?(editor, "#volunteer-profile-form #profile_availability_hours_per_week")
      assert has_element?(editor, "#volunteer-location-reminder a[href='#{profile}#location']")
      refute has_element?(editor, "#profile_share_contribution[checked]")
    end
  end

  test "reports an invalid field, keeps the other contributions and saves on retry", %{
    conn: conn,
    user: user
  } do
    {:ok, editor, _} = live(conn, "/en/profile/volunteer")

    contribution = %{
      "availability_hours_per_week" => "200",
      "selected_skills" => ["", "video_editing"],
      "experience" => %{"video_editing" => "guide", "photography" => "done"},
      "share_contribution" => "true"
    }

    render_submit(editor, "save", %{"profile" => contribution})

    assert has_element?(
             editor,
             "#profile_availability_hours_per_week[aria-invalid=true][aria-describedby=profile_availability_hours_per_week-error]"
           )

    assert has_element?(editor, "input[value='video_editing'][checked]")
    assert has_element?(editor, "input[data-experience=video_editing][value=guide][checked]")
    refute has_element?(editor, "input[data-experience=photography]")
    refute Repo.get_by(Profile, user_id: user.id)

    render_submit(editor, "save", %{
      "profile" => %{contribution | "availability_hours_per_week" => "3"}
    })

    assert has_element?(editor, "#volunteer-save-status", "Saved")

    assert Volunteers.get_profile(Scope.for_user(user)).details["availability_hours_per_week"] ==
             3

    {:ok, reopened, _} = live(conn, "/en/profile/volunteer")
    assert has_element?(reopened, "#profile_availability_hours_per_week[value='3']")
    assert has_element?(reopened, "input[value='video_editing'][checked]")
    assert has_element?(reopened, "input[data-experience=video_editing][value=guide][checked]")
    assert has_element?(reopened, "#profile_share_contribution[checked]")
  end

  test "preserves older contact fields and restores contributions from a private draft", %{
    conn: conn,
    user: user
  } do
    profile =
      Repo.insert!(%Profile{
        user_id: user.id,
        step: "contact",
        draft: %{
          "city" => "Gatineau",
          "contact_preference" => "signal",
          "application_message" => "Help with French translations"
        },
        details: %{
          "city" => "Ottawa",
          "contact_notes" => "Contact me after six.",
          "availability_hours_per_week" => 2
        }
      })

    {:ok, editor, _} = live(conn, "/en/profile/volunteer")
    assert has_element?(editor, "#profile_availability_hours_per_week[value='2']")
    assert has_element?(editor, "#profile_application_message", "Help with French translations")

    profile
    |> Ecto.Changeset.change(draft: Map.put(profile.draft, "signal_number", "+1 613 555 0102"))
    |> Repo.update!()

    render_submit(editor, "save", %{
      "profile" => %{"availability_hours_per_week" => "4", "city" => "Toronto"}
    })

    saved = Repo.get!(Profile, profile.id)
    assert saved.draft["city"] == "Gatineau"
    assert saved.draft["signal_number"] == "+1 613 555 0102"
    assert saved.details["city"] == "Ottawa"
    assert saved.details["contact_notes"] == "Contact me after six."
    assert saved.details["application_message"] == "Help with French translations"
    assert saved.details["availability_hours_per_week"] == 4
    refute saved.details["share_contribution"]
  end

  test "changing hours in an older tab does not restore withdrawn sharing", %{
    conn: conn,
    user: user
  } do
    scope = Scope.for_user(user)

    {:ok, _} =
      Volunteers.save_contribution(scope, %{
        "availability_hours_per_week" => "2",
        "share_contribution" => "true"
      })

    {:ok, editor, _} = live(conn, "/en/profile/volunteer")
    assert has_element?(editor, "#profile_share_contribution[checked]")

    {:ok, _} = Volunteers.save_contribution(scope, %{"share_contribution" => "false"})

    render_submit(editor, "save", %{
      "profile" => %{"availability_hours_per_week" => "3", "share_contribution" => "true"}
    })

    saved = Volunteers.get_profile(scope)
    assert saved.details["availability_hours_per_week"] == 3
    refute saved.details["share_contribution"]
    refute has_element?(editor, "#profile_share_contribution[checked]")
  end
end
