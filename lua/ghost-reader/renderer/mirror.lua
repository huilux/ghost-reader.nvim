local M = {}
local utils = require("ghost-reader.utils")
local presets = require("ghost-reader.renderer.presets")

local namespace_name = "GhostReaderMirror"

local comment_prefixes = {
  lua = { "-- ", "" },
  python = { "# ", "" },
  javascript = { "// ", "" },
  typescript = { "// ", "" },
  typescriptreact = { "// ", "" },
  go = { "// ", "" },
  rust = { "// ", "" },
  java = { "// ", "" },
  c = { "// ", "" },
  cpp = { "// ", "" },
  sh = { "# ", "" },
  bash = { "# ", "" },
  zsh = { "# ", "" },
  markdown = { "<!-- ", " -->" },
  html = { "<!-- ", " -->" },
}

local function state(ctx)
  ctx.view_state.mirror = ctx.view_state.mirror or {}
  return ctx.view_state.mirror
end

local function buffer_style_config(ctx)
  local buffer = ctx.config and ctx.config.buffer or {}
  local style = buffer.style or "light"
  local style_config = buffer[style] or {}
  local fallback = 3
  return style, style_config, fallback
end

local function comment_parts(filetype)
  return unpack(comment_prefixes[filetype] or { "// ", "" })
end

local function position_key(position)
  if not position or position.chapter_index == nil or position.line_index == nil then
    return nil
  end
  return table.concat({ position.chapter_index, position.line_index, position.segment_index or 1 }, ":")
end

local function block_key(block)
  return position_key(block and (block.position or block))
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

  local buffer = ctx.config and ctx.config.buffer or {}
  local preset = presets.get(buffer.preset or (ctx.config and ctx.config.reader and ctx.config.reader.preset) or "random")
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

