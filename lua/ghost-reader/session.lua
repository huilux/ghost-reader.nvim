local M = {}

local bookshelf = require("ghost-reader.bookshelf")
local navigate = require("ghost-reader.reader.navigate")
local progress = require("ghost-reader.reader.progress")
local history = require("ghost-reader.history")
local renderer = require("ghost-reader.renderer")
local keymaps = require("ghost-reader.keymaps")
local utils = require("ghost-reader.utils")

local default_config = require("ghost-reader.config").setup()

local state = {
  lifecycle = "IDLE",
  visibility = "IDLE",
  controls = "INACTIVE",
  generation = 0,
}

local active = nil
M.state = state

local function ensure_state()
  state.lifecycle = state.lifecycle or "IDLE"
  state.visibility = state.visibility or "IDLE"
  state.controls = state.controls or "INACTIVE"
  return state
end

local function clone(tbl)
  return vim.deepcopy(tbl)
end

local function ctx()
  if not active then
    return nil
  end
  return active.ctx
end

local function set_state(new_state)
  active = new_state
  if new_state then
    state = new_state
    M.state = new_state
  else
    M.state = state
  end
end

local function segment_count(chapter_index, line_index)
  if not active or not active.renderer.segment_count then
    return 1
  end
  local chapter = active.book.chapters[chapter_index] or { lines = {} }
  local text = chapter.lines[line_index] or ""
  return math.max(1, tonumber(active.renderer.segment_count(active.ctx, text)) or 1)
end

local function frame_for(pos)
  local chapter = active.book.chapters[pos.chapter_index] or { lines = {} }
  local lines = chapter.lines or {}
  local page_size = active.renderer.page_size(active.ctx)
  local peek = navigate.peek(active.book, pos, math.max(1, page_size), segment_count)
  local blocks = {}
  for i, item in ipairs(peek) do
    local chapter_item = active.book.chapters[item.chapter_index] or { lines = {} }
    local line = chapter_item.lines[item.line_index] or ""
    local segment_text = line
    if active.renderer.segment_text then
      segment_text = active.renderer.segment_text(active.ctx, line, item.segment_index) or line
    end
    blocks[#blocks + 1] = {
      index = i,
      chapter_index = item.chapter_index,
      line_index = item.line_index,
      segment_index = item.segment_index,
      text = segment_text,
      active = i == 1,
    }
  end
  if #blocks == 0 then
    blocks[1] = { index = 1, chapter_index = pos.chapter_index, line_index = pos.line_index, segment_index = pos.segment_index, text = lines[pos.line_index] or "", active = true }
  end
  return {
    title = active.book.title or active.book.path or "",
    path = active.book.path,
    position = clone(pos),
    blocks = blocks,
    visible_blocks = active.config.reader.visible_blocks,
    page_size = page_size,
  }
end

local function make_renderer_ctx()
  return active.ctx
end

local function render_current()
  if not active then
    return false
  end
  local frame = frame_for(active.position)
  local ok = active.renderer.render(make_renderer_ctx(), frame)
  return ok ~= false
end

local function save_progress()
  if active and active.book and active.config then
    progress.save(active.book, active.position, active.config)
  end
end

local function stop_renderer(session)
  if session and session.renderer and session.renderer.stop then
    pcall(session.renderer.stop, session.ctx)
  end
end

