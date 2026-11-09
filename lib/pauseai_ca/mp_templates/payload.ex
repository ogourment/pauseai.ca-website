defmodule PauseAiCa.MPTemplates.Payload do
  @moduledoc false
  @fields ~w(title purpose subject body)
  @variables ~w(mp_name district sender_name postal_code)
  def variables, do: @variables
  @limits %{"title" => 160, "purpose" => 3000, "subject" => 200, "body" => 24_000}

  def empty do
    %{
      "author" => "",
      "source" => "",
      "editions" => Map.new(~w(en fr), &{&1, Map.new(@fields, fn key -> {key, ""} end)})
    }
  end

  def normalize(payload) when is_map(payload) do
    editions = if is_map(payload["editions"]), do: payload["editions"], else: %{}

    %{
      "author" => text(payload["author"]),
      "source" => text(payload["source"]),
      "editions" =>
        Map.new(~w(en fr), fn locale ->
          values = Map.get(editions, locale)

          {locale,
           Map.new(@fields, fn key ->
             {key, if(is_map(values), do: text(values[key]), else: "")}
           end)}
        end)
    }
  end

  def normalize(_), do: empty()

  def validate(payload, mode) when is_map(payload) and mode in [:draft, :publish] do
    normalized = normalize(payload)

    valid_editions =
      Enum.all?(~w(en fr), fn locale ->
        Enum.all?(@fields, fn key ->
          text?(normalized["editions"][locale][key], @limits[key], mode)
        end) and String.length(normalized["editions"][locale]["body"]) <= 8000 and
          not String.contains?(normalized["editions"][locale]["subject"], ["\r", "\n"]) and
          (mode == :draft or
             Enum.all?(~w(subject body), &supported_tokens?(normalized["editions"][locale][&1])))
      end)

    if text?(normalized["author"], 200, mode) and text?(normalized["source"], 1000, mode) and
         source?(normalized["source"], mode) and valid_editions,
       do: {:ok, normalized},
       else: {:error, :invalid_content}
  end

  def validate(_, _), do: {:error, :invalid_content}

  defp supported_tokens?(content) do
    values = Map.new(@variables, &{&1, "reviewed"})

    case PhoenixMailWorkflow.Template.merge(content, values) do
      {:ok, merged} -> not String.contains?(merged, ["{{", "}}"])
      _ -> false
    end
  end

  defp text(value) when is_binary(value), do: value
  defp text(_), do: ""

  defp text?(value, limit, mode),
    do:
      is_binary(value) and String.valid?(value) and byte_size(value) <= limit and
        (mode == :draft or String.trim(value) != "")

  defp source?("", :draft), do: true

  defp source?(value, _) when is_binary(value) do
    case URI.new(value) do
      {:ok, %URI{scheme: scheme, host: host, userinfo: nil}}
      when scheme in ["https", "http"] and is_binary(host) and host != "" ->
        not Regex.match?(~r/[\s\x00-\x1f\x7f]/, value)

      _ ->
        false
    end
  end

  defp source?(_, _), do: false
end
