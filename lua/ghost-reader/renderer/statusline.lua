local M = {}
local utils = require("ghost-reader.utils")

M.state = nil

local function close_timer(state)
  if state.timer then
    pcall(state.timer.stop, state.timer)
    pcall(state.timer.close, state.timer)
    state.timer = nil
  end
end

local function close_float(state)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win = nil
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state.buf = nil
end

local function cleanup()
  local state = M.state
  if not state then
    return
  end
  close_timer(state)
  close_float(state)
  M.state = nil
end

local function ensure_state(ctx)
  local state = M.state
  if state then
    state.ctx = ctx or state.ctx
    return state
  end

  state = {
    ctx = ctx,
    hidden = false,
    frame = nil,
    timer = nil,
    buf = nil,
    win = nil,
  }
  M.state = state
  return state
end

local function open_float(state)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    return state.win
  end

  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end

  local win = assert(state.ctx and state.ctx.target_win, "statusline renderer needs target_win")
  local width = math.max(20, vim.api.nvim_win_get_width(win))
  local height = 1
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = true
  local row = math.max(0, vim.o.lines - 2)
  state.buf = buf
  state.win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = 0,
    style = "minimal",
    focusable = false,
    border = "none",
    zindex = 60,
  })
  vim.wo[state.win].wrap = false
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].statusline = " "
  return state.win
end

local function timer_cb()
  cleanup()
end

local function refresh_timer(state)
  close_timer(state)
  local interval = (state.ctx and state.ctx.config and state.ctx.config.statusline and state.ctx.config.statusline.interval) or 3000
  state.timer = assert(vim.uv.new_timer())
  state.timer:start(interval, 0, vim.schedule_wrap(timer_cb))
end

local function render_line(frame)
  local blocks = frame and frame.blocks or {}
  local parts = {}
  for i, block in ipairs(blocks) do
    local text = block and block.text or ""
    if text ~= "" then
      parts[#parts + 1] = text
    end
  end
  if #parts == 0 then
    return ""
  end
  return table.concat(parts, " · ")
end

function M.start(ctx)
  ensure_state(ctx)
  return true
end

function M.render(ctx, frame)
  local state = ensure_state(ctx)
  state.frame = frame
  if state.hidden then
    return true
  end
  local win = open_float(state)
  local line = render_line(frame)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { line })
  vim.api.nvim_win_set_width(win, math.max(20, vim.api.nvim_win_get_width(ctx.target_win)))
  refresh_timer(state)
  return true
end

M.update = M.render

function M.hide()
  local state = M.state
  if not state then
    return true
  end
  state.hidden = true
  close_timer(state)
  close_float(state)
  return true
end

function M.restore(ctx, frame)
  local state = ensure_state(ctx)
  state.hidden = false
  if frame then
    state.frame = frame
  end
  return M.render(state.ctx, state.frame)
end

function M.stop()
  cleanup()
  return true
end

function M.page_size(ctx)
  return (ctx.config and ctx.config.statusline and ctx.config.statusline.page_step) or 5
end

function M.segment_count(ctx, text)
  return #utils.wrap_display(text, math.max(20, vim.api.nvim_win_get_width(ctx.target_win)))
end

function M.segment_text(ctx, text, index)
  return utils.wrap_display(text, math.max(20, vim.api.nvim_win_get_width(ctx.target_win)))[index]
end

return M
