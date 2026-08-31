local progress = require("ghost-reader.reader.progress")

describe("progress", function()
  local book = {
    path = "/tmp/hidden-reading/fake/book.epub",
    chapters = {
      { title = "One", lines = { "one", "two" } },
      { title = "Two", lines = { "three" } },
    },
  }

  it("round trips version 2 position", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local config = { paths = { data_dir = dir .. "/" } }
    local position = { chapter_index = 2, line_index = 1, segment_index = 3 }

    progress.save(book, position, config)
    local loaded = progress.load(book, config)

    assert.is_truthy(loaded)
    assert.equal(2, loaded.version)
    assert.same(position, loaded.position)
  end)

  it("ignores unversioned progress", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local data_dir = dir .. "/ghost-reader/data/"
    vim.fn.mkdir(data_dir, "p")
    local hash = require("ghost-reader.utils").file_hash(book.path) or "unknown"
    local path = data_dir .. hash .. ".json"
    local f = assert(io.open(path, "w"))
    f:write(vim.json.encode({
      book_path = book.path,
      chapter_index = 2,
      line_offset = 1,
      last_read = os.time(),
    }))
    f:close()

    local loaded = progress.load(book, { paths = { data_dir = dir .. "/ghost-reader/" } })
    assert.is_nil(loaded)
  end)

  it("shows progress without book identity", function()
    local messages = {}
    local original_notify = vim.notify
    vim.notify = function(msg)
      table.insert(messages, msg)
    end

    progress.show(book, { chapter_index = 2, line_index = 1, segment_index = 1 })

    vim.notify = original_notify

    assert.equal(1, #messages)
    assert.is_truthy(messages[1]:find("Chapter"))
    assert.is_truthy(messages[1]:find("%d+%%"))
    assert.is_nil(messages[1]:find(book.path, 1, true))
    assert.is_nil(messages[1]:find(vim.fn.fnamemodify(book.path, ":t"), 1, true))
  end)
end)
