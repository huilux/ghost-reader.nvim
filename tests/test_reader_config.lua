local helpers = require("tests.helpers")
local config = require("ghost-reader.config")

describe("reader config threading", function()
  before_each(function()
    helpers.reset_modules()
  end)

  it("forwards config to bookshelf.open in full-screen mode", function()
    local reader = require("ghost-reader")
    local bookshelf = require("ghost-reader.bookshelf")
    local cfg = config.setup({ paths = { cache_dir = "/tmp/custom-cache/", data_dir = "/tmp/custom-data/" } })
    reader.setup(cfg)
    local original_open = bookshelf.open
    local captured_opts
    bookshelf.open = function(path, opts)
      captured_opts = opts
      return {
        format = "txt",
        path = path,
        chapters = { { title = "Chapter", lines = { "line" } } },
        toc = { { title = "Chapter", level = 1, index = 1 } },
      }
    end

    local original_notify = vim.notify
    vim.notify = function() end

    reader.open("tests/fixtures/sample.txt")

    bookshelf.open = original_open
    vim.notify = original_notify

    assert.are.same(cfg, captured_opts)
  end)

  it("forwards config to bookshelf.open in statusline mode", function()
    local reader = require("ghost-reader")
    local bookshelf = require("ghost-reader.bookshelf")
    local cfg = config.setup({
      paths = { cache_dir = "/tmp/custom-cache/", data_dir = "/tmp/custom-data/" },
    })
    reader.setup(cfg)
    local original_open = bookshelf.open
    local captured_opts
    bookshelf.open = function(path, opts)
      captured_opts = opts
      return {
        format = "txt",
        path = path,
        chapters = { { title = "Chapter", lines = { "line" } } },
        toc = { { title = "Chapter", level = 1, index = 1 } },
      }
    end

    local original_notify = vim.notify
    vim.notify = function() end

    reader.open_statusline("tests/fixtures/sample.txt")

    reader.close()
    bookshelf.open = original_open
    vim.notify = original_notify

    assert.are.same(cfg, captured_opts)
  end)

  it("does not leak the file name in startup notifications", function()
    local reader = require("ghost-reader")
    local bookshelf = require("ghost-reader.bookshelf")
    local cfg = config.setup({ paths = { cache_dir = "/tmp/custom-cache/", data_dir = "/tmp/custom-data/" } })
    reader.setup(cfg)
    local original_open = bookshelf.open
    bookshelf.open = function(path)
      return {
        format = "txt",
        path = path,
        chapters = { { title = "Chapter", lines = { "line" } } },
        toc = { { title = "Chapter", level = 1, index = 1 } },
      }
    end

    local messages = {}
    local original_notify = vim.notify
    vim.notify = function(msg)
      table.insert(messages, msg)
    end

    reader.open("tests/fixtures/sample.txt")

    reader.close()
    bookshelf.open = original_open
    vim.notify = original_notify

    for _, msg in ipairs(messages) do
      assert.is_nil(msg:match("sample%.txt"))
      assert.is_nil(msg:match("sample"))
      assert.is_nil(msg:match("tests/fixtures"))
    end
  end)
end)
