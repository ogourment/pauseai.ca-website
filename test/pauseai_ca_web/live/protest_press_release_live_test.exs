defmodule PauseAiCaWeb.ProtestPressReleaseLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "the bilingual statement connects the corrected count, quote, sources and recap", %{
    conn: conn
  } do
    {:ok, english, _} = live(conn, "/en/montreal-protest-2026-09-26/press-release")
    assert has_element?(english, "#protest-press-release-page", "around 40")
    assert has_element?(english, "#protest-press-release-page blockquote", "Jeremy Eliosoff")

    assert has_element?(
             english,
             "a[href='https://www.pm.gov.au/media/press-conference-new-york']"
           )

    assert has_element?(english, "a[href='/en/montreal-protest-2026-09-26']", "recap and photos")
    assert has_element?(english, "a[href='/fr/manifestation-montreal-2026-09-26/communique']")

    {:ok, french, _} = live(conn, "/fr/manifestation-montreal-2026-09-26/communique")
    assert has_element?(french, "#protest-press-release-page", "une quarantaine")
    assert has_element?(french, "#protest-press-release-page", "PauseIA Canada")
    assert has_element?(french, "#protest-press-release-page figcaption", "Clara Lacasse")
    assert has_element?(french, "a[href='/fr/manifestation-montreal-2026-09-26']", "compte rendu")

    {:ok, recap, _} = live(conn, "/en/montreal-protest-2026-09-26")

    assert has_element?(
             recap,
             "#protest-press-release[href='/en/montreal-protest-2026-09-26/press-release']"
           )
  end
end
