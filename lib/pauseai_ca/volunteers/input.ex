defmodule PauseAiCa.Volunteers.Input do
  alias PauseAiCa.ContactMigration.CSV

  @fields ~w(name email postal_code city country group_id notes bio discord_handle signal_number whatsapp_number contact_preference contact_notes availability_hours_per_week skills other_skills application_message)
  @profile_fields ~w(bio city country discord_handle signal_number whatsapp_number contact_preference contact_notes availability_hours_per_week skills other_skills application_message)
  @aliases %{
    "local_group" => "group_id",
    "location" => "city",
    "courriel" => "email",
    "e_mail" => "email",
    "nom" => "name",
    "code_postal" => "postal_code",
    "region" => "group_id",
    "incubator" => "group_id",
    "incubateur" => "group_id",
    "group" => "group_id",
    "groupe" => "group_id",
    "comments" => "notes",
    "commentaires" => "notes",
    "ville" => "city",
    "pays" => "country"
  }

  def fields, do: @fields
  def profile_fields, do: @profile_fields

  def csv(contents) when byte_size(contents) <= 5_000_000 do
    if String.valid?(contents) do
      case CSV.decode(String.trim_leading(contents, "\uFEFF")) do
        {:ok, [headers | rows]} when headers != [] ->
          if length(rows) <= 1000 and Enum.all?(rows, &(length(&1) <= length(headers))) do
            {:ok,
             %{
               headers: headers,
               mapping: Enum.map(headers, &field_for/1),
               rows: Enum.reject(rows, &Enum.all?(&1, fn v -> String.trim(v) == "" end))
             }}
          else
            {:error, :invalid_csv}
          end

        _ ->
          {:error, :invalid_csv}
      end
    else
      {:error, :invalid_csv}
    end
  end

  def csv(_), do: {:error, :invalid_csv}

  def mapped(%{rows: rows}, mapping) do
    active = Enum.reject(mapping, &(&1 == ""))

    if "email" in active and length(active) == length(Enum.uniq(active)) and
         Enum.all?(active, &(&1 in @fields)) do
      {:ok,
       Enum.map(rows, fn values ->
         mapping
         |> Enum.zip(values)
         |> Enum.reject(fn {k, _} -> k == "" end)
         |> Map.new()
         |> normalize()
       end)}
    else
      {:error, :invalid_mapping}
    end
  end

  def paste(value) when is_binary(value) and byte_size(value) <= 5_000_000 do
    rows = value |> String.replace("\r\n", "\n") |> String.split("\n", trim: true)

    if length(rows) <= 1000 do
      {:ok,
       Enum.map(rows, fn row ->
         ~w(name email postal_code group_id notes)
         |> Enum.zip(String.split(row, "\t"))
         |> Map.new()
         |> normalize()
       end)}
    else
      {:error, :invalid_csv}
    end
  end

  def paste(_), do: {:error, :invalid_csv}

  def normalize(attrs) do
    @fields
    |> Map.new(fn key -> {key, clean(attrs[key])} end)
    |> Map.update!("email", &String.downcase/1)
    |> Map.update!("postal_code", &(&1 |> String.upcase() |> String.replace(" ", "")))
    |> Map.put("key", attrs["key"] || Ecto.UUID.generate())
    |> Map.put("selected", attrs["selected"] in [true, "true"])
  end

  def errors(row) do
    %{}
    |> error_if("email", row["email"] == "", :required)
    |> error_if(
      "email",
      row["email"] != "" and not Regex.match?(~r/^[^@,;\s]+@[^@,;\s]+$/, row["email"]),
      :invalid_email
    )
    |> error_if(
      "postal_code",
      row["postal_code"] != "" and
        not Regex.match?(
          ~r/^[ABCEGHJ-NPRSTVXY]\d[ABCEGHJ-NPRSTVWXYZ]\d[ABCEGHJ-NPRSTVWXYZ]\d$/,
          row["postal_code"]
        ),
      :invalid_postal_code
    )
    |> Map.merge(profile_errors(row))
    |> then(fn errors ->
      Enum.reduce(@fields, errors, fn key, acc ->
        error_if(
          acc,
          key,
          String.length(row[key] || "") > if(key == "email", do: 160, else: 4000),
          :too_long
        )
      end)
    end)
  end

  def profile_errors(attrs) do
    hours = attrs["availability_hours_per_week"] || ""
    valid_hours = hours == "" or match?({n, ""} when n >= 0 and n <= 168, Integer.parse(hours))
    preference = attrs["contact_preference"] || ""

    channel =
      %{
        "discord" => "discord_handle",
        "signal" => "signal_number",
        "whatsapp" => "whatsapp_number"
      }[preference]

    %{}
    |> then(fn errors ->
      Enum.reduce(@profile_fields, errors, fn field, acc ->
        error_if(acc, field, String.length(clean(attrs[field])) > 4000, :too_long)
      end)
    end)
    |> error_if(
      "skills",
      match?({:error, _}, parse_skills(attrs["skills"] || "")),
      :invalid_skills
    )
    |> error_if("availability_hours_per_week", not valid_hours, :invalid_hours)
    |> error_if(
      "contact_preference",
      preference not in ["", "email", "discord", "signal", "whatsapp"],
      :invalid_preference
    )
    |> error_if(
      channel || "contact_preference",
      channel != nil and clean(attrs[channel]) == "",
      :required
    )
  end

  def profile(attrs), do: Map.take(normalize(attrs), @profile_fields)

  def profile_details(attrs) do
    {:ok, skills} = parse_skills(attrs["skills"] || "")

    attrs
    |> Map.put("skills", skills)
    |> Map.put(
      "availability_hours_per_week",
      case Integer.parse(attrs["availability_hours_per_week"] || "") do
        {n, ""} -> n
        _ -> nil
      end
    )
  end

  def parse_skills(text) do
    lines = String.split(text, "\n", trim: true)

    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, skills} ->
      case Regex.run(
             ~r/^\s*([^\/:]+)\/([^:]+):\s*(beginner|intermediate|advanced|expert)\s*$/u,
             line
           ) do
        [_, category, name, level] ->
          {:cont,
           {:ok,
            skills ++
              [
                %{
                  "category" => String.trim(category),
                  "name" => String.trim(name),
                  "proficiency" => level
                }
              ]}}

        _ ->
          {:halt, {:error, :invalid_skills}}
      end
    end)
  end

  defp clean(value) when is_binary(value), do: String.trim(value)
  defp clean(_), do: ""
  defp error_if(errors, key, true, reason), do: Map.put(errors, key, reason)
  defp error_if(errors, _key, false, _reason), do: errors

  defp field_for(header) do
    key =
      Regex.replace(~r/([a-z0-9])([A-Z])/, header, "\\1_\\2")
      |> String.normalize(:nfd)
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.downcase()
      |> String.trim()
      |> String.replace(~r/[^a-z0-9]+/, "_")

    key = Map.get(@aliases, key, key)
    if key in @fields, do: key, else: ""
  end
end
