defmodule PauseAiCa.Accounts.Onboarding do
  @moduledoc "Email-account entry and encrypted, account-bound task continuation."
  import Ecto.Query
  alias PauseAiCa.{Accounts, Engagement, Library, Repo}
  alias PauseAiCa.Accounts.User
  alias PauseAiCa.Engagement.LearningSignal
  alias PauseAiCaWeb.Endpoint

  @salt "onboarding task v1"
  @max_age 14 * 24 * 60 * 60
  @sources ~w(header home_questions resource_bookmark home_footer unknown)
  @questions ~w(risk pause coordination)
  @answers ~w(0 1 2 3 4 5)

  def sources, do: @sources

  def context(params, visitor_id) do
    locale = if params["locale"] == "fr", do: "fr", else: "en"
    bookmark = valid_bookmark(params["bookmark"])

    source =
      case params["from"] do
        "questions" -> "home_questions"
        value when value in @sources -> value
        _ -> if(bookmark, do: "resource_bookmark", else: "unknown")
      end

    %{
      "locale" => locale,
      "source" => source,
      "bookmark" => bookmark,
      "answers" => question_answers(params, visitor_id),
      "visitor_id" => visitor_id,
      "return_to" => safe_return(params["return_to"], locale, bookmark)
    }
  end

  def request(email, context, url_fun) do
    email = if is_binary(email), do: String.trim(email), else: ""

    with :ok <- validate_bound_address(email, context),
         {:ok, user, created?} <- find_or_create(email, context) do
      flow = Phoenix.Token.encrypt(Endpoint, @salt, Map.put(context, "user_id", user.id))

      case Accounts.deliver_login_instructions(user, &url_fun.(&1, flow)) do
        {:ok, _email} -> {:ok, user, created?, flow}
        {:error, _reason} -> {:error, :delivery, user, created?, flow}
      end
    end
  end

  defp validate_bound_address(email, %{"user_id" => id}) do
    case Accounts.get_user_by_email(email) do
      %User{id: ^id} -> :ok
      _ -> {:error, :continuation}
    end
  end

  defp validate_bound_address(_email, _context), do: :ok

  def restore(flow, %User{id: id}) do
    case decode(flow) do
      %{"user_id" => ^id} = context -> context
      _ -> %{}
    end
  end

  # A continuation never authenticates its holder. Resend still requires email
  # entry and a fresh, valid, single-use ownership link.
  def decode(flow) when is_binary(flow) do
    case Phoenix.Token.decrypt(Endpoint, @salt, flow, max_age: @max_age) do
      {:ok, context} when is_map(context) -> context
      _ -> %{}
    end
  end

  def decode(_), do: %{}

  def apply_context(user, context, fallback_visitor_id) do
    if bookmark = context["bookmark"] do
      Accounts.save_resource(user, bookmark)

      Engagement.record_learning_signal(
        context["visitor_id"] || fallback_visitor_id,
        user,
        "resource_bookmarked",
        bookmark
      )
    end

    if context["answers"] not in [nil, %{}],
      do: Accounts.save_belief_answers(Accounts.get_user!(user.id), context["answers"])

    if visitor = context["visitor_id"],
      do: Engagement.associate_learning_visitor(visitor, user.id)

    :ok
  end

  defp find_or_create(email, context) do
    case Accounts.get_user_by_email(email) do
      %User{} = user ->
        {:ok, user, false}

      nil ->
        source = if context["source"] in @sources, do: context["source"], else: "unknown"

        case Accounts.register_user(%{"email" => email}, signup_entry_point: source) do
          {:ok, user} ->
            {:ok, user, true}

          {:error, changeset} ->
            case Accounts.get_user_by_email(email) do
              %User{} = user -> {:ok, user, false}
              nil -> {:error, changeset}
            end
        end
    end
  end

  defp question_answers(params, visitor_id) do
    submitted =
      params |> Map.take(@questions) |> Map.filter(fn {_key, value} -> value in @answers end)

    cond do
      submitted != %{} ->
        submitted

      is_nil(visitor_id) or params["from"] not in ["questions", "home_questions"] ->
        %{}

      true ->
        Repo.all(
          from s in LearningSignal,
            where: s.visitor_id == ^visitor_id and s.kind == "question_answered",
            select: {s.subject, s.value}
        )
        |> Map.new()
        |> Map.filter(fn {key, value} -> key in @questions and value in @answers end)
    end
  end

  defp valid_bookmark(value) when is_binary(value) do
    if Library.resource(value) || value in @questions, do: value
  end

  defp valid_bookmark(_), do: nil

  defp safe_return(value, locale, bookmark) do
    allowed = ~w(/en/dashboard /fr/tableau-de-bord /en/learn /fr/comprendre)

    if value in allowed,
      do: value,
      else:
        if(bookmark,
          do: if(locale == "fr", do: "/fr/comprendre", else: "/en/learn"),
          else: if(locale == "fr", do: "/fr/tableau-de-bord", else: "/en/dashboard")
        )
  end
end
