local helpers = require("tests.helpers")

local function assert_prepared(ctx)
  assert.is_true(ctx.view_state.mirror.visible)
  assert.is_truthy(next(ctx.view_state.mirror.prepared_by_row or {}))
end

local function assert_no_persistent_marks(buf, namespace)
  assert.equal(0, #vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, {}))
end

describe("session integration", function()
  before_each(function()
    helpers.reset_modules()
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
        layout = {
          region_lines = 4,
          max_blocks_per_region = 1,
          max_lines_per_block = 1,
          min_gap_lines = 1,
          max_total_blocks = 3,
          edge_padding = 0,
        },
      },
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local target = helpers.new_normal_buffer({
      "local value_1 = 1",
      "local value_2 = 2",
      "local value_3 = 3",
      "local value_4 = 4",
      "local value_5 = 5",
      "local value_6 = 6",
      "local value_7 = 7",
      "local value_8 = 8",
      "local value_9 = 9",
      "local value_10 = 10",
      "local value_11 = 11",
      "local value_12 = 12",
    }, "lua")
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
    assert_prepared(current.ctx)
    local refreshed_text = current.ctx.view_state.mirror.prepared_by_row[current.ctx.view_state.mirror.active_row].virt_text[1][1]
    assert.is_truthy(refreshed_text:match("four"))
    session.stop()
    assert.is_true(vim.api.nvim_buf_is_valid(target))
  end)

  it("follows the active file when mirror reading switches buffers", function()
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
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local book_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "one", "two", "three", "four" }, book_path)

    local first = helpers.new_normal_buffer({ "local first = true", "return first" }, "lua")
    local second = helpers.new_normal_buffer({ "local second = true", "return second" }, "lua")
    vim.api.nvim_set_current_buf(first)

    session.configure(cfg)
    assert.is_true(session.start(book_path, "mirror"))
    local current = session.get()
    local namespace = current.ctx.view_state.mirror.namespace
    assert_prepared(current.ctx)
    assert_no_persistent_marks(first, namespace)

    vim.api.nvim_set_current_buf(second)
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = second })

    assert.equal(second, current.target_buf)
    assert.equal(second, current.ctx.target_buf)
    assert.equal(second, vim.api.nvim_win_get_buf(current.target_win))
    assert.equal(1, current.position.line_index)
    assert.equal(second, current.ctx.view_state.mirror.target_buf)
    assert_prepared(current.ctx)
    assert_no_persistent_marks(first, namespace)
    assert_no_persistent_marks(second, namespace)

    assert.is_true(session.hide("hard"))
    assert.equal(second, vim.api.nvim_win_get_buf(current.target_win))
    assert.is_false(current.ctx.view_state.mirror.visible)
    assert_no_persistent_marks(second, namespace)
    assert.is_true(session.restore())
    assert.equal(second, vim.api.nvim_win_get_buf(current.target_win))
    assert_prepared(current.ctx)
    assert_no_persistent_marks(second, namespace)
    assert.is_true(session.hide("hard"))
    assert.equal(second, vim.api.nvim_win_get_buf(current.target_win))
    session.stop()
  end)

  it("hard-hides mirror decorations when entering a special buffer", function()
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = { { title = "One", lines = { "one", "two" } } },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local book_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "one", "two" }, book_path)
    local file = helpers.new_normal_buffer({ "local file = true", "return file" }, "lua")

    session.configure(cfg)
    assert.is_true(session.start(book_path, "mirror"))
    local current = session.get()
    local namespace = current.ctx.view_state.mirror.namespace
    assert_prepared(current.ctx)
    assert_no_persistent_marks(file, namespace)

    local special = vim.api.nvim_create_buf(false, true)
    vim.bo[special].buftype = "nofile"
    vim.api.nvim_set_current_buf(special)
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = special })

    assert.equal(special, vim.api.nvim_get_current_buf())
    assert.equal("HARD_HIDDEN", current.visibility)
    assert.is_false(current.ctx.view_state.mirror.visible)
    assert_no_persistent_marks(file, namespace)
    session.stop()
  end)

  it("suspends mirror decorations only while editing a visible buffer", function()
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = { { title = "One", lines = { "one", "two" } } },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local book_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "one", "two" }, book_path)
    local file = helpers.new_normal_buffer({
      "local value_1 = 1",
      "local value_2 = 2",
      "local value_3 = 3",
      "local value_4 = 4",
    }, "lua")

    session.configure(cfg)
    assert.is_true(session.start(book_path, "mirror"))
    local current = session.get()
    local namespace = current.ctx.view_state.mirror.namespace
    assert_prepared(current.ctx)
    assert_no_persistent_marks(file, namespace)

    vim.api.nvim_exec_autocmds("InsertEnter", { buffer = file })
    assert.is_false(current.ctx.view_state.mirror.visible)
    assert_no_persistent_marks(file, namespace)
    vim.api.nvim_exec_autocmds("InsertLeave", { buffer = file })
    assert_prepared(current.ctx)
    assert_no_persistent_marks(file, namespace)

    assert.is_true(session.hide("hard"))
    vim.api.nvim_exec_autocmds("InsertEnter", { buffer = file })
    vim.api.nvim_exec_autocmds("InsertLeave", { buffer = file })
    assert.is_false(current.ctx.view_state.mirror.visible)
    assert_no_persistent_marks(file, namespace)
    session.stop()
  end)

  it("moves mirror ownership with the active window and cleans migrated buffers", function()
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = { { title = "One", lines = { "one", "two" } } },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local book_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "one", "two" }, book_path)
    local first = helpers.new_normal_buffer({ "local first = true", "return first" }, "lua")
    local second = vim.api.nvim_create_buf(true, false)
    vim.bo[second].swapfile = false
    vim.api.nvim_buf_set_lines(second, 0, -1, false, { "local second = true", "return second" })
    vim.bo[second].filetype = "lua"
    local first_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_buf(first)
    local second_win = vim.api.nvim_open_win(second, false, {
      relative = "editor",
      width = 40,
      height = 8,
      row = 1,
      col = 1,
      style = "minimal",
    })

    session.configure(cfg)
    assert.is_true(session.start(book_path, "mirror"))
    local current = session.get()
    local namespace = current.ctx.view_state.mirror.namespace
    assert_prepared(current.ctx)
    assert_no_persistent_marks(first, namespace)

    vim.api.nvim_set_current_win(second_win)
    vim.api.nvim_exec_autocmds("WinEnter", {})
    assert.equal(second, current.target_buf)
    assert.equal(second_win, current.target_win)
    assert.equal(second, current.ctx.target_buf)
    assert.equal(second_win, current.ctx.target_win)
    assert.equal(second, current.ctx.view_state.mirror.target_buf)
    assert_prepared(current.ctx)
    assert_no_persistent_marks(first, namespace)
    assert_no_persistent_marks(second, namespace)

    assert.is_true(session.stop())
    assert_no_persistent_marks(first, namespace)
    assert_no_persistent_marks(second, namespace)
    assert.is_true(vim.api.nvim_win_is_valid(first_win))
    assert.is_true(vim.api.nvim_win_is_valid(second_win))
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
      buffer = {
        light = { visible_lines = 1, max_consecutive_lines = 1 },
      },
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local book_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "placeholder" }, book_path)

    session.configure(cfg)
    assert.is_true(session.start(book_path, "mirror"))
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
    assert.is_true(session.start(book_path, "mirror"))
    session.toc()
    assert.is_not_nil(selected)
    assert.equal(1, session.get().position.chapter_index)
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
    assert.is_true(session.start(book_path, "mirror"))
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

end)
