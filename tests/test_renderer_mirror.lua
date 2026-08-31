local helpers = require("tests.helpers")
helpers.reset_modules()

local mirror = require("ghost-reader.renderer.mirror")
local buffer_seq = 0

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
    config = { reader = { visible_blocks = 3 } },
    view_state = {},
    mode = "overlay",
    view_name = "mirror",
  }
end

describe("renderer.mirror", function()
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
end)
