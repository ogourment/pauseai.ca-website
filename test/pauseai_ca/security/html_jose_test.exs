defmodule PauseAiCa.Security.HtmlJoseTest do
  use ExUnit.Case, async: true

  test "HTML attributes preserve safe values and reject injected attribute names" do
    assert Phoenix.HTML.safe_to_string(
             Phoenix.HTML.attributes_escape(%{"data-note" => "<review>"})
           ) ==
             " data-note=\"&lt;review&gt;\""

    assert_raise ArgumentError, fn ->
      Phoenix.HTML.attributes_escape(%{"title onmouseover" => "alert(1)"})
    end
  end

  test "ECDSA accepts a valid signature and rejects zero-padded signature malleability" do
    key = JOSE.JWK.generate_key({:ec, :secp256r1})
    public_key = JOSE.JWK.to_public(key)
    signed = JOSE.JWS.sign(key, "security regression", %{"alg" => "ES256"})
    {modules, fields} = signed
    signature = Base.url_decode64!(fields["signature"], padding: false)
    <<r::binary-size(32), s::binary-size(32)>> = signature
    padded = Base.url_encode64(<<0, r::binary, 0, s::binary>>, padding: false)

    assert {true, "security regression", _} = JOSE.JWS.verify(public_key, signed)

    assert {false, _, _} =
             JOSE.JWS.verify(public_key, {modules, Map.put(fields, "signature", padded)})
  end
end
