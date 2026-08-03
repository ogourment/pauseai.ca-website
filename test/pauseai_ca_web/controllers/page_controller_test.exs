defmodule PauseAiCaWeb.PageControllerTest do
  use PauseAiCaWeb.ConnCase

  test "GET / renders English by default", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "How far should we let AI advance?"
  end

  test "English and French information paths are available", %{conn: conn} do
    assert html_response(get(conn, ~p"/en"), 200) =~ "How far should we let AI advance?"

    assert html_response(get(conn, ~p"/fr"), 200) =~
             "Jusqu’où devrions-nous laisser l’IA progresser?"
  end

  test "strategy and identity are available without leaving either language", %{conn: conn} do
    assert html_response(get(conn, ~p"/en/strategy"), 200) =~ ~s(id="engagement-ladder")
    assert html_response(get(conn, ~p"/fr/strategie"), 200) =~ ~s(id="engagement-ladder")
    assert html_response(get(conn, ~p"/en/about"), 200) =~ ~s(id="about")
    assert html_response(get(conn, ~p"/fr/a-propos"), 200) =~ ~s(id="about")
  end
end
