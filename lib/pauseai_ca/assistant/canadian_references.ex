defmodule PauseAiCa.Assistant.CanadianReferences do
  @moduledoc "Pinned public geography evidence. No contact data or runtime network lookup."
  alias PhoenixAgentAssistant.Canonical

  @file Path.expand(
          "../../../priv/geography/references/vancouver-postal-candidates.json",
          __DIR__
        )
  @external_resource @file
  @bytes File.read!(@file)
  if byte_size(@bytes) > 8_192, do: raise("Canadian reference exceeds its bounded context")
  @vancouver Jason.decode!(@bytes)
  @digest Canonical.digest(@vancouver)

  def vancouver, do: @vancouver
  def digest, do: @digest

  def context do
    %{"reference_digest" => @digest, "vancouver" => @vancouver}
  end
end
