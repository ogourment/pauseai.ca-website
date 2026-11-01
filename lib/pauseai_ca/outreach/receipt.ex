defmodule PauseAiCa.Outreach.Receipt do
  @moduledoc "Private consumer receipt; raw provider capabilities never leave the consumer database."
  use PhoenixCRM.InboundReceiptSchema, table: "outreach_inbound_receipts"
end
