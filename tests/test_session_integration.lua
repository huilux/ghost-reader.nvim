local helpers = require("tests.helpers")

describe("session integration", function()
  before_each(function()
    helpers.reset_modules()
  end)

  it("falls back to mirror when overlay is unsupported", function()
    package.loaded["ghost-reader.renderer.overlay"] = {
      supports = function()
        return false
      end,
      start = function()
        return false
      end,
      render = function()
        return true
      end,
      hide = function()
        return true
      end,
      restore = function()
        return true
      end,
      stop = function()
        return true
      end,
      page_size = function()
        return 3
      end,
      segment_count = function()
        return 1
      end,
      segment_text = function(_, text)
        return text
      end,
    }

    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      reader = { renderer = "overlay" },
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local book_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "chapter 1" }, book_path)

    session.configure(cfg)
    assert.is_true(session.start(book_path, "overlay"))
    assert.equal("mirror", session.get().view_name)
    assert.equal("overlay", session.get().mode)
    session.stop()
  end)

  it("dispatches page and chapter navigation and reports eof as false", function()
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = {
            { title = "One", lines = { "a", "b", "c" } },
            { title = "Two", lines = { "d", "e", "f" } },
          },
          toc = {
            { title = "One", index = 1 },
            { title = "Two", index = 2 },
          },
        }
      end,
    }

    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      reader = { visible_blocks = 1 },
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local book_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "placeholder" }, book_path)

    session.configure(cfg)
    assert.is_true(session.start(book_path, "overlay"))
    assert.is_table(session.get())
    assert.is_true(session.dispatch("next_page"))
    assert.is_true(session.dispatch("next_chapter"))
    session.dispatch("next_content")
    session.dispatch("next_content")
    session.dispatch("next_content")
    session.dispatch("next_content")
    assert.is_false(session.dispatch("next_content"))
    session.stop()
  end)

  it("uses toc indices rather than picker ordinals", function()
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = {
            { title = "One", lines = { "a", "b" } },
            { title = "Two", lines = { "c", "d" } },
          },
          toc = {
            { title = "One", index = 1 },
            { title = "Two", index = 2 },
          },
        }
      end,
    }

    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local book_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "placeholder" }, book_path)
    session.configure(cfg)
    assert.is_true(session.start(book_path, "overlay"))
    session.stop()
  end)
end)
