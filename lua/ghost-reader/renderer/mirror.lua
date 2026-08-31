local M = {}
local utils = require("ghost-reader.utils")
local presets = require("ghost-reader.renderer.presets")

local namespace_name = "GhostReaderMirror"

local function state(ctx)
  ctx.view_state.mirror = ctx.view_state.mirror or {}
  return ctx.view_state.mirror
end

local function candidate_buffers()
  local candidates = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted and vim.bo[buf].buftype == "" then
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      if #lines >= 20 then
        candidates[#candidates + 1] = {
          buf = buf,
          lines = lines,
          filetype = vim.bo[buf].filetype,
          name = vim.api.nvim_buf_get_name(buf),
        }
      end
    end
  end
  return candidates
end

local function pick_skeleton(ctx)
  local candidates = candidate_buffers()
  table.sort(candidates, function(a, b)
    if #a.lines == #b.lines then
      return a.buf < b.buf
    end
    return #a.lines > #b.lines
  end)
  if #candidates > 0 then
    local chosen = candidates[1]
    return {
      lines = vim.deepcopy(chosen.lines),
      filetype = chosen.filetype ~= "" and chosen.filetype or "lua",
      name = chosen.name,
    }
  end

  local preset = presets.get(ctx.config and ctx.config.reader and ctx.config.reader.preset or "random")
  return {
    lines = vim.deepcopy(preset.lines),
    filetype = preset.filetype or "lua",
    name = preset.path or "",
  }
end

local function create_scratch_buffer(skeleton)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].filetype = skeleton.filetype
  return buf
end

local function visible_blocks(ctx, frame)
  local blocks = frame and frame.blocks or {}
  local limit = ctx.config and ctx.config.reader and ctx.config.reader.visible_blocks or 3
  local visible = {}
  for i = 1, math.min(#blocks, limit) do
    visible[#visible + 1] = blocks[i]
  end
  return visible
end

local function wrap_block_text(text, width)
  return utils.wrap_display(text or "", math.max(20, width))
end

local function build_lines(ctx, frame)
  local mirror = state(ctx)
  local skeleton = mirror.skeleton or {}
  local lines = vim.deepcopy(skeleton.lines or {})
  local blocks = visible_blocks(ctx, frame)
  if #lines == 0 then
    lines = { "" }
  end

  local positions = {}
  local last = math.max(1, #lines)
  for i = 1, #blocks do
    positions[i] = math.max(1, math.floor((last - 1) * i / (#blocks + 1)) + 1)
  end

  local width = math.max(20, (vim.api.nvim_win_get_width(ctx.target_win) or 80) - 4)
  for i, block in ipairs(blocks) do
    local wrapped = wrap_block_text(block.text, width)
    local pos = positions[i] or last
    for j, segment in ipairs(wrapped) do
      local line = segment
      if block.active then
        line = ">> " .. line
      end
      lines[pos + j - 1] = line
    end
  end

  return lines
end

local function save_view(ctx)
  local mirror = state(ctx)
  if not mirror.saved then
    mirror.saved = {
      buf = ctx.target_buf,
      win = ctx.target_win,
      view = vim.api.nvim_win_call(ctx.target_win, function()
        return vim.fn.winsaveview()
      end),
    }
  end
end

local function restore_saved_view(ctx)
  local mirror = state(ctx)
  local saved = mirror.saved
  if not saved then
    return true
  end
  if vim.api.nvim_win_is_valid(saved.win) and vim.api.nvim_buf_is_valid(saved.buf) then
    vim.api.nvim_win_call(saved.win, function()
      vim.api.nvim_win_set_buf(saved.win, saved.buf)
      vim.fn.winrestview(saved.view)
    end)
  end
  return true
end

function M.supports(buf, win)
  return vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win)
end

function M.start(ctx)
  if not M.supports(ctx.target_buf, ctx.target_win) then
    return false
  end
  local mirror = state(ctx)
  if mirror.buf and vim.api.nvim_buf_is_valid(mirror.buf) then
    return true
  end
  save_view(ctx)
  mirror.skeleton = mirror.skeleton or pick_skeleton(ctx)
  mirror.buf = create_scratch_buffer(mirror.skeleton)
  mirror.namespace = mirror.namespace or vim.api.nvim_create_namespace(namespace_name)
  vim.api.nvim_set_current_win(ctx.target_win)
  vim.api.nvim_win_set_buf(ctx.target_win, mirror.buf)
  vim.api.nvim_win_set_option(ctx.target_win, "number", false)
  vim.api.nvim_win_set_option(ctx.target_win, "relativenumber", false)
  return true
end

function M.render(ctx, frame)
  local mirror = state(ctx)
  if not mirror.buf or not vim.api.nvim_buf_is_valid(mirror.buf) then
    if not M.start(ctx) then
      return false
    end
  end
  local lines = build_lines(ctx, frame)
  vim.bo[mirror.buf].modifiable = true
  vim.api.nvim_buf_set_lines(mirror.buf, 0, -1, false, lines)
  vim.bo[mirror.buf].modifiable = false
  return true
end

function M.hide(ctx)
  local mirror = state(ctx)
  if not mirror.saved then
    save_view(ctx)
  end
  restore_saved_view(ctx)
  return true
end

function M.restore(ctx, frame)
  local mirror = state(ctx)
  if mirror.saved and vim.api.nvim_win_is_valid(mirror.saved.win) and vim.api.nvim_buf_is_valid(mirror.saved.buf) then
    vim.api.nvim_win_set_buf(mirror.saved.win, mirror.buf)
  end
  return M.render(ctx, frame)
end

function M.stop(ctx)
  local mirror = state(ctx)
  restore_saved_view(ctx)
  if mirror.buf and vim.api.nvim_buf_is_valid(mirror.buf) then
    vim.api.nvim_buf_delete(mirror.buf, { force = true })
  end
  mirror.buf = nil
  return true
end

function M.page_size(ctx)
  return ctx.config and ctx.config.reader and ctx.config.reader.visible_blocks or 3
end

function M.segment_count(ctx, text)
  return #utils.wrap_display(text or "", math.max(20, vim.api.nvim_win_get_width(ctx.target_win) - 4))
end

function M.segment_text(ctx, text, index)
  return utils.wrap_display(text or "", math.max(20, vim.api.nvim_win_get_width(ctx.target_win) - 4))[index]
end

return M
