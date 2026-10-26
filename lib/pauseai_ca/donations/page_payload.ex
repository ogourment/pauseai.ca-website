defmodule PauseAiCa.Donations.PagePayload do
  @moduledoc false
  import Ecto.Changeset

  @fields ~w(title lead brochure_label campaign_heading campaign_body cta_label account_requirement proposal_label unavailable_note interac_heading interac_body recipient_label allocation_heading allocation_note remaining_heading remaining_note gift_label gift_note funding_unknown projection_note remaining_label covered_label toward_label after_gift_label complete_note budget_label gift_invalid)
  @required ~w(title lead cta_label gift_label funding_unknown projection_note gift_invalid)
  @max_minor 9_007_199_254_740_991
  def edition_fields, do: @fields
  def defaults, do: PauseAiCa.Donations.PageDefaults.payload()

  def validate(payload, mode) when mode in [:draft, :publish] do
    errors =
      cond do
        not is_map(payload) ->
          [{"payload", "must be a map"}]

        true ->
          unknown(payload, ~w(currency editions links stages display), "payload") ++
            require_value(payload["currency"] == "CAD", "currency", "must be CAD") ++
            editions(payload["editions"], mode) ++
            links(payload["links"], mode) ++
            stages(payload["stages"], mode) ++ display(payload["display"])
      end

    if errors == [] do
      editions =
        Map.new(payload["editions"], fn {locale, values} ->
          {locale, Map.merge(Map.new(@fields, &{&1, ""}), values)}
        end)

      {:ok, Map.put(payload, "editions", editions)}
    else
      changeset = {%{}, %{payload: :map}} |> change(%{payload: payload})

      {:error,
       Enum.reduce(errors, changeset, fn {path, message}, cs ->
         add_error(cs, :payload, message, path: path)
       end)}
    end
  end

  defp editions(value, mode) when is_map(value) do
    unknown(value, ~w(en fr), "editions") ++
      Enum.flat_map(~w(en fr), fn locale ->
        case value[locale] do
          edition when is_map(edition) ->
            unknown(edition, @fields, "editions.#{locale}") ++
              Enum.flat_map(@fields, fn field ->
                text = Map.get(edition, field, "")
                path = "editions.#{locale}.#{field}"

                cond do
                  not is_binary(text) or not String.valid?(text) ->
                    [{path, "must be text"}]

                  String.length(text) > 20_000 ->
                    [{path, "is too long"}]

                  mode == :publish and field in @required and String.trim(text) == "" ->
                    [{path, "is required for publication"}]

                  true ->
                    []
                end
              end)

          _ ->
            [{"editions.#{locale}", "must be an edition map"}]
        end
      end)
  end

  defp editions(_, _), do: [{"editions", "must contain English and French editions"}]

  defp links(value, mode) when is_map(value) do
    unknown(value, ~w(brochure campaign), "links") ++
      Enum.flat_map(~w(brochure campaign), fn key ->
        url = Map.get(value, key, "")

        cond do
          mode == :draft and url == "" ->
            []

          key == "campaign" ->
            require_value(
              campaign?(url),
              "links.campaign",
              "must be a Manifund project HTTPS URL"
            )

          true ->
            require_value(https?(url), "links.#{key}", "must be a secure HTTPS URL")
        end
      end)
  end

  defp links(_, _), do: [{"links", "must contain brochure and campaign links"}]

  defp stages(value, mode) when is_list(value) and length(value) > 0 and length(value) <= 20 do
    malformed =
      Enum.flat_map(Enum.with_index(value), fn {stage, i} ->
        path = "stages.#{i}"

        if is_map(stage) do
          unknown(stage, ~w(id label_en label_fr target_minor buckets), path) ++
            identifier(stage["id"], path <> ".id") ++
            cost(stage["target_minor"], path <> ".target_minor") ++
            labels(stage, path, mode) ++
            buckets(stage["buckets"], path <> ".buckets", mode) ++
            if(
              mode == :publish and is_list(stage["buckets"]) and
                Enum.all?(stage["buckets"], &(is_map(&1) and is_integer(&1["amount_minor"]))),
              do:
                require_value(
                  Enum.sum(Enum.map(stage["buckets"], & &1["amount_minor"])) ==
                    stage["target_minor"],
                  path,
                  "complete scenario costs must equal its cumulative target"
                ),
              else: []
            )
        else
          [{path, "must be a stage map"}]
        end
      end)

    if malformed == [] do
      ids = Enum.map(value, & &1["id"])
      targets = Enum.map(value, & &1["target_minor"])

      require_value(length(Enum.uniq(ids)) == length(ids), "stages", "must have unique IDs") ++
        require_value(
          Enum.all?(Enum.chunk_every(targets, 2, 1, :discard), fn [a, b] -> a < b end),
          "stages",
          "cumulative targets must strictly increase"
        )
    else
      malformed
    end
  end

  defp stages(_, _), do: [{"stages", "must contain one to twenty stages"}]

  defp buckets(value, path, mode) when is_list(value) and length(value) <= 100 do
    errors =
      Enum.flat_map(Enum.with_index(value), fn {bucket, i} ->
        child = path <> ".#{i}"

        if is_map(bucket),
          do:
            unknown(bucket, ~w(id amount_minor label_en label_fr), child) ++
              identifier(bucket["id"], child <> ".id") ++
              cost(bucket["amount_minor"], child <> ".amount_minor") ++
              labels(bucket, child, mode),
          else: [{child, "must be a bucket map"}]
      end)

    cond do
      errors != [] ->
        errors

      mode == :publish and value == [] ->
        [{path, "must contain a complete cost breakdown"}]

      true ->
        require_value(
          Enum.uniq_by(value, & &1["id"]) == value,
          path,
          "must have unique IDs within the stage"
        )
    end
  end

  defp buckets(_, path, _), do: [{path, "must be a list of at most one hundred buckets"}]

  defp labels(value, path, mode) do
    Enum.flat_map(~w(label_en label_fr), fn key ->
      text = Map.get(value, key, "")

      cond do
        not is_binary(text) or not String.valid?(text) ->
          [{path <> "." <> key, "must be text"}]

        String.length(text) > 500 ->
          [{path <> "." <> key, "is too long"}]

        mode == :publish and String.trim(text) == "" ->
          [{path <> "." <> key, "is required for publication"}]

        true ->
          []
      end
    end)
  end

  defp display(value) when is_map(value) do
    unknown(value, ~w(mode remaining_threshold_percent show_remaining_above), "display") ++
      require_value(
        value["mode"] == "remaining_after_threshold",
        "display.mode",
        "is unsupported"
      ) ++
      require_value(
        is_integer(value["remaining_threshold_percent"]) and
          value["remaining_threshold_percent"] in 0..100,
        "display.remaining_threshold_percent",
        "must be an integer from zero to one hundred"
      ) ++
      require_value(
        is_boolean(value["show_remaining_above"]),
        "display.show_remaining_above",
        "must be a boolean"
      )
  end

  defp display(_), do: [{"display", "must be a display configuration map"}]

  defp cost(value, path),
    do:
      require_value(
        is_integer(value) and value > 0 and value <= @max_minor,
        path,
        "must be positive integer CAD minor units"
      )

  defp identifier(value, path),
    do:
      require_value(
        is_binary(value) and String.valid?(value) and
          String.match?(value, ~r/\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,99}\z/),
        path,
        "must be a stable identifier"
      )

  defp unknown(value, allowed, path),
    do:
      require_value(
        Enum.all?(Map.keys(value), &(&1 in allowed)),
        path,
        "contains unsupported fields"
      )

  defp require_value(true, _, _), do: []
  defp require_value(_, path, message), do: [{path, message}]

  defp campaign?(value) do
    with true <- https?(value),
         {:ok,
          %URI{
            scheme: "https",
            host: "manifund.org",
            path: "/projects/" <> slug,
            userinfo: nil,
            query: nil,
            fragment: nil,
            port: 443
          }} <- URI.new(value),
         true <- slug != "" and String.match?(slug, ~r/\A[a-z0-9-]+\z/) do
      true
    else
      _ -> false
    end
  end

  defp https?(value) when is_binary(value) do
    with true <- String.valid?(value) and not Regex.match?(~r/[\s\x00-\x1f\x7f]/, value),
         {:ok, %URI{scheme: "https", host: host, userinfo: nil}}
         when is_binary(host) and host != "" <- URI.new(value),
         do: true,
         else: (_ -> false)
  end

  defp https?(_), do: false
end
