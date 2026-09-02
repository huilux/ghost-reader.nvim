local M = {}
local utils = require("ghost-reader.utils")

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
  local mirror = ctx.view_state.mirror
  mirror.touched_buffers = mirror.touched_buffers or {}
  return mirror
end

local function buffer_style_config(ctx)
  local buffer = ctx.config and ctx.config.buffer or {}
  local style = buffer.style or "light"
  local style_config = buffer[style] or {}
  return style, style_config, 3
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
  if line_count <= needed then
    local rows = {}
    for row = 1, math.min(line_count, total) do
      rows[#rows + 1] = row
    end
    return rows
  end

  local rows = {}
  local row = math.floor((line_count - needed) / 2) + 1
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
  local total = 0
  for _, size in ipairs(sizes) do
    total = total + size
  end
  local gaps = math.max(0, #sizes - 1)
  if line_count <= total + gaps then
    return light_rows(line_count, sizes)
  end

  local rows = {}
  local previous_end = 0
  local index = 1
  for group, size in ipairs(sizes) do
    local available = math.max(1, line_count - size)
    local row = math.floor(available * group / (#sizes + 1)) + 1
    row = math.max(row, previous_end + 2)
    if row + size - 1 > line_count then
      row = line_count - size + 1
    end
    for offset = 0, size - 1 do
      rows[index] = row + offset
      index = index + 1
    end
    previous_end = row + size - 1
  end
  return rows
end

local function visible_range(ctx)
  local range = vim.api.nvim_win_call(ctx.target_win, function()
    return { vim.fn.line("w0"), vim.fn.line("w$") }
  end)
  local top, bottom = range[1], range[2]
  local line_count = vim.api.nvim_buf_line_count(ctx.target_buf)
  top = math.max(1, math.min(top, line_count))
  bottom = math.max(top, math.min(bottom, line_count))
  return top, bottom
end

local function anchor_rows(ctx, count)
  local top, bottom = visible_range(ctx)
  local available = bottom - top + 1
  count = math.min(count, available)
  if count <= 0 then
    return {}
  end

  local style, style_config, fallback = buffer_style_config(ctx)
  local max_consecutive = math.min(style_config.max_consecutive_lines or count, count)
  max_consecutive = math.max(1, max_consecutive > 0 and max_consecutive or fallback)
  local sizes = group_sizes(count, max_consecutive)
  local local_rows
  if style == "strong" then
    local_rows = strong_rows(available, sizes)
  else
    local_rows = light_rows(available, sizes)
  end

  local rows = {}
  local used = {}
  for _, row in ipairs(local_rows) do
    local absolute = top + row - 1
    if not used[absolute] then
      rows[#rows + 1] = absolute
      used[absolute] = true
    end
  end
  return rows
end

local function clear_buffer(mirror, buf)
  if mirror.namespace and buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, mirror.namespace, 0, -1)
  end
end

local function clear_marks(ctx)
  local mirror = state(ctx)
  clear_buffer(mirror, ctx.target_buf)
  mirror.rendered_rows = nil
  mirror.reader_rows = nil
  mirror.rendered_blocks = nil
  mirror.rendered_by_key = nil
  mirror.mark_ids = nil
  mirror.active_row = nil
end

local function display_width(text)
  return vim.fn.strwidth(text or "")
end

local function render_text(ctx, text)
  local filetype = vim.bo[ctx.target_buf].filetype
  local prefix, suffix = comment_parts(filetype)
  local width = math.max(20, vim.api.nvim_win_get_width(ctx.target_win))
  local content = prefix .. (text or "") .. suffix
  local padding = math.max(0, width - display_width(content))
  return content .. string.rep(" ", padding)
end

local function activate(ctx, row)
  local mirror = state(ctx)
  if not mirror.namespace or not row then
    return false
  end
  mirror.active_row = row
  if vim.api.nvim_win_is_valid(ctx.target_win)
    and vim.api.nvim_win_get_buf(ctx.target_win) == ctx.target_buf then
    local cursor = vim.api.nvim_win_get_cursor(ctx.target_win)
    vim.api.nvim_win_set_cursor(ctx.target_win, { row, cursor[2] })
  end
  return true
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
  local mirror = state(ctx)
  mirror.namespace = mirror.namespace or vim.api.nvim_create_namespace(namespace_name)
  vim.api.nvim_set_hl(0, "GhostReaderMirror", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "GhostReaderMirrorActive", { link = "CursorLine", default = true })
  mirror.touched_buffers[ctx.target_buf] = true
  return true
end

function M.render(ctx, frame)
  local mirror = state(ctx)
  if not mirror.namespace and not M.start(ctx) then
    return false
  end
  if not M.supports(ctx.target_buf, ctx.target_win) then
    return false
  end

  for buf in pairs(mirror.touched_buffers) do
    clear_buffer(mirror, buf)
  end
  mirror.touched_buffers[ctx.target_buf] = true

  local blocks = visible_lines(ctx, frame)
  local current_key = block_key(blocks[1]) or position_key(frame and frame.position)
  local previous_rows = mirror.rendered_rows
  local previous_row = current_key and mirror.rendered_by_key and mirror.rendered_by_key[current_key]
  local rows = previous_row and previous_rows and #previous_rows >= #blocks and previous_rows or anchor_rows(ctx, #blocks)
  local rendered_blocks = {}
  mirror.mark_ids = {}
  for i = 1, math.min(#blocks, #rows) do
    local block = blocks[i]
    local row = rows[i]
    local text = render_text(ctx, block.text)
    local mark = vim.api.nvim_buf_set_extmark(ctx.target_buf, mirror.namespace, row - 1, 0, {
      virt_text = {{text, block.active and "GhostReaderMirrorActive" or "GhostReaderMirror"}},
      virt_text_pos = "overlay",
      virt_text_hide = true,
      priority = 90,
    })
    rendered_blocks[i] = block
    mirror.mark_ids[i] = mark
  end

  mirror.rendered_rows = rows
  mirror.reader_rows = rows
  mirror.rendered_blocks = rendered_blocks
  mirror.rendered_by_key = {}
  for i, block in ipairs(rendered_blocks) do
    local key = block_key(block)
    if key then
      mirror.rendered_by_key[key] = rows[i]
    end
  end
  activate(ctx, previous_row or rows[1])
  return true
end

function M.reader_buf(ctx)
  return ctx.target_buf
end

function M.hide(ctx)
  clear_marks(ctx)
  return true
end

function M.restore(ctx, frame)
  return M.render(ctx, frame)
end

function M.stop(ctx)
  local mirror = state(ctx)
  for buf in pairs(mirror.touched_buffers) do
    clear_buffer(mirror, buf)
  end
  mirror.namespace = nil
  mirror.touched_buffers = {}
  mirror.rendered_rows = nil
  mirror.reader_rows = nil
  mirror.rendered_blocks = nil
  mirror.rendered_by_key = nil
  mirror.mark_ids = nil
  mirror.active_row = nil
  return true
end

function M.page_size(ctx)
  local _, style_config, fallback = buffer_style_config(ctx)
  local limit = style_config.visible_lines or fallback
  if not M.supports(ctx.target_buf, ctx.target_win) then
    return limit
  end
  return math.max(1, math.min(limit, vim.api.nvim_win_get_height(ctx.target_win), vim.api.nvim_buf_line_count(ctx.target_buf)))
end

function M.segment_count(ctx, text)
  local prefix, suffix = comment_parts(vim.bo[ctx.target_buf].filetype)
  local width = math.max(20, vim.api.nvim_win_get_width(ctx.target_win) - display_width(prefix) - display_width(suffix) - 2)
  return #utils.wrap_display(text or "", width)
end

function M.segment_text(ctx, text, index)
  local prefix, suffix = comment_parts(vim.bo[ctx.target_buf].filetype)
  local width = math.max(20, vim.api.nvim_win_get_width(ctx.target_win) - display_width(prefix) - display_width(suffix) - 2)
  return utils.wrap_display(text or "", width)[index]
end

return M
