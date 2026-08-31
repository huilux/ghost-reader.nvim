local parser = require("ghost-reader.bookshelf.parser_md")

describe("parser_md", function()
  local fixture_path = "tests/fixtures/sample.md"
  local h2_only_path = "tests/fixtures/heading_only_h2.md"

  it("parses into chapters by headings", function()
    local book = parser.parse(fixture_path)
    assert.equal(2, #book.chapters)
  end)

  it("extracts chapter titles", function()
    local book = parser.parse(fixture_path)
    assert.equal("Chapter One", book.chapters[1].title)
    assert.equal("Chapter Two", book.chapters[2].title)
  end)

  it("captures heading levels in toc", function()
    local book = parser.parse(fixture_path)
    assert.equal(1, book.toc[1].level)
  end)

  it("preserves content lines", function()
    local book = parser.parse(fixture_path)
    assert.is_truthy(#book.chapters[1].lines > 0)
  end)

  it("handles file with no headings as single chapter", function()
    local path = "tests/fixtures/sample.txt"
    local book = parser.parse(path)
    assert.equal(1, #book.chapters)
  end)

  it("creates an implicit chapter for H2-only input", function()
    local book = parser.parse(h2_only_path)
    assert.equal(1, #book.chapters)
    assert.equal("heading_only_h2.md", book.chapters[1].title)
    assert.is_true(vim.tbl_contains(book.chapters[1].lines, "Content under a level-two heading."))
  end)

  it("keeps every toc index in chapter bounds", function()
    local book = parser.parse(fixture_path)
    for _, entry in ipairs(book.toc) do
      assert.is_true(entry.index >= 1)
      assert.is_true(entry.index <= #book.chapters)
    end
  end)

  it("points a subsection at its containing chapter", function()
    local book = parser.parse(fixture_path)
    assert.equal(1, book.toc[2].index)
  end)
end)
