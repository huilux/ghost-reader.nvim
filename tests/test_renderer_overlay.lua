local overlay = require("ghost-reader.renderer.overlay")
local buffer_seq = 0

local function make_context()
  vim.o.swapfile = false
  buffer_seq = buffer_seq + 1
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, "overlay-test-" .. buffer_seq .. ".lua")
  local lines = {}
  for i = 1, 20 do
    lines[i] = "local line_" .. i .. " = " .. i
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "lua"
  vim.bo[buf].modified = false

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(win, 8)

  return {
    target_buf = buf,
    target_win = win,
    config = { reader = { visible_blocks = 3 } },
    view_state = {},
  }
end

describe("renderer.overlay", function()
  it("renders virtual lines without changing the real buffer", function()
    local ctx = make_context()
    local buf = ctx.target_buf
    local win = ctx.target_win

    local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local name = vim.api.nvim_buf_get_name(buf)
    local ft = vim.bo[buf].filetype
    local statusline = vim.wo[win].statusline

    assert.is_true(overlay.start(ctx))
    assert.is_true(overlay.render(ctx, {
      blocks = {
        { text = "first paragraph", active = true },
        { text = "second paragraph", active = false },
      },
    }))

    assert.same(before, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    assert.equal(name, vim.api.nvim_buf_get_name(buf))
    assert.equal(ft, vim.bo[buf].filetype)
    assert.equal(statusline, vim.wo[win].statusline)
    assert.is_false(vim.bo[buf].modified)
  end)

  it("limits rendering to three visible blocks", function()
    local ctx = make_context()
    assert.is_true(overlay.start(ctx))
    assert.is_true(overlay.render(ctx, {
      blocks = {
        { text = "one", active = true },
        { text = "two", active = false },
        { text = "three", active = false },
        { text = "four", active = false },
      },
    }))

    local marks = vim.api.nvim_buf_get_extmarks(ctx.target_buf, ctx.view_state.overlay.namespace, 0, -1, { details = true })
    assert.equal(3, #marks)
  end)

  it("uses filetype comment prefixes", function()
    local ctx = make_context()
    assert.is_true(overlay.start(ctx))
    assert.is_true(overlay.render(ctx, { blocks = { { text = "prefix check", active = true } } }))

    local marks = vim.api.nvim_buf_get_extmarks(ctx.target_buf, ctx.view_state.overlay.namespace, 0, -1, { details = true })
    assert.is_truthy(#marks > 0)
    local details = marks[1][4]
    local virt = details.virt_lines[1][1][1]
    assert.is_truthy(virt:find("^%-%- "))
  end)

  it("hides and restores idempotently", function()
    local ctx = make_context()
    assert.is_true(overlay.start(ctx))
    assert.is_true(overlay.render(ctx, { blocks = { { text = "one", active = true } } }))
    assert.is_true(overlay.hide(ctx))
    assert.equal(0, #vim.api.nvim_buf_get_extmarks(ctx.target_buf, ctx.view_state.overlay.namespace, 0, -1, {}))
    assert.is_true(overlay.hide(ctx))
    assert.is_true(overlay.restore(ctx, { blocks = { { text = "two", active = true } } }))
    assert.is_true(overlay.stop(ctx))
    assert.is_true(overlay.stop(ctx))
  end)

  it("rejects a terminal buftype", function()
    vim.cmd("terminal")
    local buf = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()
    local ctx = {
      target_buf = buf,
      target_win = win,
      config = { reader = { visible_blocks = 3 } },
      view_state = {},
    }
    assert.is_false(overlay.start(ctx))
  end)

  it("recomputes anchors after resize", function()
    local ctx = make_context()
    assert.is_true(overlay.start(ctx))
    vim.api.nvim_win_set_height(ctx.target_win, 12)
    assert.is_true(overlay.render(ctx, {
      blocks = {
        { text = "one", active = true },
        { text = "two", active = false },
        { text = "three", active = false },
      },
    }))
    local first_marks = vim.api.nvim_buf_get_extmarks(ctx.target_buf, ctx.view_state.overlay.namespace, 0, -1, {})

    vim.api.nvim_win_set_height(ctx.target_win, 4)
    assert.is_true(overlay.render(ctx, {
      blocks = {
        { text = "one", active = true },
        { text = "two", active = false },
        { text = "three", active = false },
      },
    }))
    local second_marks = vim.api.nvim_buf_get_extmarks(ctx.target_buf, ctx.view_state.overlay.namespace, 0, -1, {})

    assert.is_truthy(#first_marks > 0)
    assert.is_truthy(#second_marks > 0)
    assert.are_not.equal(first_marks[1][2], second_marks[1][2])
  end)
end)