local function setup_autocmds()
  if active.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, active.autocmd_group)
  end
  active.autocmd_group = vim.api.nvim_create_augroup("ghost-reader-session-" .. active.generation, { clear = true })

  local function autocmd(events, callback)
    vim.api.nvim_create_autocmd(events, {
      group = active.autocmd_group,
      buffer = active.control_buf,
      callback = callback,
    })
  end

  autocmd("InsertEnter", function()
    if active and active.mode == "overlay" and active.config.stealth.overlay.hide_on_insert then
      M.hide("soft")
    end
  end)

  autocmd("InsertLeave", function()
    if active and active.visibility == "SOFT_HIDDEN" and active.mode == "overlay" then
      M.restore()
    end
  end)

  autocmd("BufLeave", function()
    if active and active.mode == "overlay" and active.config.stealth.overlay.hide_on_buf_leave then
      M.hide("hard")
    elseif active and active.mode == "statusline" and active.controls == "ACTIVE" then
      keymaps.leave_controls(active)
      active.controls = "INACTIVE"
    end
  end)

  autocmd("WinLeave", function()
    if active and active.mode == "overlay" and active.config.stealth.overlay.hide_on_win_leave then
      M.hide("hard")
    end
  end)

  autocmd("FocusLost", function()
    if active and active.config.stealth.hide_on_focus_lost then
      M.hide("hard")
    end
  end)

  vim.api.nvim_create_autocmd("QuitPre", {
    group = active.autocmd_group,
    callback = function()
      M.stop()
    end,
  })
end

local function open_book(path, mode)
  local cfg = clone(active and active.config or default_config)
  local book, err = bookshelf.open(path, cfg)
  if err then
    utils.notify(err, vim.log.levels.ERROR)
    return false
  end

  local previous = active
  local requested_mode = mode or cfg.reader.renderer or "overlay"
  local control_buf = vim.api.nvim_get_current_buf()
  local control_win = vim.api.nvim_get_current_win()
  local ctx_obj = {
    target_buf = control_buf,
    target_win = control_win,
    config = cfg,
    view_state = {},
    mode = requested_mode,
    view_name = requested_mode,
    generation = state.generation + 1,
  }
  local impl = renderer.create(ctx_obj, requested_mode)
  if not impl then
    return false
  end

  local tentative = {
    lifecycle = "ACTIVE",
    visibility = "VISIBLE",
    controls = requested_mode == "statusline" and "INACTIVE" or "ACTIVE",
    mode = requested_mode,
    view_name = ctx_obj.view_name,
    book = book,
    config = cfg,
    position = { chapter_index = 1, line_index = 1, segment_index = 1 },
    ctx = ctx_obj,
    renderer = impl,
    control_buf = control_buf,
    control_win = control_win,
    generation = state.generation + 1,
  }

  local saved = progress.load(book, cfg)
  if saved and saved.position then
    tentative.position = navigate.normalize(book, saved.position, segment_count)
  end
  active = tentative
  local ok, rendered = pcall(render_current)
  if not ok or rendered == false then
    stop_renderer(tentative)
    active = previous
    return false
  end

  if previous then
    local previous_state = active
    active = previous
    M.stop()
    active = previous_state
  end

  set_state(tentative)
  setup_autocmds()
  history.record(book.path, cfg)
  if active.controls == "ACTIVE" then
    keymaps.enter_controls(active, cfg)
  end
  active.visibility = "VISIBLE"
  return true
end

function M.configure(cfg)
  default_config = cfg or default_config
  return default_config
end

function M.start(path, mode)
  return open_book(path, mode)
end

function M.open(path, mode)
  return M.start(path, mode)
end

function M.get()
  if active and active.lifecycle == "ACTIVE" then
    return active
  end
  return nil
end

function M.hide(policy)
  if not active then
    return false
  end
  if policy == "soft" then
    if active.visibility == "HARD_HIDDEN" then
      return false
    end
    active.visibility = "SOFT_HIDDEN"
    active.hidden_policy = "soft"
    if active.renderer.hide then
      active.renderer.hide(active.ctx)
    end
    return true
  end
  if active.controls == "ACTIVE" then
    keymaps.leave_controls(active)
  end
  active.visibility = "HARD_HIDDEN"
  active.controls = "INACTIVE"
  active.hidden_policy = "hard"
  if active.renderer.hide then
    active.renderer.hide(active.ctx)
  end
  return true
end

function M.toggle_hide()
  if not active then
    return false
  end
  if active.visibility == "VISIBLE" then
    return M.hide("hard")
  end
  return M.restore()
