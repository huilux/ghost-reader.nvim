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
    assert.equal(session.get().ctx.view_state.mirror.buf, session.get().reader_buf)
    assert.equal("overlay", session.get().mode)
    session.stop()
  end)

  it("moves mirror cursor between reading rows and refreshes at page boundaries", function()
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = {
            { title = "One", lines = { "one", "two", "three", "four" } },
          },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      reader = { renderer = "mirror" },
      buffer = {
        style = "strong",
        strong = { visible_lines = 3, max_consecutive_lines = 1 },
      },
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local target = helpers.new_normal_buffer({ "local value = 1" }, "lua")
    local book_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "one", "two", "three", "four" }, book_path)

    session.configure(cfg)
    assert.is_true(session.start(book_path, "mirror"))
    local current = session.get()
    local rows = current.ctx.view_state.mirror.reader_rows
    assert.equal(rows[1], vim.api.nvim_win_get_cursor(current.target_win)[1])

    assert.is_true(session.dispatch("next_content"))
    assert.equal(rows[2], vim.api.nvim_win_get_cursor(current.target_win)[1])
    assert.is_true(session.dispatch("prev_content"))
    assert.equal(rows[1], vim.api.nvim_win_get_cursor(current.target_win)[1])

    assert.is_true(session.dispatch("next_page"))
    assert.equal(4, session.get().position.line_index)
    local refreshed_rows = current.ctx.view_state.mirror.reader_rows
    local refreshed_line = vim.api.nvim_buf_get_lines(current.ctx.view_state.mirror.buf, refreshed_rows[1] - 1, refreshed_rows[1], false)[1]
    assert.is_truthy(refreshed_line:match("four"))
    session.stop()
    assert.is_true(vim.api.nvim_buf_is_valid(target))
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
            { title = "Two", index = 1 },
          },
        }
      end,
    }

    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      reader = { visible_blocks = 1 },
      buffer = {
        light = { visible_lines = 1, max_consecutive_lines = 1 },
      },
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
    local selected = nil
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
            { title = "Two", index = 1 },
          },
        }
      end,
    }
    vim.ui.select = function(items, _, on_choice)
      selected = items
      on_choice(items[2], 2)
    end

    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local book_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "placeholder" }, book_path)
    session.configure(cfg)
    assert.is_true(session.start(book_path, "overlay"))
    session.toc()
    assert.is_not_nil(selected)
    assert.equal(1, session.get().position.chapter_index)
    session.stop()
  end)

  it("applies overlay autocmd soft and hard hide transitions", function()
    local code_buf = vim.api.nvim_create_buf(false, false)
    vim.bo[code_buf].swapfile = false
    vim.api.nvim_buf_set_name(code_buf, vim.fn.tempname() .. ".lua")
    vim.api.nvim_buf_set_lines(code_buf, 0, -1, false, { "local value = 1" })
    vim.bo[code_buf].filetype = "lua"
    vim.api.nvim_set_current_buf(code_buf)
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local book_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "placeholder" }, book_path)

    session.configure(cfg)
    assert.is_true(session.start(book_path, "overlay"))
    vim.api.nvim_exec_autocmds("InsertEnter", {})
    assert.equal("SOFT_HIDDEN", session.get().visibility)
    vim.api.nvim_exec_autocmds("InsertLeave", {})
    assert.equal("VISIBLE", session.get().visibility)
    vim.api.nvim_exec_autocmds("FocusLost", {})
    assert.equal("HARD_HIDDEN", session.get().visibility)
    session.stop()
  end)

  it("keeps a hard-hidden mirror session hidden across an insert cycle", function()
    local code_buf = helpers.new_normal_buffer({ "local value = 1" }, "lua")
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local book_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "placeholder" }, book_path)

    session.configure(cfg)
    assert.is_true(session.start(book_path, "overlay"))
    assert.equal("mirror", session.get().view_name)
    assert.is_true(session.hide("hard"))
    assert.equal("HARD_HIDDEN", session.get().visibility)

    vim.api.nvim_exec_autocmds("InsertEnter", { buffer = code_buf })
    vim.api.nvim_exec_autocmds("InsertLeave", { buffer = code_buf })

    assert.equal("HARD_HIDDEN", session.get().visibility)
    session.stop()
  end)

  it("moves visible statusline reader mappings to the current buffer", function()
    local function maparg_in_buf(buf, lhs)
      return vim.api.nvim_buf_call(buf, function()
        return vim.fn.maparg(lhs, "n", false, true)
      end)
    end
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local book_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "placeholder" }, book_path)

    local first = helpers.new_normal_buffer({ "one" })
    vim.keymap.set("n", "j", "gj", { buffer = first, desc = "first j" })
    session.configure(cfg)
    assert.is_true(session.start(book_path, "statusline"))
    assert.equal("Ghost Reader: next content", maparg_in_buf(first, "j").desc)

    local second = helpers.new_normal_buffer({ "two" })
    assert.equal("VISIBLE", session.get().visibility)
    assert.equal("gj", maparg_in_buf(first, "j").rhs)
    assert.equal("Ghost Reader: next content", maparg_in_buf(second, "j").desc)

    assert.is_true(session.hide("hard"))
    assert.same({}, maparg_in_buf(second, "j"))
    assert.is_true(session.restore())
    assert.equal("Ghost Reader: next content", maparg_in_buf(second, "j").desc)
    session.stop()
  end)

  it("triggers target-scoped autocmds on the current buffer only", function()
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local first = helpers.new_normal_buffer({ "one" })
    local second = helpers.new_normal_buffer({ "two" })
    vim.api.nvim_set_current_buf(first)
    package.loaded["ghost-reader.renderer.overlay"] = {
      supports = function() return true end,
      start = function() return true end,
      render = function() return true end,
      hide = function() return true end,
      restore = function() return true end,
      stop = function() return true end,
      page_size = function() return 1 end,
      segment_count = function() return 1 end,
      segment_text = function(_, text) return text end,
    }
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
    package.loaded["ghost-reader.renderer"] = nil
    package.loaded["ghost-reader.session"] = nil
    local session = require("ghost-reader.session")

    session.configure(cfg)
    assert.is_true(session.start(vim.fn.tempname() .. ".txt", "overlay"))
    vim.api.nvim_exec_autocmds("BufLeave", { buffer = second })
    assert.equal("VISIBLE", session.get().visibility)
    vim.api.nvim_exec_autocmds("WinLeave", { buffer = second })
    assert.equal("VISIBLE", session.get().visibility)
    vim.api.nvim_exec_autocmds("BufLeave", { buffer = first })
    assert.equal("HARD_HIDDEN", session.get().visibility)
    session.stop()
  end)
end)
