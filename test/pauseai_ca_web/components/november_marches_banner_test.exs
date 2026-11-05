defmodule PauseAiCaWeb.NovemberMarchesBannerTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias PauseAiCaWeb.NovemberMarchesBanner

  test "both exact event links remain available throughout November 14 local time" do
    html = render_component(&NovemberMarchesBanner.banner/1, now: ~U[2026-11-15 04:59:59Z])
    assert html =~ "https://luma.com/g93q6ksk?tk=EYSylQ"
    assert html =~ "https://luma.com/20vit6m2"
    assert html =~ "2026-11-14"

    refute render_component(&NovemberMarchesBanner.banner/1, now: ~U[2026-11-15 05:00:00Z]) =~
             "november-marches-banner"
  end
end
