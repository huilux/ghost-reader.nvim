local bookshelf = require("ghost-reader.bookshelf")

describe("bookshelf", function()
  it("rejects a missing txt file", function()
    local book, err = bookshelf.open("/nonexistent/ghost-reader.txt")
    assert.is_nil(book)
    assert.matches("file not found", err)
  end)

  it("rejects an empty parsed book", function()
    local path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({}, path)
    local book, err = bookshelf.open(path)
    assert.is_nil(book)
    assert.matches("no readable content", err)
    vim.fn.delete(path)
  end)
end)
