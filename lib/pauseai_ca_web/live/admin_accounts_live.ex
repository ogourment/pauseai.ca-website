defmodule PauseAiCaWeb.AdminAccountsLive do
  @moduledoc "Compatibility entry point for bookmarked admin account URLs."
  use PauseAiCaWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    query = Map.take(params, ~w(locale page q))
    {:ok, redirect(socket, to: ~p"/manage/accounts?#{query}")}
  end
end
