defmodule PauseAiCaWeb.ActController do
  @moduledoc """
  Sends someone to PauseAI Global and remembers that they went.

  The Act menu points here rather than straight at pauseai.info. A signed-in
  visitor gets an unconfirmed action recorded on the way out, so the dashboard
  can ask whether they actually joined or signed — we watched them leave, which
  is not the same as watching them finish.

  Anonymous visitors are simply redirected. We do not create a record with
  nobody to attach it to, and we do not make signing in a condition of leaving.
  """

  use PauseAiCaWeb, :controller

  alias PauseAiCa.Audit
  alias PauseAiCa.Engagement

  @destinations %{
    "join" => %{
      action_type: "joined",
      en: "https://pauseai.info/embed/onboarding-form?country=Canada&languages=English",
      fr: "https://pauseia.fr/agir"
    },
    "sign" => %{
      action_type: "signed",
      en: "https://pauseai.info/statement",
      fr: "https://pauseia.fr/agir"
    },
    "actions" => %{
      action_type: nil,
      en: "https://pauseai.info/action",
      fr: "https://pauseia.fr/agir"
    }
  }

  def go(conn, %{"destination" => destination} = params) do
    case Map.fetch(@destinations, destination) do
      {:ok, target} ->
        locale = if params["locale"] == "fr", do: :fr, else: :en
        record(conn, target.action_type, destination)
        redirect(conn, external: Map.fetch!(target, locale))

      :error ->
        conn
        |> put_flash(:error, "Unknown destination.")
        |> redirect(to: ~p"/en")
    end
  end

  # "actions" is a reading page, not something a person completes, so it is
  # tracked but never written to anyone's log.
  defp record(conn, nil, destination) do
    Audit.event(:act_followed, %{destination: destination, recorded: false})
    conn
  end

  defp record(conn, action_type, destination) do
    case conn.assigns[:current_scope] do
      %{user: %{}} = scope ->
        Engagement.create_action(scope, %{
          "action_type" => action_type,
          "happened_on" => Date.utc_today(),
          "confirmed_at" => nil
        })

        Audit.event(:act_followed, %{destination: destination, recorded: true})

      _anonymous ->
        Audit.event(:act_followed, %{destination: destination, recorded: false})
    end

    conn
  end
end
