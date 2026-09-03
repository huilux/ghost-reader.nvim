local helpers = require("tests.helpers")

local function assert_prepared(ctx)
  assert.is_true(ctx.view_state.mirror.visible)
  assert.is_truthy(next(ctx.view_state.mirror.prepared_by_row or {}))
end

local function assert_no_persistent_marks(buf, namespace)
  assert.equal(0, #vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, {}))
end

local function screen_text_for_buffer_row(win, row)
  local position = vim.fn.screenpos(win, row, 1)
  assert.is_true(position.row > 0)
  local chars = {}
  for col = 1, vim.o.columns do
    chars[#chars + 1] = vim.fn.screenstring(position.row, col)
  end
  return table.concat(chars)
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

  it("reuses forward batches and builds previous batches from the active block", function()
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = {
            { title = "One", lines = { "one", "two", "three", "four", "five", "six", "seven", "eight" } },
          },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    session.configure(require("ghost-reader.config").setup({
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
    }))
    helpers.new_normal_buffer({ "local a = 1", "local b = 2", "local c = 3", "local d = 4", "local e = 5", "local f = 6", "local g = 7", "local h = 8", "local i = 9", "local j = 10", "local k = 11", "local l = 12" }, "lua")

    assert.is_true(session.start(vim.fn.tempname() .. ".txt", "mirror"))
    local initial_rows = vim.deepcopy(session.get().ctx.view_state.mirror.reader_rows)
    session.dispatch("next_content")
    assert.same(initial_rows, session.get().ctx.view_state.mirror.reader_rows)
    assert.equal(initial_rows[2], vim.api.nvim_win_get_cursor(0)[1])

    session.dispatch("next_content")
    session.dispatch("next_content")
    assert.same(initial_rows, session.get().ctx.view_state.mirror.reader_rows)
    assert.equal(4, session.get().position.line_index)
    assert.equal(initial_rows[1], vim.api.nvim_win_get_cursor(0)[1])

    session.dispatch("prev_content")
    assert.equal(3, session.get().position.line_index)
    assert.equal(initial_rows[#initial_rows], vim.api.nvim_win_get_cursor(0)[1])
    session.stop()
  end)

  it("rebuilds mirror batches for explicit chapter navigation", function()
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = {
            { title = "One", lines = { "one" } },
            { title = "Two", lines = { "two-a", "two-b", "two-c" } },
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
    session.configure(require("ghost-reader.config").setup({
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
    }))
    helpers.new_normal_buffer({
      "local a = 1", "local b = 2", "local c = 3", "local d = 4",
      "local e = 5", "local f = 6", "local g = 7", "local h = 8",
      "local i = 9", "local j = 10", "local k = 11", "local l = 12",
    }, "lua")

    assert.is_true(session.start(vim.fn.tempname() .. ".txt", "mirror"))
    local current = session.get()
    local mirror_state = current.ctx.view_state.mirror
    local rows = vim.deepcopy(mirror_state.reader_rows)
    local initial_batch = mirror_state.rendered_by_key
    assert.is_truthy(initial_batch["2:1:1"])

    assert.is_true(session.dispatch("next_content"))
    assert.equal(2, current.position.chapter_index)
    assert.equal(initial_batch, mirror_state.rendered_by_key)

    assert.is_true(session.dispatch("prev_chapter"))
    assert.equal(1, current.position.chapter_index)
    assert.is_not.equal(initial_batch, mirror_state.rendered_by_key)
    assert.same(rows, mirror_state.reader_rows)

    local previous_batch = mirror_state.rendered_by_key
    assert.is_true(session.dispatch("next_chapter"))
    assert.equal(2, current.position.chapter_index)
    assert.is_not.equal(previous_batch, mirror_state.rendered_by_key)
    assert.is_nil(mirror_state.rendered_by_key["1:1:1"])
    assert.is_truthy(mirror_state.rendered_by_key["2:1:1"])
    assert.same(rows, mirror_state.reader_rows)
    session.stop()
  end)

  it("redraws every visible mirror block immediately after chapter navigation", function()
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = {
            { title = "One", lines = { "old-a", "old-b", "old-c" } },
            { title = "Two", lines = { "fresh-a", "fresh-b", "fresh-c" } },
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
    session.configure(require("ghost-reader.config").setup({
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
    }))
    helpers.new_normal_buffer({
      "local a = 1", "local b = 2", "local c = 3", "local d = 4",
      "local e = 5", "local f = 6", "local g = 7", "local h = 8",
      "local i = 9", "local j = 10", "local k = 11", "local l = 12",
    }, "lua")

    assert.is_true(session.start(vim.fn.tempname() .. ".txt", "mirror"))
    vim.cmd("redraw!")
    local current = session.get()
    local rows = vim.deepcopy(current.ctx.view_state.mirror.reader_rows)
    assert.equal(3, #rows)
    for index, expected in ipairs({ "old-a", "old-b", "old-c" }) do
      assert.is_truthy(screen_text_for_buffer_row(current.target_win, rows[index]):find(expected, 1, true))
    end

    assert.is_true(session.dispatch("next_chapter"))
    assert.equal(2, current.position.chapter_index)
    assert.same(rows, current.ctx.view_state.mirror.reader_rows)
    for index, expected in ipairs({ "fresh-a", "fresh-b", "fresh-c" }) do
      assert.is_truthy(screen_text_for_buffer_row(current.target_win, rows[index]):find(expected, 1, true))
    end
    session.stop()
  end)

  it("restores each code view after hiding and migrating the mirror", function()
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = { { title = "One", lines = { "one", "two", "three", "four", "five", "six" } } },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    session.configure(require("ghost-reader.config").setup({
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    }))
    local first = helpers.new_normal_buffer({ "local first_1 = 1", "local first_2 = 2", "local first_3 = 3", "local first_4 = 4", "local first_5 = 5", "local first_6 = 6" }, "lua")
    local extra_first_lines = {}
    for index = 7, 80 do extra_first_lines[#extra_first_lines + 1] = "local first_" .. index .. " = " .. index end
    vim.api.nvim_buf_set_lines(first, -1, -1, false, extra_first_lines)
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    vim.fn.winrestview({ topline = 2, lnum = 4, col = 0, curswant = 0 })
    local first_view = vim.fn.winsaveview()

    assert.is_true(session.start(vim.fn.tempname() .. ".txt", "mirror"))
    session.dispatch("next_page")
    assert.is_true(session.hide("hard"))
    assert.same(first_view, vim.fn.winsaveview())

    vim.api.nvim_win_set_cursor(0, { 40, 0 })
    vim.fn.winrestview({ topline = 25, lnum = 40, col = 0, curswant = 0 })
    vim.cmd("redraw!")
    local moved_first_view = vim.fn.winsaveview()
    assert.is_true(session.restore())

    local first_win = vim.api.nvim_get_current_win()
    local second = vim.api.nvim_create_buf(true, false)
    vim.bo[second].swapfile = false
    vim.bo[second].filetype = "lua"
    vim.api.nvim_buf_set_lines(second, 0, -1, false, { "local second_1 = 1", "local second_2 = 2", "local second_3 = 3", "local second_4 = 4", "local second_5 = 5", "local second_6 = 6" })
    local extra_second_lines = {}
    for index = 7, 80 do extra_second_lines[#extra_second_lines + 1] = "local second_" .. index .. " = " .. index end
    vim.api.nvim_buf_set_lines(second, -1, -1, false, extra_second_lines)
    local second_win = vim.api.nvim_open_win(second, false, {
      relative = "editor", width = 40, height = 6, row = 1, col = 1, style = "minimal",
    })
    vim.api.nvim_win_set_cursor(second_win, { 40, 0 })
    vim.api.nvim_win_call(second_win, function()
      vim.fn.winrestview({ topline = 35, lnum = 40, col = 0, curswant = 0 })
      vim.cmd("redraw")
    end)
    local second_view = vim.api.nvim_win_call(second_win, vim.fn.winsaveview)
    vim.api.nvim_set_current_win(second_win)
    vim.api.nvim_exec_autocmds("WinEnter", {})
    assert.same(moved_first_view, vim.api.nvim_win_call(first_win, vim.fn.winsaveview))
    assert.is_true(session.hide("hard"))
    assert.same(second_view, vim.api.nvim_win_call(second_win, vim.fn.winsaveview))
    session.stop()
  end)

  it("suspends the mirror for edits and reflows it after a resize", function()
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = { { title = "One", lines = { "long text that will wrap after the window width changes", "two", "three" } } },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    session.configure(require("ghost-reader.config").setup({
      buffer = { layout = { max_total_blocks = 3, max_lines_per_block = 1 } },
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    }))
    local file = helpers.new_normal_buffer({ "local first = true", "local second = true", "local third = true", "local fourth = true", "local fifth = true" }, "lua")
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    local code_view = vim.fn.winsaveview()
    assert.is_true(session.start(vim.fn.tempname() .. ".txt", "mirror"))
    local current = session.get()

    vim.api.nvim_exec_autocmds("InsertEnter", { buffer = file })
    assert.is_false(current.ctx.view_state.mirror.visible)
    assert.same(code_view, vim.fn.winsaveview())
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    local edited_view = vim.fn.winsaveview()
    vim.api.nvim_exec_autocmds("InsertLeave", { buffer = file })
    assert.same({ chapter_index = 1, line_index = 1, segment_index = 1 }, current.position)
    assert.is_true(session.hide("hard"))
    assert.same(edited_view, vim.fn.winsaveview())
    assert.is_true(session.restore())

    local before_signature = current.ctx.view_state.mirror.layout_signature
    vim.api.nvim_win_set_width(current.target_win, math.max(10, vim.api.nvim_win_get_width(current.target_win) - 10))
    vim.api.nvim_exec_autocmds("WinResized", { data = { windows = { current.target_win } } })
    assert.is_truthy(vim.wait(100, function()
      return current.ctx.view_state.mirror.layout_signature ~= before_signature
    end, 5))
    assert.equal(1, current.position.chapter_index)
    assert.equal(1, current.position.line_index)
    assert.equal(1, current.position.segment_index)
    session.stop()
  end)

  it("reflows a real mirror session when its active anchor is folded", function()
    package.loaded["ghost-reader.bookshelf"] = {
      open = function(path)
        return {
          path = path,
          format = "txt",
          chapters = { { title = "One", lines = { "one", "two", "three", "four", "five", "six" } } },
          toc = { { title = "One", index = 1 } },
        }
      end,
    }
    local session = require("ghost-reader.session")
    local root = vim.fn.tempname()
    local cfg = require("ghost-reader.config").setup({
      buffer = {
        layout = {
          region_lines = 20,
          max_blocks_per_region = 1,
          max_lines_per_block = 1,
          min_gap_lines = 1,
          max_total_blocks = 4,
          edge_padding = 0,
        },
      },
      paths = { cache_dir = root .. "-cache/", data_dir = root .. "-data/" },
    })
    local lines = {}
    for index = 1, 80 do lines[index] = "local value_" .. index .. " = " .. index end
    local file = helpers.new_normal_buffer(lines, "lua")
    session.configure(cfg)
    assert.is_true(session.start(vim.fn.tempname() .. ".txt", "mirror"))
    local current = session.get()
    local old_active = current.ctx.view_state.mirror.active_row
    assert.is_number(old_active)

    local fold_start = old_active
    local fold_end = math.min(vim.api.nvim_buf_line_count(file), old_active + 1)
    vim.api.nvim_win_call(current.target_win, function()
      vim.wo[current.target_win].foldmethod = "manual"
      vim.cmd(('%d,%dfold'):format(fold_start, fold_end))
    end)
    vim.cmd("redraw!")
    assert.is_truthy(vim.wait(100, function()
      local active_row = current.ctx.view_state.mirror.active_row
      return active_row ~= old_active and active_row ~= nil
        and vim.api.nvim_win_call(current.target_win, function() return vim.fn.foldclosed(active_row) == -1 end)
    end, 5))
    for _, row in ipairs(current.ctx.view_state.mirror.reader_rows) do
      assert.equal(-1, vim.api.nvim_win_call(current.target_win, function() return vim.fn.foldclosed(row) end))
    end
    local folded_rows = vim.deepcopy(current.ctx.view_state.mirror.reader_rows)

    local ok, err = pcall(vim.api.nvim_win_call, current.target_win, function()
      vim.cmd(('%d,%dfoldopen'):format(fold_start, fold_end))
    end)
    assert.is_true(ok, err)
    vim.cmd("redraw!")
    assert.is_truthy(vim.wait(100, function()
      return current.visibility == "VISIBLE"
        and not vim.deep_equal(current.ctx.view_state.mirror.reader_rows, folded_rows)
        and next(current.ctx.view_state.mirror.prepared_by_row or {}) ~= nil
    end, 5))
    assert.is_true(current.ctx.view_state.mirror.active_row ~= nil)
    session.stop()
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