end

function M.toggle_controls()
  if not active then
    return false
  end
  if active.controls == "ACTIVE" then
    keymaps.leave_controls(active)
    active.controls = "INACTIVE"
  else
    keymaps.enter_controls(active, active.config)
    active.controls = "ACTIVE"
  end
  return true
end

function M.restore()
  if not active then
    return false
  end
  active.visibility = "VISIBLE"
  if active.mode == "statusline" then
    active.controls = "INACTIVE"
  else
    active.controls = "ACTIVE"
  end
  if active.renderer.restore and active.hidden_policy ~= nil then
    active.renderer.restore(active.ctx, frame_for(active.position))
  else
    render_current()
  end
  active.hidden_policy = nil
  if active.mode ~= "statusline" then
    active.controls = "ACTIVE"
    keymaps.enter_controls(active, active.config)
  end
  return true
end

function M.stop()
  if not active then
    state.lifecycle = "IDLE"
    state.visibility = "IDLE"
    state.controls = "INACTIVE"
    return true
  end
  active.lifecycle = "STOPPING"
  save_progress()
  if active.renderer.stop then
    active.renderer.stop(active.ctx)
  end
  if active.control_maps then
    keymaps.leave_controls(active)
  end
  if active.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, active.autocmd_group)
  end
  state.lifecycle = "IDLE"
  state.visibility = "IDLE"
  state.controls = "INACTIVE"
  active.lifecycle = "IDLE"
  active.visibility = "IDLE"
  active.controls = "INACTIVE"
  set_state(nil)
  return true
end

function M.dispatch(name)
  if not active then
    return false
  end
  if name == "close" then
    return M.stop()
  elseif name == "hide" then
    return M.hide("hard")
  elseif name == "toc" then
    return M.toc()
  elseif name == "exit_controls" then
    return M.toggle_controls()
  elseif name == "progress" then
    progress.show(active.book, active.position)
    return true
  elseif name == "toggle_auto" or name == "faster" or name == "slower" then
    if active.mode ~= "statusline" then
      return false
    end
    local fn = active.renderer[name]
    if type(fn) ~= "function" then
      return false
    end
    fn(active.ctx)
    return true
  end

  local next_pos, moved = nil, false
  if name == "next_content" then
    next_pos, moved = navigate.next_content(active.book, active.position, segment_count)
  elseif name == "prev_content" then
    next_pos, moved = navigate.prev_content(active.book, active.position, segment_count)
  elseif name == "next_page" then
    next_pos, moved = navigate.next_page(active.book, active.position, active.renderer.page_size(active.ctx), segment_count)
  elseif name == "prev_page" then
    next_pos, moved = navigate.prev_page(active.book, active.position, active.renderer.page_size(active.ctx), segment_count)
  elseif name == "next_chapter" then
    next_pos, moved = navigate.next_chapter(active.book, active.position, segment_count)
  elseif name == "prev_chapter" then
    next_pos, moved = navigate.prev_chapter(active.book, active.position, segment_count)
  else
    return false
  end
  active.position = next_pos
  render_current()
  return moved
end

function M.toc()
  if not active or not active.book or not active.book.toc then
    return false
  end
  local items = {}
  for _, entry in ipairs(active.book.toc) do
    items[#items + 1] = entry.title
  end
  vim.ui.select(items, { prompt = "Table of Contents:" }, function(_, idx)
    if idx and active.book.toc[idx] then
      local target = active.book.toc[idx]
      local chapter_index = target.index or idx
      active.position = navigate.go_to_chapter(active.book, active.position, chapter_index, segment_count)
      render_current()
    end
  end)
  return true
end

function M._reset_for_tests()
  if active and active.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, active.autocmd_group)
  end
  active = nil
  state = {
    lifecycle = "IDLE",
    visibility = "IDLE",
    controls = "INACTIVE",
    generation = 0,
  }
  default_config = require("ghost-reader.config").setup()
end

return M
