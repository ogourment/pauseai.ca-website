defmodule PauseAiCa.ChapterPagesTest do
  use PauseAiCa.DataCase, async: false

  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Incubators, Volunteers}
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Incubators.ChapterPageEdit

  # CHAPTER-PAGES-01: a chapter manager may save and publish only within their
  # group. The same slug can exist in two chapters. Readers see only the saved
  # publication, and a revoked manager cannot open drafts or publish them.
  test "chapter pages isolate audiences, drafts and publication by group and revision" do
    admin = user_fixture() |> change(superadmin: true) |> Repo.update!() |> Scope.for_user()
    organizer = user_fixture()
    manager = Scope.for_user(organizer)
    toronto = chapter(admin, "Toronto", "toronto")
    ottawa = chapter(admin, "Ottawa", "ottawa")
    {:ok, grant} = Volunteers.assign_manager(admin, toronto.id, organizer.email)

    page = %{
      "slug" => "plan",
      "title" => "Toronto plan",
      "body" => "Public Toronto",
      "navigation_order" => 2
    }

    assert {:error, {:invalid, %{"slug" => :bad_address}}} =
             Incubators.save_chapter_page(manager, toronto.id, nil, 0, %{page | "slug" => "home"})

    assert {:error, :forbidden} = Incubators.save_chapter_page(manager, ottawa.id, nil, 0, page)
    assert {:ok, draft} = Incubators.save_chapter_page(manager, toronto.id, nil, 0, page)
    assert {:ok, _, [^draft]} = Incubators.chapter_pages(manager, toronto.id)
    assert Incubators.published_chapter_pages(toronto.id) == []

    assert {:error, {:invalid, %{"slug" => :address_taken}}} =
             Incubators.save_chapter_page(manager, toronto.id, nil, 0, page)

    assert {:ok, ottawa_draft} =
             Incubators.save_chapter_page(admin, ottawa.id, nil, 0, %{page | "body" => "Ottawa"})

    assert {:ok, _} =
             Incubators.publish_chapter_page(admin, ottawa.id, "plan", ottawa_draft.revision)

    assert {:ok, published} =
             Incubators.publish_chapter_page(manager, toronto.id, "plan", draft.revision)

    assert {:ok, latest} =
             Incubators.save_chapter_page(
               manager,
               toronto.id,
               "plan",
               published.revision,
               %{page | "body" => "Private Toronto"}
             )

    assert {:error, :stale} =
             Incubators.publish_chapter_page(manager, toronto.id, "plan", draft.revision)

    assert [{"plan", %{"body" => "Public Toronto"}}] =
             Incubators.published_chapter_pages(toronto.id)

    assert [{"plan", %{"body" => "Ottawa"}}] = Incubators.published_chapter_pages(ottawa.id)

    assert :ok = Volunteers.revoke_manager(admin, grant.id)
    assert {:error, :forbidden} = Incubators.chapter_pages(manager, toronto.id)

    assert {:error, :forbidden} =
             Incubators.publish_chapter_page(manager, toronto.id, "plan", latest.revision)

    assert Repo.all(
             from e in ChapterPageEdit,
               where: e.page_id == ^latest.id,
               order_by: e.revision,
               select: {e.action, e.content}
           ) == [
             {"saved", draft.draft},
             {"published", published.draft},
             {"saved", latest.draft}
           ]
  end

  defp chapter(admin, name, slug) do
    {:ok, group} = Volunteers.create_group(admin, %{name: name})

    {:ok, profile} =
      Incubators.configure(admin, group.id, %{
        "name_en" => name,
        "name_fr" => name,
        "area_served" => "local",
        "fsas" => "M5H",
        "published" => true
      })

    {:ok, draft} =
      Incubators.save_chapter(admin, group.id, profile.revision, %{
        "slug" => slug,
        "en" => name,
        "fr" => ""
      })

    {:ok, _} = Incubators.publish_chapter(admin, group.id, draft.revision)
    group
  end
end
