local M = {}
local utils = require("ghost-reader.utils")

local namespace_name = "GhostReaderComment"

local prefixes = {
  lua = "-- ",
  python = "# ",
  javascript = "// ",
  typescript = "// ",
  typescriptreact = "// ",
  go = "// ",
  rust = "// ",
  java = "// ",
  c = "// ",
  cpp = "// ",
  sh = "# ",
  bash = "# ",
  zsh = "# ",
  markdown = "<!-- ",
  html = "<!-- ",
}

local function overlay_state(ctx)
  ctx.view_state.overlay = ctx.view_state.overlay or {}
  return ctx.view_state.overlay
end

local function current_prefix(buf)
  local ft = vim.bo[buf].filetype
  return prefixes[ft] or "// "
end

local function anchor_positions(win, buf, count)
  local cursor = vim.api.nvim_win_get_cursor(win)[1]
  local height = math.max(1, vim.api.nvim_win_get_height(win))
  local top = cursor - math.floor(height / 2)
  local line_count = vim.api.nvim_buf_line_count(buf)
  top = math.max(2, top)
  local bottom = math.min(math.max(2, line_count - 1), top + height - 1)
  if bottom <= top then
    return { top }
  end
  local positions = {}
  local fractions = { 0.25, 0.5, 0.75 }
  for i = 1, math.min(count, 3) do
    local anchor = math.floor(top + (bottom - top) * fractions[i] + 0.5)
    if #positions == 0 or positions[#positions] ~= anchor then
      positions[#positions + 1] = math.max(top, math.min(bottom, anchor))
    end
  end
  return positions
end

local function clear(ctx)
  local state = overlay_state(ctx)
  if state.namespace then
    vim.api.nvim_buf_clear_namespace(ctx.target_buf, state.namespace, 0, -1)
  end
end

local function render_block(ctx, namespace, anchor, text, active)
  local prefix = current_prefix(ctx.target_buf)
  local width = math.max(20, vim.api.nvim_win_get_width(ctx.target_win) - #prefix - 4)
  local wrapped = utils.wrap_display(text, width)
  local virt_lines = {}
  local highlight = active and "GhostReaderComment" or "Comment"
  for _, segment in ipairs(wrapped) do
    virt_lines[#virt_lines + 1] = {
      { prefix .. segment, highlight },
    }
  end
  vim.api.nvim_buf_set_extmark(ctx.target_buf, namespace, anchor - 1, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    priority = 90,
  })
end

function M.supports(buf, win)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_buf_is_loaded(buf)
    and vim.api.nvim_win_get_buf(win) == buf
    and vim.bo[buf].buftype == ""
end

function M.start(ctx)
  if not M.supports(ctx.target_buf, ctx.target_win) then
    return false
  end
  local state = overlay_state(ctx)
  state.namespace = state.namespace or vim.api.nvim_create_namespace(namespace_name)
  vim.api.nvim_set_hl(0, "GhostReaderComment", { link = "Comment", default = true })
  return true
end

function M.render(ctx, frame)
  local state = overlay_state(ctx)
  if not state.namespace and not M.start(ctx) then
    return false
  end
  clear(ctx)

  local blocks = frame and frame.blocks or {}
  local visible = math.min(#blocks, ctx.config.reader.visible_blocks or 3)
  local anchors = anchor_positions(ctx.target_win, ctx.target_buf, visible)
  for i = 1, visible do
    render_block(ctx, state.namespace, anchors[i] or anchors[#anchors], blocks[i].text or "", blocks[i].active)
  end
  return true
end

function M.hide(ctx)
  clear(ctx)
  return true
end

function M.restore(ctx, frame)
  return M.render(ctx, frame)
end

function M.stop(ctx)
  clear(ctx)
  return true
end

function M.page_size(ctx)
  return ctx.config.reader.visible_blocks or 3
end

function M.segment_count(ctx, text)
  return #utils.wrap_display(text, math.max(20, vim.api.nvim_win_get_width(ctx.target_win) - 4))
end

function M.segment_text(ctx, text, index)
  return utils.wrap_display(text, math.max(20, vim.api.nvim_win_get_width(ctx.target_win) - 4))[index]
end

return M
