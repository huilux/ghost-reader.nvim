local parser = require("ghost-reader.bookshelf.parser_txt")

describe("parser_txt", function()
  local fixture_path = "tests/fixtures/sample.txt"

  it("parses file into chapters", function()
    local book = parser.parse(fixture_path)
    assert.is_truthy(book)
    assert.is_truthy(book.chapters)
    assert.equal(3, #book.chapters)
  end)

  it("detects chapter titles by pattern", function()
    local book = parser.parse(fixture_path)
    assert.equal("第一章 开始", book.chapters[1].title)
    assert.equal("第二章 继续", book.chapters[2].title)
  end)

  it("preserves paragraph content", function()
    local book = parser.parse(fixture_path)
    local lines = book.chapters[1].lines
    assert.is_truthy(#lines > 0)
    assert.equal("这是第一章的内容。", lines[1])
  end)

  it("splits by fixed line count when no chapter markers", function()
    local book = parser.parse(fixture_path, { chapter_patterns = {" NEVER_MATCH "} })
    assert.is_truthy(#book.chapters >= 1)
  end)

  it("returns table of contents", function()
    local book = parser.parse(fixture_path)
    assert.is_truthy(book.toc)
    assert.equal(#book.chapters, #book.toc)
  end)

  it("returns empty book for non-existent file", function()
    local book, err = parser.parse("/nonexistent/file.txt")
    assert.is_nil(book)
    assert.matches("file not found", err)
  end)

  it("reports unreadable paths separately from missing files", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir)
    local book, err = parser.parse(dir)
    assert.is_nil(book)
    assert.matches("file unreadable", err)
    vim.fn.delete(dir, "d")
  end)
end)
