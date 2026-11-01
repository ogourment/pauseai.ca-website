defmodule PauseAiCa.Outreach.Notification do
  @moduledoc "Consumer reply notification intent; authority and delivery policy stay local."
  use PhoenixCRM.ReplyNotificationSchema,
    table: "outreach_reply_notifications",
    actor_id_type: :binary_id
end
