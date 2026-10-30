defmodule PauseAiCa.Blog.MarkdownTest do
  use ExUnit.Case, async: true
  alias PauseAiCa.Blog.Markdown

  test "heading AST yields nested siblings, stable unique anchors and an always visible introduction" do
    edition = %{
      "markdown" => """
      # A **Markdown** title

      Introduction with [source](https://example.org).

      ## First

      Top body.

      ### Nested

      Child body.

      ## First

      Another body.

      ## First-2

      Last body.
      """
    }

    document = Markdown.document(edition)
    assert document.title == "A Markdown title"
    assert document.intro =~ "https://example.org"
    assert Enum.map(document.sections, & &1.id) == ["first", "first-2", "first-2-2"]
    assert [%{title: "Nested", html: child}] = hd(document.sections).sections
    assert child =~ "Child body."
    assert Markdown.document(edition) == document
  end

  test "fenced code and quoted headings are content, and setext headings form sections" do
    document =
      Markdown.document(%{
        "markdown" => """
        # Title

        Intro.

        ```markdown
        ## Code heading
        ```

        > ## Quoted heading

        Real section
        ------------

        Body.
        """
      })

    assert document.intro =~ "## Code heading"
    assert document.intro =~ "Quoted heading"
    assert [%{title: "Real section", sections: []}] = document.sections
  end

  test "reference links defined in another section retain their destination" do
    document =
      Markdown.document(%{
        "markdown" =>
          "# Title\n\n[Intro source][evidence].\n\n## Sources\n\n[Section source][evidence].\n\n[evidence]: https://example.org/report \"Report\"\n\n[^note]: Footnote-shaped source text.\n"
      })

    assert document.intro =~ "href=\"https://example.org/report\""
    assert hd(document.sections).html =~ "href=\"https://example.org/report\""
    # The existing safe renderer uses CommonMark, without the footnote extension.
    # Footnote-shaped text stays ordinary content rather than gaining broken anchors.
    assert hd(document.sections).html =~ "Footnote-shaped source text."
    refute hd(document.sections).html =~ "href=\"#fn"

    legacy = %{
      "title" => "Ancien",
      "summary" => "Introduction",
      "details" => "Détail.",
      "full" => "Fin."
    }

    assert Enum.map(Markdown.document(legacy, "fr").sections, & &1.title) == [
             "Détails",
             "Article complet"
           ]
  end

  test "article body and heading text cannot create executable markup" do
    document =
      Markdown.document(%{
        "markdown" => """
        # <script>alert(1)</script>

        <img src=x onerror=alert(2)>

        ## Unsafe

        [bad](javascript:alert(3))
        <script>alert(4)</script>
        """
      })

    refute document.intro =~ "<img"
    html = hd(document.sections).html
    refute html =~ "<script>"
    refute html =~ "href=\"javascript:"
  end

  test "conversion closes each legacy field independently without swallowing later sections" do
    legacy = %{
      "title" => "Old article",
      "summary" => "Original introduction.",
      "details" => "```markdown\n## This is code\nUnclosed code sample.",
      "full" =>
        "Full explanation with [source][reference].\n\n[reference]: https://example.org/full"
    }

    converted = Markdown.edition(legacy)
    document = Markdown.document(converted)
    assert [%{title: "Details"} = details, %{title: "Full article"} = full] = document.sections
    assert details.sections == []
    assert details.html =~ "<code"
    assert details.html =~ "## This is code"
    refute details.html =~ "Full explanation"
    assert full.html =~ "Full explanation"
    assert full.html =~ "href=\"https://example.org/full\""
    assert legacy["details"] == "```markdown\n## This is code\nUnclosed code sample."
    assert Markdown.edition(converted) == converted
  end

  test "legacy conversion preserves all authored text, is idempotent, and leaves originals intact" do
    legacy = %{
      "title" => "A *literal* title",
      "summary" => "Plain <text> and **stars**",
      "details" => "## Existing\n\n```\n# code\n```",
      "full" => "Last paragraph.\n"
    }

    converted = Markdown.edition(legacy)
    assert Map.keys(converted) == ["markdown"]
    assert converted["markdown"] =~ "# code"
    assert String.ends_with?(String.trim(converted["markdown"]), String.trim(legacy["full"]))
    assert Markdown.document(converted).title == legacy["title"]
    assert Markdown.document(converted).intro =~ "&lt;text&gt;"
    assert Markdown.edition(converted) == converted
    assert legacy["summary"] == "Plain <text> and **stars**"

    assert Markdown.edition(Map.new(~w(title summary details full), &{&1, ""})) == %{
             "markdown" => ""
           }
  end
end
