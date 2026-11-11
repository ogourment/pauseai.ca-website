defmodule PauseAiCaWeb.DataGridComponents do
  @moduledoc "PauseAI labels and neutral column definitions for shared data grids."
  use PauseAiCaWeb, :html

  def enabled?, do: Application.get_env(:pauseai_ca, :data_grid_enabled, false)

  def contact_columns do
    [
      %{field: "name", label: gettext("Name"), frozen: true, width: 200},
      %{field: "email", label: gettext("Email"), width: 270},
      %{field: "city", label: gettext("City")},
      %{field: "province", label: gettext("Province")},
      %{
        field: "fsa",
        label: gettext("FSA"),
        description:
          gettext("FSA = the first three characters of a Canadian postal code, for example H2X.")
      },
      %{field: "region", label: gettext("Recorded region")}
    ]
  end

  def list_columns do
    [
      %{field: "name", label: gettext("Name"), frozen: true, width: 260},
      %{
        field: "kind",
        label: gettext("Type"),
        filter_values: %{"static" => gettext("Static"), "dynamic" => gettext("Dynamic")}
      },
      %{field: "revision", label: gettext("Revision"), type: :number}
    ]
  end

  def labels do
    %{
      columns: gettext("Columns"),
      copied: gettext("Selection copied."),
      noRange: gettext("Select cells to copy."),
      copyError: gettext("Unable to copy. Select cells and use your browser copy command."),
      filterLabel: gettext("filter"),
      filter: gettext("Filter…"),
      all: gettext("All"),
      select: gettext("Select"),
      selectAll: gettext("Select this page"),
      empty: gettext("No records match these filters."),
      loading: gettext("Loading…"),
      error: gettext("Unable to load records. Try again."),
      first: gettext("First"),
      previous: gettext("Previous"),
      next: gettext("Next"),
      last: gettext("Last"),
      pageTitle: gettext("Show page"),
      firstTitle: gettext("First page"),
      lastTitle: gettext("Last page"),
      previousTitle: gettext("Previous page"),
      nextTitle: gettext("Next page"),
      showing: gettext("Showing"),
      of: gettext("of"),
      rows: gettext("rows"),
      pages: gettext("pages"),
      pageSize: gettext("Rows per page")
    }
  end

  def storage_key(scope, grid), do: "pauseai:grid:v1:#{scope.user.id}:#{grid}"
end
