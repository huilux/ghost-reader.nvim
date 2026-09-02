local helpers = require("tests.helpers")
local keymaps = require("ghost-reader.keymaps")
local config = require("ghost-reader.config")

describe("session", function()
  before_each(function()
    helpers.reset_modules()
  end)

  it("tracks lifecycle and visibility without a separate controls state", function()
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
    assert.is_true(session.start(book_path, "mirror"))
    assert.equal("ACTIVE", session.state.lifecycle)
    assert.equal("VISIBLE", session.state.visibility)
    assert.equal("mirror", session.state.mode)
    assert.is_nil(session.state.controls)

    assert.is_true(session.hide("soft"))
    assert.equal("SOFT_HIDDEN", session.state.visibility)
    assert.is_nil(session.state.controls)

    assert.is_true(session.restore())
    assert.is_nil(session.state.controls)

    assert.is_true(session.stop())
    assert.is_nil(session.get())
    assert.equal("IDLE", session.state.lifecycle)
  end)

  it("soft hide calls the active renderer hide and restore redraws the frame", function()
    local hide_calls = 0
    local restore_calls = 0
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = { { title = "One", lines = { "alpha" } } },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    package.loaded["ghost-reader.renderer"] = {
      create = function()
        return {
          start = function() return true end,
          render = function() return true end,
          hide = function()
            hide_calls = hide_calls + 1
            return true
          end,
          restore = function()
            restore_calls = restore_calls + 1
            return true
          end,
          stop = function() return true end,
          page_size = function() return 1 end,
          segment_count = function() return 1 end,
          segment_text = function(_, text) return text end,
        }
      end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })

    session.configure(cfg)
    assert.is_true(session.start(vim.fn.tempname() .. ".txt", "mirror"))
    assert.is_true(session.hide("soft"))
    assert.equal(1, hide_calls)
    assert.equal(0, restore_calls)
    assert.is_true(session.restore())
    assert.equal(1, restore_calls)
    session.stop()
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
    assert.is_true(session.start(good_path, "mirror"))
    local before = session.get()
    assert.is_false(session.start(bad_path, "mirror"))
    assert.equal(before, session.get())
    assert.equal(before.generation, session.get().generation)
    session.stop()
  end)

  it("keeps the active session when renderer creation fails during replacement", function()
    local create_calls = 0
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = { { title = "One", lines = { "a" } } },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    package.loaded["ghost-reader.renderer"] = {
      create = function()
        create_calls = create_calls + 1
        return nil
      end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local good_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "alpha" }, good_path)

    session.configure(cfg)
    assert.is_false(session.start(good_path, "mirror"))
    assert.equal(1, create_calls)
    assert.is_nil(session.get())
  end)

  it("keeps the active session when the first render fails during replacement", function()
    local render_calls = 0
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = { { title = "One", lines = { "a" } } },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    package.loaded["ghost-reader.renderer"] = {
      create = function()
        return {
          start = function() return true end,
          render = function()
            render_calls = render_calls + 1
            return render_calls == 1
          end,
          hide = function() return true end,
          restore = function() return true end,
          stop = function() return true end,
          page_size = function() return 1 end,
          segment_count = function() return 1 end,
          segment_text = function(_, text) return text end,
        }
      end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local first = vim.fn.tempname() .. ".txt"
    local second = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "alpha" }, first)
    vim.fn.writefile({ "beta" }, second)

    session.configure(cfg)
    assert.is_true(session.start(first, "mirror"))
    local before = session.get()
    assert.is_false(session.start(second, "mirror"))
    assert.equal(before, session.get())
    assert.equal(before.generation, session.get().generation)
    assert.is_true(render_calls > 0)
    session.stop()
  end)

  it("replaces repeated sessions by stopping only the previous renderer", function()
    local created = {}
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = { { title = "One", lines = { "a" } } },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    package.loaded["ghost-reader.renderer"] = {
      create = function(_, mode)
        local item = { mode = mode, stops = 0 }
        created[#created + 1] = item
        return {
          render = function() return true end,
          hide = function() return true end,
          restore = function() return true end,
          stop = function() item.stops = item.stops + 1; return true end,
          page_size = function() return 1 end,
          segment_count = function() return 1 end,
          segment_text = function(_, text) return text end,
        }
      end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    session.configure(require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    }))

    assert.is_true(session.start("/tmp/first.txt", "mirror"))
    local first = session.get()
    assert.is_true(session.start("/tmp/second.txt", "statusline"))
    assert.equal(first.generation + 1, session.get().generation)
    assert.equal("statusline", session.get().mode)
    assert.equal(1, created[1].stops)
    assert.equal(0, created[2].stops)

    session.stop()
    assert.equal(1, created[1].stops)
    assert.equal(1, created[2].stops)
  end)

  it("records history only after a successful start", function()
    local history_calls = {}
    package.loaded["ghost-reader.history"] = {
      record = function(path)
        history_calls[#history_calls + 1] = path
      end,
    }
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = { { title = "One", lines = { "a" } } },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local good_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "alpha" }, good_path)

    session.configure(cfg)
    assert.is_true(session.start(good_path, "mirror"))
    assert.same({ good_path }, history_calls)
    session.stop()
  end)

  it("saves progress exactly once on quit pre and stop", function()
    local saves = 0
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = { { title = "One", lines = { "a" } } },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    package.loaded["ghost-reader.reader.progress"] = {
      save = function() saves = saves + 1 end,
      load = function() return nil end,
      show = function() end,
    }
    package.loaded["ghost-reader.session"] = nil
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })

    session.configure(cfg)
    assert.is_true(session.start(vim.fn.tempname() .. ".txt", "mirror"))
    vim.api.nvim_exec_autocmds("QuitPre", { buffer = vim.api.nvim_get_current_buf() })
    assert.equal(1, saves)
  end)

  it("detaches reader mappings on hard hide and reattaches them on restore", function()
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
      attach = function() events[#events + 1] = "attach" end,
      detach = function() events[#events + 1] = "detach" end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })

    session.configure(cfg)
    assert.is_true(session.start(vim.fn.tempname() .. ".txt", "mirror"))
    assert.is_nil(session.get().controls)
    assert.is_true(session.hide("hard"))
    assert.same({ "attach", "detach" }, events)
    assert.is_true(session.restore())
    assert.same({ "attach", "detach", "attach" }, events)
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

  it("rerenders a visible statusline after layout-affecting events", function()
    local renders = 0
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
    package.loaded["ghost-reader.renderer"] = {
      create = function()
        return {
          render = function() renders = renders + 1; return true end,
          hide = function() return true end,
          restore = function() return true end,
          stop = function() return true end,
          page_size = function() return 1 end,
          segment_count = function() return 1 end,
          segment_text = function(_, text) return text end,
        }
      end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    session.configure(require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    }))

    assert.is_true(session.start(vim.fn.tempname() .. ".txt", "statusline"))
    assert.equal(1, renders)
    vim.api.nvim_exec_autocmds("VimResized", {})
    assert.is_truthy(vim.wait(100, function() return renders == 2 end, 5))
    vim.api.nvim_exec_autocmds("OptionSet", { pattern = "laststatus" })
    assert.is_truthy(vim.wait(100, function() return renders == 3 end, 5))

    assert.is_true(session.hide("hard"))
    vim.api.nvim_exec_autocmds("VimResized", {})
    vim.wait(20)
    assert.equal(3, renders)
    session.stop()
  end)

  it("exposes the active renderer segment callbacks in frame rendering", function()
    local segment_calls = { count = 0, text = 0 }
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = {
            { title = "One", lines = { "alpha", "beta" } },
          },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    package.loaded["ghost-reader.renderer.mirror"] = {
      start = function() return true end,
      render = function() return true end,
      hide = function() return true end,
      restore = function() return true end,
      stop = function() return true end,
      page_size = function() return 2 end,
      segment_count = function(_, text) segment_calls.count = segment_calls.count + 1; return #text end,
      segment_text = function(_, text, idx) segment_calls.text = segment_calls.text + 1; return string.sub(text, idx, idx) end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    session.configure(cfg)
    assert.is_true(session.start(vim.fn.tempname() .. ".txt", "mirror"))
    assert.is_truthy(segment_calls.count > 0)
    assert.is_truthy(segment_calls.text > 0)
    session.stop()
  end)

  it("does not confuse a global mapping for a previous buffer-local mapping", function()
    local function maparg_in_buf(buf, lhs)
      return vim.api.nvim_buf_call(buf, function()
        return vim.fn.maparg(lhs, "n", false, true)
      end)
    end
    local buf = helpers.new_normal_buffer({ "one" })
    vim.keymap.set("n", "j", "gj", { desc = "global user j" })
    local session = { mode = "mirror" }
    keymaps.attach(session, config.setup(), buf)
    keymaps.detach(session)
    local global_map = vim.fn.maparg("j", "n", false, true)
    assert.equal("gj", global_map.rhs)
    assert.equal("global user j", global_map.desc)
    assert.same({}, vim.api.nvim_buf_get_keymap(buf, "n"))
  end)
end)
