defmodule PauseAiCa.MPTemplatesTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  import PauseAiCa.MPTemplatesFixtures
  alias PauseAiCa.{Accounts, MPTemplates, Repo}
  alias PauseAiCa.MPTemplates.{Template, Revision}

  setup do
    editor = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    member = user_fixture()
    %{editor: editor, scope: Accounts.Scope.for_user(editor), member: member}
  end

  test "drafts remain private and publication requires complete editions and fresh author permission",
       c do
    assert {:ok, draft} = MPTemplates.create(c.scope, "synthetic-campaign")
    assert {:error, :not_found} = MPTemplates.published(draft.slug, "en")
    assert {:error, :author_permission_required} = MPTemplates.publish(c.scope, draft, false)
    assert {:error, :invalid_content} = MPTemplates.publish(c.scope, draft, true)
    payload = mp_template_payload()
    assert {:ok, saved} = MPTemplates.save(c.scope, draft, payload)
    assert {:error, :author_permission_required} = MPTemplates.publish(c.scope, saved, nil)
    assert {:ok, published} = MPTemplates.publish(c.scope, saved, true)
    assert published.published_revision == published.revision

    for locale <- ["en", "fr"] do
      assert {:ok, edition} = MPTemplates.published(draft.slug, locale)
      assert edition.author == payload["author"]
      assert edition.purpose == payload["editions"][locale]["purpose"]
      assert edition.body == payload["editions"][locale]["body"]

      assert URI.decode_query(URI.parse(edition.share_path).query) == %{
               "revision" => to_string(published.revision)
             }

      refute edition.share_path =~ c.editor.email
      refute Map.has_key?(edition, :editor_id)
    end

    assert {:ok, history} = MPTemplates.history(c.scope, published)
    assert Enum.map(history, & &1.action) == ["published", "saved", "created"]
    assert Enum.map(history, & &1.author_permission) == [true, false, false]
    assert Enum.all?(history, &(&1.editor_id == c.editor.id))
  end

  test "frozen published links survive subsequent drafts and publications", c do
    {:ok, draft} = MPTemplates.create(c.scope, "frozen-campaign")
    {:ok, saved} = MPTemplates.save(c.scope, draft, mp_template_payload())
    {:ok, first} = MPTemplates.publish(c.scope, saved, true)
    {:ok, original} = MPTemplates.published(first.slug, "en", first.revision)

    changed =
      put_in(mp_template_payload(), ["editions", "en", "body"], "A separately reviewed revision.")

    {:ok, saved} = MPTemplates.save(c.scope, first, changed)
    assert {:ok, ^original} = MPTemplates.published(first.slug, "en")
    {:ok, latest} = MPTemplates.publish(c.scope, saved, "true")
    assert latest.revision > first.revision
    assert {:ok, ^original} = MPTemplates.published(first.slug, "en", to_string(first.revision))

    assert {:ok, %{body: "A separately reviewed revision."}} =
             MPTemplates.published(first.slug, "en")

    assert {:error, :not_found} = MPTemplates.published(first.slug, "en", saved.revision)

    for invalid <- ["999999999999999999999", 2_147_483_648, "-1", "3junk", %{}, 0] do
      assert {:error, :not_found} = MPTemplates.published(first.slug, "en", invalid)
    end
  end

  test "fresh role checks prevent stale scopes and member publication without effects", c do
    member_scope = Accounts.Scope.for_user(c.member)
    assert {:error, :unauthorized} = MPTemplates.create(member_scope, "forged")
    assert {:error, :unauthorized} = MPTemplates.list(member_scope)
    {:ok, draft} = MPTemplates.create(c.scope, "role-change")
    {:ok, saved} = MPTemplates.save(c.scope, draft, mp_template_payload())
    assert {:error, :unauthorized} = MPTemplates.publish(member_scope, saved, true)
    c.editor |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = MPTemplates.save(c.scope, saved, mp_template_payload())
    assert {:error, :unauthorized} = MPTemplates.publish(c.scope, saved, true)
    assert Repo.aggregate(Revision, :count) == 2
    assert {:error, :not_found} = MPTemplates.published(saved.slug, "en")
  end

  test "stale reviews, invalid source links and incomplete editions cannot publish", c do
    {:ok, draft} = MPTemplates.create(c.scope, "validation-campaign")
    assert {:error, %Ecto.Changeset{}} = MPTemplates.create(c.scope, "bad/email@example.org")
    assert {:error, %Ecto.Changeset{}} = MPTemplates.create(c.scope, draft.slug)

    for source <- [
          "javascript:alert(1)",
          "data:text/html,unsafe",
          "https://user:secret@example.org",
          "https://example.org/\nunsafe",
          "https://example.org:bad",
          "https://example.org/\0unsafe"
        ] do
      assert {:error, :invalid_content} =
               MPTemplates.save(c.scope, draft, %{mp_template_payload() | "source" => source})
    end

    {:ok, saved} = MPTemplates.save(c.scope, draft, mp_template_payload())
    assert {:error, :stale} = MPTemplates.publish(c.scope, draft, true)
    assert {:error, :stale} = MPTemplates.save(c.scope, draft, mp_template_payload())
    incomplete = put_in(mp_template_payload(), ["editions", "fr", "purpose"], "")
    {:ok, saved} = MPTemplates.save(c.scope, saved, incomplete)
    assert {:error, :invalid_content} = MPTemplates.publish(c.scope, saved, true)
    assert Repo.get!(Template, saved.id).published_revision == nil
  end

  test "published merge variables are controlled and bodies fit the MP sender", c do
    {:ok, template} = MPTemplates.create(c.scope, "controlled-campaign")

    for body <- [String.duplicate("x", 8001), String.duplicate("é", 8001)] do
      payload = put_in(mp_template_payload(), ["editions", "en", "body"], body)
      assert {:error, :invalid_content} = MPTemplates.save(c.scope, template, payload)
    end

    for token <- ["{{other_person}}", "{{unknown123}}", "{{unfinished"] do
      {:ok, template} = MPTemplates.get(c.scope, template.id)
      payload = put_in(mp_template_payload(), ["editions", "en", "body"], token)
      {:ok, saved} = MPTemplates.save(c.scope, template, payload)
      assert {:error, :invalid_content} = MPTemplates.publish(c.scope, saved, true)
      template = saved
      assert template.published_revision == nil
    end

    {:ok, current} = MPTemplates.get(c.scope, template.id)
    body = "Dear {{mp_name}}, please discuss {{district}}. {{sender_name}}, {{postal_code}}."

    {:ok, current} =
      MPTemplates.save(
        c.scope,
        current,
        put_in(mp_template_payload(), ["editions", "en", "body"], body)
      )

    assert {:ok, _} = MPTemplates.publish(c.scope, current, true)
  end

  test "public body rendering sanitizes active markup and never exposes extra draft fields", c do
    payload =
      mp_template_payload()
      |> put_in(
        ["editions", "en", "body"],
        "<script>alert(1)</script>\n\n[Unsafe](javascript:alert(1))"
      )

    payload = Map.put(payload, "private_letter", "PRIVATE-PERSONAL-DRAFT")
    {:ok, template} = MPTemplates.create(c.scope, "safe-campaign")
    {:ok, template} = MPTemplates.save(c.scope, template, payload)
    {:ok, template} = MPTemplates.publish(c.scope, template, true)
    {:ok, public} = MPTemplates.published(template.slug, "en")
    refute public.html =~ "<script>"
    refute public.html =~ "href=\"javascript:"
    refute inspect(public) =~ "PRIVATE-PERSONAL-DRAFT"
    assert {:error, :not_found} = MPTemplates.published(template.slug, "es")
  end
end
