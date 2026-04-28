local parser = require("ghost-reader.bookshelf.parser_md")

describe("parser_md", function()
  local fixture_path = "tests/fixtures/sample.md"

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
end)
