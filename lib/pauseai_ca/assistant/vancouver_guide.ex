defmodule PauseAiCa.Assistant.VancouverGuide do
  @moduledoc "Host-registered Vancouver city workflow. Saving and preparing drafts remain human actions."
  import Ecto.Query
  alias PauseAiCa.{CRM, Repo}
  alias PauseAiCa.Assistant.CanadianReferences
  alias PauseAiCa.Newsletters.{Drafts, Lists}
  alias PhoenixCRM.{MailingList, MailingListEvent}

  @journey "crm.vancouver_workflow"
  @criteria %{
    "match" => "any",
    "rules" => [%{"field" => "city", "operator" => "equals", "values" => ["Vancouver"]}]
  }

  def journey, do: @journey
  def criteria, do: @criteria

  def registration do
    %{
      controls: %{
        "menu.contacts" => %{"label" => "Contacts", "types" => ["activate_menu_item"]},
        "crm.geography.cities" => %{
          "label" => "Cities",
          "types" => ["focus", "select_options"],
          "options" => ["Vancouver"]
        },
        "menu.contact_lists" => %{"label" => "Lists", "types" => ["activate_menu_item"]},
        "contact_list.name" => %{"label" => "List name", "types" => ["focus"]},
        "contact_list.compose_newsletter" => %{
          "label" => "Compose newsletter",
          "types" => ["focus"]
        }
      },
      journeys: %{
        @journey => %{
          "steps" => [
            %{
              "id" => "open_contacts",
              "actions" => [%{"type" => "activate_menu_item", "control" => "menu.contacts"}]
            },
            %{
              "id" => "choose_vancouver",
              "actions" => [
                %{"type" => "focus", "control" => "crm.geography.cities"},
                %{"type" => "select_options", "control" => "crm.geography.cities"}
              ]
            },
            %{
              "id" => "open_lists",
              "actions" => [%{"type" => "activate_menu_item", "control" => "menu.contact_lists"}]
            },
            %{
              "id" => "save_city_list",
              "actions" => [%{"type" => "focus", "control" => "contact_list.name"}]
            },
            %{
              "id" => "prepare_newsletter_draft",
              "actions" => [%{"type" => "focus", "control" => "contact_list.compose_newsletter"}]
            }
          ]
        }
      }
    }
  end

  def example_plan(manifest) do
    steps = get_in(manifest, ["journeys", @journey, "steps"])

    %{
      "protocol_version" => 1,
      "manifest_digest" => manifest["digest"],
      "journey" => @journey,
      "steps" =>
        put_in(steps, [Access.at(1), "actions", Access.at(1), "arguments"], %{
          "values" => ["Vancouver"]
        })
    }
  end

  def valid_plan?(plan),
    do:
      get_in(plan, ["steps", Access.at(1), "actions", Access.at(1), "arguments", "values"]) == [
        "Vancouver"
      ]

  def initialize(state, scope) do
    rows = Repo.all(from l in MailingList, select: {l.id, l.revision}, limit: 1_001)

    drafts =
      Repo.all(
        from d in PauseAiCa.Newsletters.Draft,
          where: d.owner_id == ^scope.user.id,
          select: d.id,
          limit: 1_001
      )

    if length(rows) <= 1_000 && length(drafts) <= 1_000,
      do:
        {:ok,
         Map.put(state, :vancouver, %{
           baseline: Map.new(rows),
           baseline_drafts: drafts,
           list_id: nil,
           list_revision: nil,
           draft_id: nil
         })},
      else: {:error, :guide_unavailable}
  end

  def command(state, token, step, locale) do
    target =
      case state.index do
        0 -> "manage-menu-navigation-pauseai.contacts"
        1 -> "crm-cities"
        2 -> "manage-menu-navigation-pauseai.contact_lists"
        3 -> "list_name"
        4 -> "contact-list-compose-newsletter"
      end

    actions =
      Enum.map(step["actions"], fn action ->
        %{
          type: action["type"],
          target_id: target,
          values: get_in(action, ["arguments", "values"])
        }
      end)

    %{
      token: token,
      actions: actions,
      expected_path: if(state.index < 2, do: "/admin/contacts", else: "/manage/lists"),
      locale: locale,
      human_step: state.index >= 3
    }
  end

  # Observations are constructed by server handlers from their current route and IDs.
  # This verifier re-reads resources; caller-supplied counts/criteria never authorize a step.
  def verify(scope, state, data, locale) do
    cond do
      state.index < 2 ->
        verify_contacts(scope, state, data, locale)

      state.index == 2 ->
        if valid_route?(data["url"], "/manage/lists", locale), do: {:ok, state, 0}, else: :error

      state.index == 3 ->
        verify_list(scope, state, data, locale)

      state.index == 4 ->
        verify_draft(scope, state, data, locale)

      true ->
        :error
    end
  rescue
    _ -> :error
  end

  defp verify_contacts(scope, state, data, locale) do
    parsed = URI.parse(data["url"])
    params = Plug.Conn.Query.decode(parsed.query || "")
    expected = if state.index == 0, do: [], else: ["Vancouver"]

    with true <- parsed.path == "/admin/contacts" && params["locale"] == locale,
         true <- Enum.all?(Map.keys(params), &(&1 in ~w(locale page per q region cities))),
         true <- params["page"] in [nil, "1"],
         {:ok, page} <- CRM.directory_page(scope, params),
         true <- page.q == "" && page.region == "",
         filters <- page.geography_filters,
         true <- filters["cities"] == expected && filters["unknown"] == "false",
         true <- Enum.all?(~w(provinces fsas areas), &(filters[&1] == [])),
         true <- data["filters"] == filters do
      {:ok, state, page.total}
    else
      _ -> :error
    end
  end

  defp verify_list(scope, state, data, locale) do
    if valid_route?(data["url"], "/manage/lists", locale) do
      if is_nil(data["list_id"]) do
        :waiting
      else
        with {:ok, list} <- current_city_list(scope, data["list_id"]),
             true <- data["list_revision"] == list.revision,
             true <- list.revision > Map.get(state.vancouver.baseline, list.id, 0),
             true <-
               Repo.exists?(
                 from e in MailingListEvent,
                   where:
                     e.list_id == ^list.id and e.revision == ^list.revision and
                       e.actor_id == ^scope.user.id and e.action in ["created", "updated"]
               ) do
          {:ok,
           put_in(state, [:vancouver, :list_id], list.id)
           |> put_in([:vancouver, :list_revision], list.revision), 0}
        else
          _ -> :error
        end
      end
    else
      :error
    end
  end

  defp verify_draft(scope, state, data, locale) do
    if is_nil(data["draft_id"]) && valid_route?(data["url"], "/manage/lists", locale) do
      :waiting
    else
      with {:ok, list} <- current_city_list(scope, state.vancouver.list_id),
           true <- list.revision == state.vancouver.list_revision,
           {:ok, draft} <- Drafts.get(scope, data["draft_id"]),
           true <- draft.owner_id == scope.user.id && is_nil(draft.archived_at),
           true <- draft.id not in state.vancouver.baseline_drafts,
           true <- draft.recipient_mode == "list" && draft.mailing_list_id == list.id,
           true <-
             valid_route?(data["url"], "/manage/lists", locale) ||
               valid_route?(data["url"], "/manage/mail/drafts/" <> draft.id, locale) do
        if valid_route?(data["url"], "/manage/lists", locale) do
          {:handoff, state,
           %{
             token: state.token,
             actions: [],
             expected_path: "/manage/mail/drafts/" <> draft.id,
             locale: locale,
             human_step: true
           }}
        else
          {:ok, put_in(state, [:vancouver, :draft_id], draft.id), 0}
        end
      else
        _ -> :error
      end
    end
  end

  defp current_city_list(scope, id) do
    with {:ok, %{archived_at: nil} = list} <- Lists.get(scope, id),
         true <- list.criteria == @criteria,
         do: {:ok, list},
         else: (_ -> {:error, :guide_unavailable})
  end

  defp valid_route?(uri, path, locale) when is_binary(uri) do
    parsed = URI.parse(uri)
    params = Plug.Conn.Query.decode(parsed.query || "")
    draft? = String.starts_with?(path, "/manage/mail/drafts/")
    allowed = if draft?, do: ~w(locale workspace), else: ~w(locale list_id)

    parsed.path == path && params["locale"] == locale &&
      Enum.all?(Map.keys(params), &(&1 in allowed)) &&
      (not draft? || params["workspace"] in [nil, "newsletters"])
  end

  defp valid_route?(_, _, _), do: false

  def reference_digest, do: CanadianReferences.digest()
end
