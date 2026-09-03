local parser = require("ghost-reader.bookshelf.parser_epub")

describe("parser_epub", function()
  it("returns error when unzip not available", function()
    local orig = vim.fn.executable
    vim.fn.executable = function() return 0 end
    local book, err = parser.parse("dummy.epub")
    vim.fn.executable = orig
    assert.is_truthy(err)
  end)

  it("returns error for non-existent file", function()
    local book, err = parser.parse("/nonexistent/book.epub")
    assert.is_truthy(err)
  end)

  it("strips HTML tags from content", function()
    assert.equal("Hello World", parser._strip_html("<p>Hello <b>World</b></p>"))
    assert.equal("Title", parser._strip_html("<h1>Title</h1>"))
    assert.equal("line1 line2", parser._strip_html("line1<br/>line2"))
  end)

  it("extracts text preserving paragraph breaks", function()
    local html = "<p>Para one.</p><p>Para two.</p>"
    local lines = parser._html_to_lines(html)
    assert.equal("Para one.", lines[1])
    assert.equal("Para two.", lines[2])
  end)

  it("extracts body text without head metadata", function()
    local html = [[
      <html>
        <head><title>Repeated metadata</title></head>
        <body><p>Chapter title</p><p>Chapter content.</p></body>
      </html>
    ]]

    assert.same({ "Chapter title", "Chapter content." }, parser._html_to_lines(html))
  end)
end)
