defmodule PauseAiCaWeb.RogueGameController do
  use PauseAiCaWeb, :controller
  @external_resource "priv/learning/rogue_episodes.json"
  @episodes "priv/learning/rogue_episodes.json" |> File.read!() |> Jason.decode!()
  def en(conn, _params), do: render_game(conn, :window, "en")
  def fr(conn, _params), do: render_game(conn, :window, "fr")

  def ally(conn, params),
    do: render_game(conn, :ally, if(params["lang"] == "fr", do: "fr", else: "en"))

  defp render_game(conn, template, locale) do
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)
    user = conn.assigns.current_scope && conn.assigns.current_scope.user

    render(conn, template,
      locale: locale,
      page_title: gettext("Rogue agent · game"),
      episodes: Enum.at(@episodes, if(locale == "fr", do: 1, else: 0)),
      account_id: if(user, do: user.id, else: ""),
      saved: if(user, do: user.saved_resources, else: []),
      learn_path: if(locale == "fr", do: "/fr/comprendre", else: "/en/learn")
    )
  end
end
