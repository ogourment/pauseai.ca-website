defmodule PauseAiCa.CRM.Grid do
  @moduledoc "Freshly authorized grid projections; private matching IDs never cross to the browser."
  alias PauseAiCa.{CRM, ContactLists, Volunteers}
  @contacts Enum.map(~w(name email city province fsa region), &%{field: &1})
  @lists [%{field: "name"}, %{field: "kind"}, %{field: "revision", type: :number}]

  def contacts(scope, params, payload) do
    with {:ok, _} <- PhoenixDataGrid.Query.normalize(payload, @contacts),
         {:ok, rows} <- CRM.directory_grid_projection(scope, params) do
      PhoenixDataGrid.Page.fetch(rows, payload, @contacts)
    end
  end

  def lists(scope, archived?, payload) do
    with {:ok, lists} <- ContactLists.list(scope, archived?),
         true <- Volunteers.superadmin?(scope) do
      rows =
        Enum.map(lists, fn list ->
          %{
            "id" => list.id,
            "name" => list.name,
            "kind" => if(list.criteria["kind"] == "static", do: "static", else: "dynamic"),
            "revision" => list.revision
          }
        end)

      PhoenixDataGrid.Page.fetch(rows, payload, @lists)
    else
      false -> {:error, :unauthorized}
      error -> error
    end
  end

  def reply(page, id, request_id),
    do: page |> Map.drop([:matched_ids]) |> Map.merge(%{id: id, request_id: request_id})
end
