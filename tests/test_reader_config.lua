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
    local map = vim.fn.maparg(vim.api.nvim_replace_termcodes("<leader>rr", true, false, true), "n", false, true)
    assert.equal("<Plug>(GhostReaderOpen)", map.rhs)
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
    local original_select = vim.ui.select
    vim.notify = function() end
    vim.ui.select = function(items, opts, on_choice)
      assert.equal("Select mode:", opts.prompt)
      on_choice(items[1], 1)
    end

    reader.open("tests/fixtures/sample.txt")

    reader.close()
    bookshelf.open = original_open
    vim.notify = original_notify
    vim.ui.select = original_select

    assert.are.same(cfg, captured_opts)
  end)

  it("opens the book selector when open is called without a path", function()
    local restored = 0
    local started = 0
    local selected = 0
    package.loaded["ghost-reader.session"] = {
      get = function()
        return { visibility = "HARD_HIDDEN" }
      end,
      restore = function()
        restored = restored + 1
        return true
      end,
      configure = function() end,
      start = function()
        started = started + 1
      end,
      stop = function() end,
      toc = function() end,
    }
    package.loaded["ghost-reader.history"] = { load = function() return {} end }
    package.loaded["ghost-reader.keymaps"] = { setup = function() end }

    local reader = require("ghost-reader")
    reader.setup()
    local original_select = vim.ui.select
    vim.ui.select = function(_, _, on_choice)
      selected = selected + 1
      on_choice(nil, nil)
    end
    reader.open()
    vim.ui.select = original_select
    assert.equal(1, selected)
    assert.equal(0, restored)
    assert.equal(0, started)
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
    local original_select = vim.ui.select
    vim.notify = function(msg)
      table.insert(messages, msg)
    end
    vim.ui.select = function(items, opts, on_choice)
      assert.equal("Select mode:", opts.prompt)
      on_choice(items[1], 1)
    end

    reader.open("tests/fixtures/sample.txt")

    reader.close()
    bookshelf.open = original_open
    vim.notify = original_notify
    vim.ui.select = original_select

    for _, msg in ipairs(messages) do
      assert.is_nil(msg:match("sample%.txt"))
      assert.is_nil(msg:match("sample"))
      assert.is_nil(msg:match("tests/fixtures"))
    end
  end)
end)
