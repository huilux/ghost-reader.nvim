local helpers = require("tests.helpers")

describe("session", function()
  before_each(function()
    helpers.reset_modules()
  end)

  it("tracks lifecycle, visibility, and controls for an opened overlay session", function()
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = {
        cache_dir = root .. "-cache/",
        data_dir = root .. "-data/",
      },
    })

    local buf = helpers.new_normal_buffer({ "one", "two", "three" })
    local book_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "alpha", "", "beta" }, book_path)
    package.loaded["ghost-reader.bookshelf"] = {
      open = function()
        return {
          path = book_path,
          format = "txt",
          chapters = {
            { title = "Chapter 1", lines = { "alpha", "beta" } },
          },
          toc = { { title = "Chapter 1" } },
        }
      end,
    }

    assert.same(cfg, session.configure(cfg))
    assert.is_true(session.start(book_path, "overlay"))
    assert.equal("ACTIVE", session.state.lifecycle)
    assert.equal("VISIBLE", session.state.visibility)
    assert.equal("overlay", session.state.mode)

    assert.is_true(session.hide("soft"))
    assert.equal("SOFT_HIDDEN", session.state.visibility)
    assert.is_truthy(session.state.controls)

    assert.is_true(session.restore())
    assert.equal("VISIBLE", session.state.visibility)
    assert.equal("ACTIVE", session.state.controls)

    assert.is_true(session.stop())
    assert.is_nil(session.get())
    assert.equal("IDLE", session.state.lifecycle)
  end)

  it("exposes the lifecycle API surface", function()
    local session = require("ghost-reader.session")
    assert.is_function(session.configure)
    assert.is_function(session.start)
    assert.is_function(session.get)
    assert.is_function(session.hide)
    assert.is_function(session.stop)
    assert.is_function(session.dispatch)
    assert.is_function(session._reset_for_tests)
  end)

  it("keeps the active session when a replacement book fails to parse", function()
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = {
        cache_dir = root .. "-cache/",
        data_dir = root .. "-data/",
      },
    })
    local good_path = vim.fn.tempname() .. ".txt"
    local bad_path = "/definitely-missing/ghost-reader.txt"
    vim.fn.writefile({ "alpha" }, good_path)

    session.configure(cfg)
    assert.is_true(session.start(good_path, "overlay"))
    local before = session.get()
    assert.is_false(session.start(bad_path, "overlay"))
    assert.equal(before, session.get())
    assert.equal(before.generation, session.get().generation)
    session.stop()
  end)

  it("hard hide leaves controls before hiding and restore re-enters them for overlay", function()
    local events = {}
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = { { title = "One", lines = { "a", "b" } } },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    package.loaded["ghost-reader.keymaps"] = {
      enter_controls = function() events[#events + 1] = "enter" end,
      leave_controls = function() events[#events + 1] = "leave" end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })

    session.configure(cfg)
    assert.is_true(session.start(vim.fn.tempname() .. ".txt", "overlay"))
    assert.is_true(session.toggle_controls())
    assert.is_true(session.hide("hard"))
    assert.same({ "leave", "enter", "leave" }, events)
    assert.is_true(session.restore())
    assert.equal("ACTIVE", session.get().controls)
    assert.same({ "leave", "enter", "leave", "leave", "enter" }, events)
    session.stop()
  end)

  it("dispatches renderer speed actions only in statusline mode", function()
    local calls = {}
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = { { title = "One", lines = { "a", "b" } } },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    package.loaded["ghost-reader.renderer.statusline"] = {
      supports = function() return true end,
      start = function() return true end,
      render = function() return true end,
      hide = function() return true end,
      restore = function() return true end,
      stop = function() return true end,
      page_size = function() return 1 end,
      segment_count = function() return 1 end,
      segment_text = function() return "x" end,
      toggle_auto = function() calls[#calls + 1] = "toggle"; return true end,
      faster = function() calls[#calls + 1] = "faster"; return true end,
      slower = function() calls[#calls + 1] = "slower"; return true end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })

    session.configure(cfg)
    assert.is_true(session.start(vim.fn.tempname() .. ".txt", "statusline"))
    assert.is_true(session.dispatch("toggle_auto"))
    assert.is_true(session.dispatch("faster"))
    assert.is_true(session.dispatch("slower"))
    assert.same({ "toggle", "faster", "slower" }, calls)
    session.stop()
  end)
end)
