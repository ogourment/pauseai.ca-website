defmodule PauseAiCaWeb.PageControllerTest do
  use PauseAiCaWeb.ConnCase

  test "GET / renders English by default", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "How far should we let AI advance?"
  end

  test "the legacy Montreal page permanently redirects to the English home page", %{conn: conn} do
    conn = get(conn, "/en/montreal.html")

    assert conn.status == 301
    assert redirected_to(conn, 301) == "/en"
  end

  test "unknown browser pages redirect home with a localized flash", %{conn: conn} do
    en_conn = get(conn, "/en/no-such-page")
    assert redirected_to(en_conn) == "/en"

    assert Phoenix.Flash.get(en_conn.assigns.flash, :error) ==
             "The page you requested could not be found."

    fr_conn = get(recycle(conn), "/fr/page-introuvable")
    assert redirected_to(fr_conn) == "/fr"
    assert Phoenix.Flash.get(fr_conn.assigns.flash, :error) == "La page demandée est introuvable."

    other_conn = get(recycle(conn), "/not-a-page")
    assert redirected_to(other_conn) == "/en"
  end

  test "English and French information paths are available", %{conn: conn} do
    en_html = html_response(get(conn, ~p"/en"), 200)
    assert en_html =~ "How far should we let AI advance?"
    refute en_html =~ "Three questions."
    refute en_html =~ "Your answers stay in this browser"
    refute en_html =~ "Everything remains available"
    refute en_html =~ "From curiosity to capacity"
    refute en_html =~ "Nothing is public"

    fr_html = html_response(get(conn, ~p"/fr"), 200)
    assert fr_html =~ "Jusqu’où devrions-nous laisser l’IA progresser?"
    assert fr_html =~ "Commencez là où vous avez des questions."
    refute fr_html =~ "Explorer les arguments"
    assert fr_html =~ "Créer un compte pour enregistrer votre parcours"
    assert fr_html =~ "Politique de confidentialité"
    assert fr_html =~ ~s(href="/users/register?bookmark=risk")
    refute fr_html =~ "Trois questions."
    refute fr_html =~ "Vos réponses restent dans ce navigateur"
    refute fr_html =~ "Tout reste accessible"
    refute fr_html =~ "De la curiosité à la capacité"
    refute fr_html =~ "Rien n’est public"
  end

  test "privacy pages and durable footer links are available", %{conn: conn} do
    fr_html = html_response(get(conn, ~p"/fr/confidentialite"), 200)
    assert fr_html =~ "Politique de confidentialité"

    home = html_response(get(conn, ~p"/fr"), 200)
    assert home =~ "À propos de PauseAI Canada"
    assert home =~ "Événements à Montréal"
    assert home =~ ~s(href="https://luma.com/pauseaimtl")
    assert home =~ ~s(href="/fr/confidentialite")
    assert home =~ "Source"
    refute home =~ "Pause IA France"

    assert html_response(get(conn, ~p"/en"), 200) =~ "Montréal events"
  end

  test "a signed-in reader gets an authenticated bookmark action", %{conn: conn} do
    user = PauseAiCa.AccountsFixtures.user_fixture()

    html =
      conn
      |> log_in_user(user)
      |> get(~p"/fr")
      |> html_response(200)

    assert html =~ ~s(href="/bookmarks/risk?locale=fr")
    refute html =~ ~s(href="/users/register?bookmark=risk")
  end

  test "authenticated French LiveViews set the Gettext locale", %{conn: conn} do
    user = PauseAiCa.AccountsFixtures.user_fixture()
    conn = log_in_user(conn, user)

    assert html_response(get(conn, ~p"/fr/profil"), 200) =~ "Code postal complet"
    assert html_response(get(conn, ~p"/fr/tableau-de-bord"), 200) =~ "Mon tableau de bord"
  end

  test "strategy and identity are available without leaving either language", %{conn: conn} do
    en_html = html_response(get(conn, ~p"/en/strategy"), 200)
    fr_html = html_response(get(conn, ~p"/fr/strategie"), 200)

    assert en_html =~ ~s(id="engagement-ladder")
    assert fr_html =~ ~s(id="engagement-ladder")
    refute en_html =~ "Proposed engagement ladder"
    refute fr_html =~ "Échelle d'engagement proposée"
    about_en = html_response(get(conn, ~p"/en/about"), 200)
    assert about_en =~ ~s(id="about")
    assert about_en =~ "Join PauseAI Canada"
    assert about_en =~ ~s(href="/en/learn#updates")
    refute about_en =~ "network form"
    assert about_en =~ "https://pauseai.info/"
    assert about_en =~ "https://pauseia.fr/fr"
    assert about_en =~ "https://www.pauseai-us.org/"
    assert html_response(get(conn, ~p"/fr/a-propos"), 200) =~ ~s(id="about")
  end
end
