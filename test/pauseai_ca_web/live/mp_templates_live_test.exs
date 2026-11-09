defmodule PauseAiCaWeb.MPTemplatesLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  import PauseAiCa.MPTemplatesFixtures
  alias PauseAiCa.{Accounts, MPTemplates, Repo}

  setup do
    editor = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    member = user_fixture()
    %{editor: editor, member: member, scope: Accounts.Scope.for_user(editor)}
  end

  test "normal editor saves and reloads a bilingual draft, explicitly acknowledges and publishes",
       c do
    conn = log_in_user(c.conn, c.editor)
    {:ok, view, _} = live(conn, "/manage/mp-templates?locale=en")

    result =
      view
      |> form("#mp-template-create", campaign: %{slug: "synthetic-public-campaign"})
      |> render_submit()

    {:ok, view, _} = follow_redirect(result, conn)
    assert {:ok, [template]} = MPTemplates.list(c.scope)
    view |> form("#mp-template-form", campaign: mp_template_payload()) |> render_submit()
    assert has_element?(view, "#mp-template-status", "Draft saved")
    assert {:error, :not_found} = MPTemplates.published(template.slug, "en")
    render_submit(view, "publish", %{})
    assert has_element?(view, "#mp-template-error", "Confirm the author's permission")
    view |> form("#mp-template-publish", %{"author_permission" => "true"}) |> render_submit()
    assert has_element?(view, "#mp-template-status", "Campaign template published")
    {:ok, published} = MPTemplates.published(template.slug, "en")
    assert published.body == mp_template_payload()["editions"]["en"]["body"]
    {:ok, reloaded, _} = live(conn, "/manage/mp-templates/#{template.id}?locale=en")
    assert has_element?(reloaded, "#mp-template-en-title[value='Synthetic briefing campaign']")
    assert has_element?(reloaded, "#mp-template-published-fr")
  end

  test "public snapshots expose attribution and stable CTA without account or newsletter requirement",
       c do
    {:ok, template} = MPTemplates.create(c.scope, "public-campaign")
    {:ok, template} = MPTemplates.save(c.scope, template, mp_template_payload())
    {:ok, template} = MPTemplates.publish(c.scope, template, true)

    {:ok, view, html} =
      live(c.conn, MPTemplates.share_path(template.slug, "en", template.revision))

    assert html =~ "Synthetic Campaign Collective"

    assert has_element?(
             view,
             "#mp-template-purpose",
             mp_template_payload()["editions"]["en"]["purpose"]
           )

    [href] =
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("#mp-template-personalize")
      |> LazyHTML.attribute("href")

    uri = URI.parse(href)
    assert uri.path == "/en/contact-your-mp"

    assert URI.decode_query(uri.query) == %{
             "revision" => to_string(template.revision),
             "template" => "public-campaign"
           }

    refute html =~ c.editor.email
    {:ok, _, html} = live(c.conn, "/en/mp-templates/public-campaign?revision=9999999999999999")
    assert html =~ "Campaign template unavailable"
    refute html =~ "Synthetic Campaign Collective"
  end

  test "role loss rejects forged publication and preserves the unpublished draft", c do
    {:ok, template} = MPTemplates.create(c.scope, "permission-campaign")
    {:ok, template} = MPTemplates.save(c.scope, template, mp_template_payload())

    {:ok, view, _} =
      live(log_in_user(c.conn, c.editor), "/manage/mp-templates/#{template.id}?locale=en")

    c.editor |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    render_submit(view, "publish", %{"author_permission" => "true"})
    assert_redirect(view, "/")
    assert {:error, :not_found} = MPTemplates.published(template.slug, "en")

    assert c.conn
           |> log_in_user(c.member)
           |> get("/manage/mp-templates?locale=en")
           |> response(302)
  end
end
