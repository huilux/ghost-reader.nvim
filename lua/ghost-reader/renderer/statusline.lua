local M = {}
local utils = require("ghost-reader.utils")

local MIN_INTERVAL = 500
local MAX_INTERVAL = 15000

local function state(ctx)
  ctx.view_state = ctx.view_state or {}
  ctx.view_state.statusline = ctx.view_state.statusline or {}
  return ctx.view_state.statusline
end

local function clamp_interval(value)
  value = tonumber(value) or 3000
  if value < MIN_INTERVAL then
    return MIN_INTERVAL
  end
  if value > MAX_INTERVAL then
    return MAX_INTERVAL
  end
  return value
end

local function config(ctx)
  return (ctx and ctx.config and ctx.config.statusline) or {}
end

local function autoplay_enabled(ctx)
  local st = state(ctx)
  if st.autoplay == nil then
    return config(ctx).autoplay ~= false
  end
  return st.autoplay
end

local function current_generation(ctx)
  return ctx and ctx.generation
end

local function current_frame(st)
  return st.frame or { blocks = {} }
end

local function close_timer(st)
  if st.timer then
    pcall(st.timer.stop, st.timer)
    pcall(st.timer.close, st.timer)
    st.timer = nil
  end
end

local function close_float(st)
  if st.win and vim.api.nvim_win_is_valid(st.win) then
    pcall(vim.api.nvim_win_close, st.win, true)
  end
  st.win = nil
  if st.buf and vim.api.nvim_buf_is_valid(st.buf) then
    pcall(vim.api.nvim_buf_delete, st.buf, { force = true })
  end
  st.buf = nil
end

local function timer_factory()
  if M._new_timer then
    return M._new_timer()
  end
  return assert(vim.uv.new_timer())
end

local function render_text(frame)
  local blocks = frame and frame.blocks or {}
  local block = blocks[1] or {}
  local text = block.text or ""
  local prefix = block.active and "▶ " or "‖ "
  return prefix .. text
end

local function wrap_width()
  return math.max(20, vim.o.columns - 4)
end

local function update_window(st)
  if not (st.win and vim.api.nvim_win_is_valid(st.win)) then
    return false
  end
  local height = 1
  local width = wrap_width()
  local row = math.max(0, vim.o.lines - height - 1)
  vim.api.nvim_win_set_config(st.win, {
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
  return true
end

local function open_float(ctx)
  local st = state(ctx)
  if st.win and vim.api.nvim_win_is_valid(st.win) then
    return st.win
  end
  if st.buf and vim.api.nvim_buf_is_valid(st.buf) then
    pcall(vim.api.nvim_buf_delete, st.buf, { force = true })
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = true
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = wrap_width(),
    height = 1,
    row = math.max(0, vim.o.lines - 2),
    col = 0,
    style = "minimal",
    focusable = false,
    border = "none",
    zindex = 60,
  })
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].statusline = " "
  st.buf = buf
  st.win = win
  return win
end

local function dispatch_next(ctx)
  local actions = require("ghost-reader.actions")
  if actions and actions.next_content then
    return actions.next_content(ctx)
  end
  return false
end

local function schedule_autoplay(ctx)
  local st = state(ctx)
  close_timer(st)
  if not st.visible or not autoplay_enabled(ctx) then
    return
  end
  local interval = clamp_interval(config(ctx).interval)
  local gen = current_generation(ctx)
  st.timer = timer_factory()
  st.timer:start(interval, 0, vim.schedule_wrap(function()
    local live = state(ctx)
    close_timer(live)
    if not live.visible then
      return
    end
    if current_generation(ctx) ~= gen then
      return
    end
    if not autoplay_enabled(ctx) then
      return
    end
    if dispatch_next(ctx) then
      schedule_autoplay(ctx)
    end
  end))
end

local function cleanup_handles(st)
  close_timer(st)
  close_float(st)
end

function M.start(ctx)
  local st = state(ctx)
  st.visible = true
  st.autoplay = config(ctx).autoplay ~= false
  st.interval = clamp_interval(config(ctx).interval)
  st.page_step = tonumber(config(ctx).page_step) or 5
  st.frame = st.frame or { blocks = {} }
  st.generation = current_generation(ctx)
  return true
end

function M.render(ctx, frame)
  local st = state(ctx)
  st.frame = frame or st.frame or { blocks = {} }
  st.visible = true
  st.generation = current_generation(ctx)
  local win = open_float(ctx)
  update_window(st)
  vim.api.nvim_buf_set_lines(st.buf, 0, -1, false, { render_text(st.frame) })
  schedule_autoplay(ctx)
  return true
end

M.update = M.render

function M.resize(ctx)
  local st = state(ctx)
  if not (st.win and vim.api.nvim_win_is_valid(st.win)) then
    return false
  end
  update_window(st)
  return true
end

function M.hide(ctx)
  local st = state(ctx)
  st.visible = false
  cleanup_handles(st)
  return true
end

function M.restore(ctx, frame)
  local st = state(ctx)
  st.visible = true
  if frame then
    st.frame = frame
  end
  st.generation = current_generation(ctx)
  if not open_float(ctx) then
    return false
  end
  update_window(st)
  vim.api.nvim_buf_set_lines(st.buf, 0, -1, false, { render_text(current_frame(st)) })
  schedule_autoplay(ctx)
  return true
end

function M.stop(ctx)
  local st = state(ctx)
  cleanup_handles(st)
  st.visible = false
  st.autoplay = false
  return true
end

function M.page_size(ctx)
  return tonumber(config(ctx).page_step) or 5
end

function M.segment_count(ctx, text)
  return #utils.wrap_display(text, wrap_width())
end

function M.segment_text(ctx, text, index)
  return utils.wrap_display(text, wrap_width())[index]
end

function M.toggle_auto(ctx)
  local st = state(ctx)
  st.autoplay = not autoplay_enabled(ctx)
  if st.autoplay and st.visible then
    schedule_autoplay(ctx)
  else
    close_timer(st)
  end
  return st.autoplay
end

function M.faster(ctx)
  local st = state(ctx)
  st.interval = clamp_interval((st.interval or config(ctx).interval or 3000) - 500)
  if st.visible and autoplay_enabled(ctx) then
    schedule_autoplay(ctx)
  end
  return st.interval
end

function M.slower(ctx)
  local st = state(ctx)
  st.interval = clamp_interval((st.interval or config(ctx).interval or 3000) + 500)
  if st.visible and autoplay_enabled(ctx) then
    schedule_autoplay(ctx)
  end
  return st.interval
end

return M