local function visible_lines(ctx, frame)
  local blocks = frame and frame.blocks or {}
  local _, style_config, fallback = buffer_style_config(ctx)
  local limit = style_config.visible_lines or fallback
  local visible = {}
  for i = 1, math.min(#blocks, limit) do
    visible[#visible + 1] = blocks[i]
  end
  return visible
end

local function ensure_skeleton_size(lines, minimum)
  while #lines < minimum do
    lines[#lines + 1] = ""
  end
end

local function group_sizes(count, max_consecutive)
  local sizes = {}
  local remaining = count
  while remaining > 0 do
    local size = math.min(max_consecutive, remaining)
    sizes[#sizes + 1] = size
    remaining = remaining - size
  end
  return sizes
end

local function light_rows(line_count, sizes)
  local total = 0
  for _, size in ipairs(sizes) do
    total = total + size
  end
  local needed = total + math.max(0, #sizes - 1)
  local start = math.max(1, math.floor((line_count - needed) / 2) + 1)
  local rows = {}
  local row = start
  local index = 1
  for group, size in ipairs(sizes) do
    for _ = 1, size do
      rows[index] = row
      index = index + 1
      row = row + 1
    end
    if group < #sizes then
      row = row + 1
    end
  end
  return rows
end

local function strong_rows(line_count, sizes)
  local rows = {}
  local previous_end = 0
  local index = 1
  for group, size in ipairs(sizes) do
    local available = math.max(1, line_count - size)
    local row = math.floor(available * group / (#sizes + 1)) + 1
    row = math.max(row, previous_end + 2)
    if row + size - 1 > line_count then
      row = math.max(1, line_count - size + 1)
    end
    for offset = 0, size - 1 do
      rows[index] = row + offset
      index = index + 1
    end
    previous_end = row + size - 1
  end
  return rows
end

local function build_lines(ctx, frame)
  local mirror = state(ctx)
  local skeleton = mirror.skeleton or {}
  local lines = vim.deepcopy(skeleton.lines or {})
  local blocks = visible_lines(ctx, frame)
  if #lines == 0 then
    lines = { "" }
  end

  local style, style_config, fallback = buffer_style_config(ctx)
  local max_consecutive = math.min(style_config.max_consecutive_lines or #blocks, #blocks)
  max_consecutive = math.max(1, max_consecutive > 0 and max_consecutive or fallback)
  local sizes = group_sizes(#blocks, max_consecutive)
  ensure_skeleton_size(lines, math.max(#lines, #blocks * 3 + 5))
  local positions
  if style == "strong" then
    positions = strong_rows(#lines, sizes)
  else
    positions = light_rows(#lines, sizes)
  end

  local prefix, suffix = comment_parts(skeleton.filetype)
  local rows = {}
  for i, block in ipairs(blocks) do
    local row = positions[i] or #lines
    rows[i] = row
    lines[row] = prefix .. (block.text or "") .. suffix
  end

  return lines, rows, blocks
end

local function activate(ctx, row)
  local mirror = state(ctx)
  if not mirror.buf or not vim.api.nvim_buf_is_valid(mirror.buf) or not row then
    return false
  end
  mirror.highlight_namespace = mirror.highlight_namespace or vim.api.nvim_create_namespace(namespace_name .. "Active")
  vim.api.nvim_set_hl(0, "GhostReaderMirrorActive", { link = "CursorLine", default = true })
  vim.api.nvim_buf_clear_namespace(mirror.buf, mirror.highlight_namespace, 0, -1)
  vim.api.nvim_buf_add_highlight(mirror.buf, mirror.highlight_namespace, "GhostReaderMirrorActive", row - 1, 0, -1)
  if vim.api.nvim_win_is_valid(ctx.target_win) and vim.api.nvim_win_get_buf(ctx.target_win) == mirror.buf then
    local cursor = vim.api.nvim_win_get_cursor(ctx.target_win)
    vim.api.nvim_win_set_cursor(ctx.target_win, { row, math.min(cursor[2], math.max(0, #(vim.api.nvim_buf_get_lines(mirror.buf, row - 1, row, false)[1] or "") - 1)) })
  end
  mirror.active_row = row
  return true
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
  return true
end

function M.render(ctx, frame)
  local mirror = state(ctx)
  if not mirror.buf or not vim.api.nvim_buf_is_valid(mirror.buf) then
    if not M.start(ctx) then
      return false
    end
  end
  local blocks = visible_lines(ctx, frame)
  local current_key = block_key(blocks[1]) or position_key(frame and frame.position)
  if current_key and mirror.rendered_by_key and mirror.rendered_by_key[current_key] then
    return activate(ctx, mirror.rendered_by_key[current_key])
  end

  local lines, rows, rendered_blocks = build_lines(ctx, frame)
  vim.bo[mirror.buf].modifiable = true
  vim.api.nvim_buf_set_lines(mirror.buf, 0, -1, false, lines)
  vim.bo[mirror.buf].modifiable = false
  mirror.reader_rows = rows
  mirror.rendered_blocks = rendered_blocks
  mirror.rendered_by_key = {}
  for i, block in ipairs(rendered_blocks) do
    local key = block_key(block)
    if key then
      mirror.rendered_by_key[key] = rows[i]
    end
  end
  activate(ctx, rows[1])
  return true
end

function M.reader_buf(ctx)
  local mirror = state(ctx)
  if mirror.buf and vim.api.nvim_buf_is_valid(mirror.buf) then
    return mirror.buf
  end
  return ctx.target_buf
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
  mirror.reader_rows = nil
  mirror.rendered_blocks = nil
  mirror.rendered_by_key = nil
  mirror.active_row = nil
  return true
end

function M.page_size(ctx)
  local _, style_config, fallback = buffer_style_config(ctx)
  return style_config.visible_lines or fallback
end

function M.segment_count(ctx, text)
  local mirror = state(ctx)
  local filetype = mirror.skeleton and mirror.skeleton.filetype or "lua"
  local prefix, suffix = comment_parts(filetype)
  local width = math.max(20, vim.api.nvim_win_get_width(ctx.target_win) - #prefix - #suffix - 2)
  return #utils.wrap_display(text or "", width)
end

function M.segment_text(ctx, text, index)
  local mirror = state(ctx)
  local filetype = mirror.skeleton and mirror.skeleton.filetype or "lua"
  local prefix, suffix = comment_parts(filetype)
  local width = math.max(20, vim.api.nvim_win_get_width(ctx.target_win) - #prefix - #suffix - 2)
  return utils.wrap_display(text or "", width)[index]
end

return M
