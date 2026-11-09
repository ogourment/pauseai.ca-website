defmodule PauseAiCaWeb.MPTemplateLetterTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  import PauseAiCa.MPTemplatesFixtures
  alias PauseAiCa.{Accounts, MPTemplates, Repo}

  setup do
    editor = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(editor)
    {:ok, template} = MPTemplates.create(scope, "family-letter")

    payload =
      put_in(
        mp_template_payload(),
        ["editions", "en", "body"],
        "Dear {{mp_name}}, I am {{sender_name}} in {{district}} ({{postal_code}}). Please arrange a briefing."
      )

    {:ok, template} = MPTemplates.save(scope, template, payload)
    {:ok, template} = MPTemplates.publish(scope, template, true)
    %{scope: scope, template: template, member: user_fixture()}
  end

  test "published template personalizes the member letter and preserves edits during a guide or template change",
       c do
    conn = log_in_user(c.conn, c.member)
    path = "/en/contact-your-mp?template=family-letter&revision=#{c.template.published_revision}"
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#mp-selected-template", "Synthetic Campaign Collective")

    view
    |> form("#participation-form",
      participation: %{
        name: "Morgan Example",
        email: c.member.email,
        postal_code: "H2X 1Y4",
        account: "false",
        newsletter: "false"
      }
    )
    |> render_submit()

    assert render(view) =~ "Dear Steven Guilbeault, I am Morgan Example"
    assert render(view) =~ "H2X 1Y4"
    refute render(view) =~ "{{sender_name}}"

    view
    |> form("#letter-form", letter: %{subject: "My subject", body: "My own words."})
    |> render_change()

    render_patch(view, "/en/contact-your-mp?template=missing&revision=1")
    assert has_element?(view, "#mp-template-error")
    assert has_element?(view, "#letter-form textarea", "My own words.")
    assert has_element?(view, "#mp-selected-template", "Synthetic Campaign Collective")
  end

  test "old published links remain pinned after an editor publishes another revision", c do
    payload =
      put_in(mp_template_payload(), ["editions", "en", "subject"], "Later campaign subject")

    {:ok, current} = MPTemplates.save(c.scope, c.template, payload)
    {:ok, _} = MPTemplates.publish(c.scope, current, true)
    path = "/en/contact-your-mp?template=family-letter&revision=#{c.template.published_revision}"
    {:ok, view, _} = live(log_in_user(c.conn, c.member), path)

    view
    |> form("#participation-form",
      participation: %{
        name: "Morgan",
        email: c.member.email,
        postal_code: "H2X 1Y4",
        account: "false",
        newsletter: "false"
      }
    )
    |> render_submit()

    assert has_element?(view, "#letter_subject[value='Request a public briefing']")
    refute render(view) =~ "Later campaign subject"
  end

  test "invalid template links cannot silently substitute another campaign", c do
    for query <- [
          "template=missing",
          "template=family-letter&revision=0",
          "template=family-letter&revision=99999"
        ] do
      {:ok, view, _} = live(c.conn, "/en/contact-your-mp?#{query}")
      assert has_element?(view, "#mp-template-error")
      refute has_element?(view, "#participation-form")
      refute has_element?(view, "#letter-form")
    end
  end

  test "post-send sharing keeps the reviewed campaign link and excludes the private letter", c do
    path = "/en/contact-your-mp?template=family-letter&revision=#{c.template.published_revision}"
    {:ok, view, _} = live(log_in_user(c.conn, c.member), path)

    view
    |> form("#participation-form",
      participation: %{
        name: "Morgan Private",
        email: c.member.email,
        postal_code: "H2X 1Y4",
        account: "false",
        newsletter: "false"
      }
    )
    |> render_submit()

    view
    |> form("#letter-form",
      letter: %{subject: "Private subject", body: "My private personal words."}
    )
    |> render_change()

    view |> form("#send-form", send: %{consent: "true"}) |> render_submit()
    assert has_element?(view, "#send-success")

    [href] =
      render(view)
      |> LazyHTML.from_document()
      |> LazyHTML.query("#share-email")
      |> LazyHTML.attribute("href")

    body = URI.parse(href).query |> URI.decode_query() |> Map.fetch!("body")
    assert body =~ "Synthetic briefing campaign"
    assert body =~ "/en/mp-templates/family-letter?revision=#{c.template.published_revision}"
    refute body =~ "My private personal words"
    refute body =~ "Morgan Private"
    refute body =~ c.member.email
    refute body =~ "An AI escaped"
  end
end
