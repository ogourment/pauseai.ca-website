defmodule PauseAiCaWeb.TextareaLabelTest do
  use ExUnit.Case, async: true
  use Phoenix.Component
  import Phoenix.LiveViewTest
  alias PauseAiCaWeb.CoreComponents

  test "a populated textarea keeps its caption as the associated label" do
    assigns = %{}

    document =
      ~H"""
      <CoreComponents.input
        id="review-letter"
        type="textarea"
        name="letter[body]"
        label="Body"
        value="Existing private letter text"
      />
      """
      |> rendered_to_string()
      |> LazyHTML.from_document()

    label = LazyHTML.query(document, "label[for='review-letter']")
    assert LazyHTML.text(label) == "Body"
    assert Enum.count(LazyHTML.query(label, "textarea")) == 0

    assert LazyHTML.text(LazyHTML.query(document, "textarea#review-letter")) ==
             "Existing private letter text"
  end
end
