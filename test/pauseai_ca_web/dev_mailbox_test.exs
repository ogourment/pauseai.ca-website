defmodule PauseAiCaWeb.DevMailboxTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "review mailbox shortcut requires an explicit isolated local sink and stays absent in production" do
    keys = [:mail_environment, :dev_review_mailbox, PauseAiCa.Mailer]
    previous = Map.new(keys, &{&1, Application.get_env(:pauseai_ca, &1)})

    on_exit(fn ->
      Enum.each(previous, fn {key, value} -> Application.put_env(:pauseai_ca, key, value) end)
    end)

    Application.put_env(:pauseai_ca, :dev_review_mailbox, true)
    Application.put_env(:pauseai_ca, PauseAiCa.Mailer, adapter: Swoosh.Adapters.Local)
    Application.put_env(:pauseai_ca, :mail_environment, :dev)

    assert render_component(&PauseAiCaWeb.CoreComponents.dev_mailbox_link/1, %{}) =~
             "/dev/mailbox"

    Application.put_env(:pauseai_ca, :mail_environment, :production)

    refute render_component(&PauseAiCaWeb.CoreComponents.dev_mailbox_link/1, %{}) =~
             "/dev/mailbox"

    Application.put_env(:pauseai_ca, :mail_environment, :dev)
    Application.put_env(:pauseai_ca, PauseAiCa.Mailer, adapter: Swoosh.Adapters.Test)

    refute render_component(&PauseAiCaWeb.CoreComponents.dev_mailbox_link/1, %{}) =~
             "/dev/mailbox"
  end
end
