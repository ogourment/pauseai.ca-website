defmodule PauseAiCa.CryptoRedactionTest do
  use ExUnit.Case, async: true

  test "malformed verification tokens cannot expose the signing key in errors" do
    signing_key = String.duplicate("FixtureKeyMustStayPrivate", 4)

    diagnostic =
      try do
        inspect(Plug.Crypto.verify(signing_key, "fixture", ["malformed"]))
      rescue
        error -> Exception.format(:error, error, __STACKTRACE__)
      end

    refute String.contains?(diagnostic, signing_key)
  end
end
