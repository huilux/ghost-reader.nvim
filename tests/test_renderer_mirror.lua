local helpers = require("tests.helpers")
helpers.reset_modules()

local mirror = require("ghost-reader.renderer.mirror")
local buffer_seq = 0

local function reader_rows(ctx)
  return ctx.view_state.mirror.reader_rows or {}
end

local function make_context()
  vim.o.swapfile = false
  buffer_seq = buffer_seq + 1

  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, "mirror-test-" .. buffer_seq .. ".lua")
  local lines = {}
  for i = 1, 40 do
    lines[i] = "local line_" .. i .. " = " .. i
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "lua"
  vim.bo[buf].modified = false

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(win, 12)
  vim.api.nvim_win_set_width(win, 80)
  vim.api.nvim_win_set_cursor(win, { 18, 0 })

  return {
    target_buf = buf,
    target_win = win,
    config = {
      buffer = {
        style = "light",
        light = { visible_lines = 3, max_consecutive_lines = 3 },
        strong = { visible_lines = 3, max_consecutive_lines = 1 },
      },
    },
    view_state = {},
    mode = "mirror",
    view_name = "mirror",
  }
end

local function make_two_window_context()
  vim.o.swapfile = false
  buffer_seq = buffer_seq + 1

  local target_buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(target_buf, "mirror-target-" .. buffer_seq .. ".lua")
  local lines = {}
  for i = 1, 40 do
    lines[i] = "local target_" .. i .. " = " .. i
  end
  vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, lines)
  vim.bo[target_buf].filetype = "lua"
  vim.bo[target_buf].modified = false

  local scratch_buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(scratch_buf, "mirror-peer-" .. buffer_seq .. ".lua")
  vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, { "peer buffer" })
  vim.bo[scratch_buf].filetype = "lua"
  vim.bo[scratch_buf].modified = false

  local current_win = vim.api.nvim_get_current_win()
  local peer_win = vim.api.nvim_open_win(scratch_buf, false, {
    relative = "editor",
    width = 40,
    height = 10,
    row = 1,
    col = 1,
    style = "minimal",
    border = "none",
  })

  vim.api.nvim_win_set_buf(current_win, target_buf)
  vim.api.nvim_win_set_height(current_win, 12)
  vim.api.nvim_win_set_width(current_win, 80)
  vim.api.nvim_win_set_cursor(current_win, { 24, 0 })

  vim.api.nvim_win_set_cursor(peer_win, { 1, 0 })
  vim.api.nvim_win_set_width(peer_win, 40)

  return {
    target_buf = target_buf,
    target_win = current_win,
    peer_win = peer_win,
    config = {
      buffer = {
        style = "light",
        light = { visible_lines = 3, max_consecutive_lines = 3 },
        strong = { visible_lines = 3, max_consecutive_lines = 1 },
      },
    },
    view_state = {},
    mode = "mirror",
    view_name = "mirror",
  }
end

