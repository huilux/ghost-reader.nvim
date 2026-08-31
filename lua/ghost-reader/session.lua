local M = {}

local bookshelf = require("ghost-reader.bookshelf")
local navigate = require("ghost-reader.reader.navigate")
local renderer = require("ghost-reader.renderer")
local progress = require("ghost-reader.reader.progress")
local keymaps = require("ghost-reader.keymaps")
local utils = require("ghost-reader.utils")

local function status(state)
  return state and state.visibility or "IDLE"
end

local function make_context(state)
  return {
    target_buf = state.control_buf,
    target_win = state.control_win,
    config = state.config,
    view_state = state.view_state,
    generation = state.generation,
  }
end

local function current_segment_total(_, _, _) return 1 end

local function render_state(state)
  if not state or not state.renderer then
    return false
  end
  local chapter = state.book.chapters[state.position.chapter_index] or { lines = {} }
  local lines = chapter.lines or {}
  local line = lines[state.position.line_index] or ""
  local frame = {
    title = state.book.title or state.book.path or "",
    path = state.book.path,
    blocks = { { text = line, active = true } },
  }
  return state.renderer.render(make_context(state), frame)
end

local function apply_controls(state, enable)
  if not state then
    return false
  end
  if enable then
    if not state.controls_active then
      keymaps.enter_controls(state, state.config)
      state.controls_active = true
    end
  else
    if state.controls_active then
      keymaps.leave_controls(state)
    end
  end
  return true
end

local function clear_autocmds(state)
  if state and state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    state.augroup = nil
  end
end

local function stop_timers(state)
  if state and state.timer then
    pcall(state.timer.stop, state.timer)
    pcall(state.timer.close, state.timer)
    state.timer = nil
  end
end

local function stop_view(state)
  if not state or not state.renderer then
    return
  end
  pcall(state.renderer.stop, make_context(state))
end

function M.open(opts)
  opts = opts or {}
  local config = opts.config or require("ghost-reader.config").setup()
  local book, err = bookshelf.open(opts.path, config)
  if err then
    utils.notify(err, vim.log.levels.ERROR)
    return false
  end

  if M.state then
    M.stop()
  end

  local mode = opts.mode or config.reader.renderer or "overlay"
  local control_buf = vim.api.nvim_get_current_buf()
  local control_win = vim.api.nvim_get_current_win()
  local renderer_impl = renderer.create(mode, {
    buffer = control_buf,
    window = control_win,
    config = config,
  })

  M.state = {
    lifecycle = "ACTIVE",
    visibility = "VISIBLE",
    controls = mode == "statusline" and "INACTIVE" or "ACTIVE",
    mode = mode,
    book = book,
    config = config,
    position = { chapter_index = 1, line_index = 1, segment_index = 1 },
    view_state = {},
    renderer = renderer_impl,
    control_buf = control_buf,
    control_win = control_win,
    generation = (M.state and M.state.generation or 0) + 1,
  }

  if opts.position then
    M.state.position = navigate.normalize(book, opts.position, current_segment_total)
  end

  render_state(M.state)
  apply_controls(M.state, M.state.controls == "ACTIVE")
  return true
end

function M.stop()
  local state = M.state
  if not state then
    return true
  end
  state.lifecycle = "STOPPING"
  stop_timers(state)
  apply_controls(state, false)
  stop_view(state)
  clear_autocmds(state)
  state.lifecycle = "IDLE"
  state.visibility = "IDLE"
  state.controls = "INACTIVE"
  return true
end

function M.restore()
  local state = M.state
  if not state then
    return false
  end
  state.visibility = "VISIBLE"
  if state.mode == "statusline" then
    state.controls = "INACTIVE"
  else
    state.controls = "ACTIVE"
  end
  render_state(state)
  apply_controls(state, state.controls == "ACTIVE")
  return true
end

function M.toggle_hide()
  local state = M.state
  if not state then
    return false
  end
  if state.visibility == "VISIBLE" then
    state.visibility = "HARD_HIDDEN"
    state.controls = "INACTIVE"
    apply_controls(state, false)
    stop_view(state)
    stop_timers(state)
    return true
  end
  return M.restore()
end

function M.toggle_controls()
  local state = M.state
  if not state then
    return false
  end
  if state.controls == "ACTIVE" then
    apply_controls(state, false)
    state.controls = "INACTIVE"
  else
    apply_controls(state, true)
    state.controls = "ACTIVE"
  end
  return true
end

function M.toc()
  local state = M.state
  if not state or not state.book or not state.book.toc then
    return false
  end
  local items = {}
  for _, entry in ipairs(state.book.toc) do
    items[#items + 1] = entry.title
  end
  vim.ui.select(items, { prompt = "Table of Contents:" }, function(_, idx)
    if idx then
      state.position = navigate.go_to_chapter(state.book, state.position, idx, current_segment_total)
      render_state(state)
    end
  end)
  return true
end

function M.dispatch(name)
  local state = M.state
  if not state then
    return false
  end
  if name == "hide" then return M.toggle_hide() end
  if name == "exit_controls" then return M.toggle_controls() end
  if name == "toc" then return M.toc() end
  if name == "close" then return M.stop() end
  if name == "progress" then
    progress.show(state.book, state)
    return true
  end
  if name == "next_chapter" then
    state.position = navigate.next_chapter(state.book, state.position, current_segment_total)
  elseif name == "prev_chapter" then
    state.position = navigate.prev_chapter(state.book, state.position, current_segment_total)
  elseif name == "next_page" or name == "next_content" then
    state.position = navigate.next_content(state.book, state.position, current_segment_total)
  elseif name == "prev_page" or name == "prev_content" then
    state.position = navigate.prev_content(state.book, state.position, current_segment_total)
  elseif name == "toggle_auto" or name == "faster" or name == "slower" then
    return true
  else
    return false
  end
  render_state(state)
  return true
end

return M
