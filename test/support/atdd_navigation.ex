defmodule PauseAiCaWeb.AtddNavigation do
  @moduledoc false

  alias PhoenixTest.Playwright
  alias PlaywrightEx.Frame

  # Follow the visible navigation rather than assuming a formerly expanded row.
  # Signed-in public links are also available in the brand menu at every width.
  def open_public(conn) do
    open_section(conn, if(signed_in?(conn), do: "brand", else: "involvement"))
  end

  def open_section(conn, section) when section in ~w(admin manage account brand involvement) do
    selector = "##{section}-menu"

    {:ok, open?} =
      Frame.evaluate(conn.frame_id,
        expression: "document.querySelector(#{Jason.encode!(selector)})?.open === true",
        timeout: 8_000
      )

    if open?, do: conn, else: Playwright.click(conn, selector <> " > summary")
  end

  def home(conn) do
    if signed_in?(conn) do
      conn
      |> open_section("brand")
      |> Playwright.click("#brand-menu a[href='/en'], #brand-menu a[href='/fr']")
    else
      Playwright.click(conn, "header nav > a:first-child")
    end
  end

  defp signed_in?(conn) do
    {:ok, signed_in?} =
      Frame.evaluate(conn.frame_id,
        expression: "!!document.querySelector('#brand-menu')",
        timeout: 8_000
      )

    signed_in?
  end
end