describe("renderer.mirror", function()
  it("renders virtual text on the real target buffer", function()
    local ctx = make_context()
    local target = ctx.target_buf
    local before = vim.api.nvim_buf_get_lines(target, 0, -1, false)
    local name = vim.api.nvim_buf_get_name(target)

    assert.is_true(mirror.start(ctx))
    assert.is_true(mirror.render(ctx, {
      blocks = {
        { chapter_index = 1, line_index = 1, segment_index = 1, text = "first", active = true },
        { chapter_index = 1, line_index = 2, segment_index = 1, text = "second", active = false },
      },
    }))

    local state = ctx.view_state.mirror
    assert.is_nil(state.buf)
    assert.is_number(state.namespace)
    assert.equal(target, vim.api.nvim_win_get_buf(ctx.target_win))
    assert.same(before, vim.api.nvim_buf_get_lines(target, 0, -1, false))
    assert.equal(name, vim.api.nvim_buf_get_name(target))
    assert.is_false(vim.bo[target].modified)

    local marks = vim.api.nvim_buf_get_extmarks(target, state.namespace, 0, -1, { details = true })
    assert.is_truthy(#marks > 0)
    assert.equal("overlay", marks[1][4].virt_text_pos)
  end)

  it("keeps one skeleton and an unnamed scratch buffer", function()
    local ctx = make_context()
    assert.is_true(mirror.start(ctx))
    local mirror_buf = ctx.view_state.mirror.buf
    local skeleton = vim.deepcopy(ctx.view_state.mirror.skeleton)
    assert.equal("", vim.api.nvim_buf_get_name(mirror_buf))

    assert.is_true(mirror.render(ctx, { blocks = { { text = "page one", active = true } } }))
    assert.is_true(mirror.render(ctx, { blocks = { { text = "page two", active = true } } }))
    assert.same(skeleton, ctx.view_state.mirror.skeleton)
  end)

  it("renders light style as a contiguous reading group", function()
    local ctx = make_context()
    ctx.config.buffer.light.max_consecutive_lines = 2
    assert.is_true(mirror.start(ctx))
    assert.is_true(mirror.render(ctx, {
      blocks = {
        { chapter_index = 1, line_index = 1, segment_index = 1, text = "one" },
        { chapter_index = 1, line_index = 2, segment_index = 1, text = "two" },
        { chapter_index = 1, line_index = 3, segment_index = 1, text = "three" },
      },
    }))
    local rows = reader_rows(ctx)
    assert.equal(3, #rows)
    assert.equal(1, rows[2] - rows[1])
    assert.is_true(rows[3] - rows[2] > 1)
  end)

  it("renders strong style as separated reading groups", function()
    local ctx = make_context()
    ctx.config.buffer.style = "strong"
    assert.is_true(mirror.start(ctx))
    assert.is_true(mirror.render(ctx, {
      blocks = {
        { chapter_index = 1, line_index = 1, segment_index = 1, text = "one" },
        { chapter_index = 1, line_index = 2, segment_index = 1, text = "two" },
        { chapter_index = 1, line_index = 3, segment_index = 1, text = "three" },
      },
    }))
    local rows = reader_rows(ctx)
    assert.equal(3, #rows)
    assert.is_true(rows[2] - rows[1] > 1)
    assert.is_true(rows[3] - rows[2] > 1)
    local lines = vim.api.nvim_buf_get_lines(ctx.view_state.mirror.buf, 0, -1, false)
    assert.is_truthy(lines[rows[1]]:match("one"))
  end)

  it("moves the cursor between rendered reading rows without stopping on skeleton code", function()
    local ctx = make_context()
    assert.is_true(mirror.start(ctx))
    assert.is_true(mirror.render(ctx, {
      blocks = {
        { chapter_index = 1, line_index = 1, segment_index = 1, text = "one" },
        { chapter_index = 1, line_index = 2, segment_index = 1, text = "two" },
        { chapter_index = 1, line_index = 3, segment_index = 1, text = "three" },
      },
    }))
    local rows = reader_rows(ctx)
    assert.equal(rows[1], vim.api.nvim_win_get_cursor(ctx.target_win)[1])
    assert.is_true(mirror.render(ctx, {
      blocks = {
        { chapter_index = 1, line_index = 2, segment_index = 1, text = "two" },
        { chapter_index = 1, line_index = 3, segment_index = 1, text = "three" },
        { chapter_index = 1, line_index = 4, segment_index = 1, text = "four" },
      },
    }))
    assert.equal(rows[2], vim.api.nvim_win_get_cursor(ctx.target_win)[1])
  end)

  it("uses the configured visible line count as its page size", function()
    local ctx = make_context()
    ctx.config.buffer.light.visible_lines = 7
    assert.equal(7, mirror.page_size(ctx))
  end)

  it("hide restores the real buffer and view", function()
    local ctx = make_context()
    local real_buf = ctx.target_buf
    local real_win = ctx.target_win

    local real_cursor = vim.api.nvim_win_get_cursor(real_win)
    local real_topline = vim.fn.winsaveview().topline
    local real_leftcol = vim.fn.winsaveview().leftcol

    assert.is_true(mirror.start(ctx))
    assert.is_true(mirror.render(ctx, { blocks = { { text = "page one", active = true } } }))

    assert.is_true(mirror.hide(ctx))
    assert.equal(real_buf, vim.api.nvim_win_get_buf(real_win))
    assert.same(real_cursor, vim.api.nvim_win_get_cursor(real_win))
    local restored_view = vim.fn.winsaveview()
    assert.equal(real_topline, restored_view.topline)
    assert.equal(real_leftcol, restored_view.leftcol)
  end)

  it("restore reuses the mirror buffer", function()
    local ctx = make_context()
    assert.is_true(mirror.start(ctx))
    local first_buf = ctx.view_state.mirror.buf

    assert.is_true(mirror.hide(ctx))
    assert.is_true(mirror.restore(ctx, { blocks = { { text = "page one", active = true } } }))
    assert.equal(first_buf, ctx.view_state.mirror.buf)
  end)

  it("stop deletes the scratch buffer", function()
    local ctx = make_context()
    assert.is_true(mirror.start(ctx))
    local mirror_buf = ctx.view_state.mirror.buf

    assert.is_true(mirror.stop(ctx))
    assert.is_false(vim.api.nvim_buf_is_valid(mirror_buf))
  end)

  it("hide and stop are idempotent", function()
    local ctx = make_context()
    assert.is_true(mirror.start(ctx))
    assert.is_true(mirror.hide(ctx))
    assert.is_true(mirror.hide(ctx))
    assert.is_true(mirror.stop(ctx))
    assert.is_true(mirror.stop(ctx))
  end)

  it("restores a non-current target window view", function()
    local ctx = make_two_window_context()
    vim.api.nvim_set_current_win(ctx.peer_win)

    local expected_cursor = vim.api.nvim_win_get_cursor(ctx.target_win)
    local expected_view = vim.api.nvim_win_call(ctx.target_win, function()
      return vim.fn.winsaveview()
    end)

    assert.is_true(mirror.start(ctx))
    assert.is_true(mirror.render(ctx, { blocks = { { text = "page one", active = true } } }))
    assert.is_true(mirror.hide(ctx))

    local restored_cursor = vim.api.nvim_win_get_cursor(ctx.target_win)
    local restored_view = vim.api.nvim_win_call(ctx.target_win, function()
      return vim.fn.winsaveview()
    end)

    assert.same(expected_cursor, restored_cursor)
    assert.equal(expected_view.topline, restored_view.topline)
    assert.equal(expected_view.leftcol, restored_view.leftcol)
    assert.equal(expected_view.col, restored_view.col)
    assert.equal(expected_view.lnum, restored_view.lnum)
    assert.equal(expected_view.curswant, restored_view.curswant)
  end)
end)
