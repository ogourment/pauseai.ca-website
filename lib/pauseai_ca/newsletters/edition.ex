defmodule PauseAiCa.Newsletters.Edition do
  @moduledoc "Evidence-based newsletter language; ambiguous or absent answers remain unknown."
  import Ecto.Query
  alias PauseAiCa.Repo
  alias PauseAiCa.Newsletters.{ConsentEvent, Subscription}

  defmodule Preference do
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: true}
    schema "newsletter_language_preferences" do
      field :email, :string, redact: true
      field :locale, :string
      field :actor_id, :binary_id
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
  end

  def confirm_preference(scope, email, locale) when locale in ["en", "fr", "unknown"] do
    if PauseAiCa.Volunteers.superadmin?(scope) and is_binary(email) and
         Regex.match?(~r/^[^@\s]+@[^@\s]+$/, email) do
      Repo.transaction(fn ->
        Repo.one!(
          from u in PauseAiCa.Accounts.User, where: u.id == ^scope.user.id, lock: "FOR UPDATE"
        )

        if not PauseAiCa.Volunteers.superadmin?(scope), do: Repo.rollback(:unauthorized)

        Repo.insert!(%Preference{
          email: String.downcase(String.trim(email)),
          locale: locale,
          actor_id: scope.user.id
        })
      end)
    else
      {:error, :unauthorized}
    end
  end

  def confirm_preference(_, _, _), do: {:error, :unauthorized}

  def decorate(rows) do
    emails = Enum.map(rows, & &1.email) |> Enum.reject(&is_nil/1)

    preferences =
      Repo.all(
        from p in Preference,
          where: p.email in ^emails,
          order_by: [desc: p.inserted_at, desc: p.id],
          select: {p.email, p.locale}
      )
      |> Enum.reduce(%{}, fn {email, locale}, acc -> Map.put_new(acc, email, locale) end)

    explicit =
      Repo.all(
        from e in ConsentEvent,
          join: s in Subscription,
          on: s.id == e.subscription_id,
          where:
            s.email in ^emails and s.state == "confirmed" and
              e.kind in ["requested", "profile_updated", "language_preference"],
          order_by: [desc: e.inserted_at],
          select: {s.email, e.evidence}
      )
      |> Enum.reduce(%{}, fn {email, evidence}, acc ->
        language = answer(evidence["locale"])
        if language in ["en", "fr"], do: Map.put_new(acc, email, language), else: acc
      end)

    participation =
      Repo.all(
        from r in PauseAiCa.Participation.Request,
          where: r.email in ^emails and r.state == "confirmed" and r.newsletter == true,
          order_by: [desc: r.confirmed_at],
          select: {r.email, r.locale}
      )
      |> Enum.reduce(%{}, fn {email, locale}, acc -> Map.put_new(acc, email, locale) end)

    source =
      Repo.all(
        from c in PauseAiCa.ContactMigration.Contact,
          where: c.email in ^emails,
          select: {c.email, c.source_data}
      )
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {email, data} -> {email, recorded(data)} end)

    Enum.map(rows, fn row ->
      Map.put(
        row,
        :edition,
        preferences[row.email] || explicit[row.email] || participation[row.email] ||
          source[row.email] || "unknown"
      )
    end)
  end

  def select(rows, edition), do: Enum.filter(rows, &(Map.get(&1, :edition, "unknown") == edition))
  def counts(rows), do: Enum.frequencies_by(rows, &Map.get(&1, :edition, "unknown"))
  def locale("en"), do: "en"
  def locale("fr"), do: "fr"
  def locale(_), do: nil

  def recorded(data) do
    case data |> answers() |> Enum.reject(&(&1 == "unknown")) |> Enum.uniq() do
      [language] when language in ["en", "fr"] -> language
      _ -> "unknown"
    end
  end

  defp answers(data) when is_list(data), do: Enum.flat_map(data, &answers/1)

  defp answers(data) when is_map(data) do
    Enum.flat_map(data, fn {key, value} ->
      normalized = key |> to_string() |> String.downcase() |> String.replace(~r/[^a-z]/, "")

      if normalized in ~w(preferredlanguage newsletterlanguage language languages langue langues),
        do: [answer(value)],
        else: if(is_map(value) or is_list(value), do: answers(value), else: [])
    end)
  end

  defp answers(_), do: []

  defp answer(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      value when value in ["en", "english", "anglais"] ->
        "en"

      value when value in ["fr", "french", "français", "francais"] ->
        "fr"

      value ->
        if(
          String.contains?(value, ["english", "anglais"]) and
            String.contains?(value, ["french", "français", "francais"]),
          do: "ambiguous",
          else: "unknown"
        )
    end
  end

  defp answer([one]), do: answer(one)

  defp answer(value) when is_list(value),
    do:
      if(Enum.any?(value, &(answer(&1) in ["en", "fr", "ambiguous"])),
        do: "ambiguous",
        else: "unknown"
      )

  defp answer(_), do: "unknown"
end
