local layout = require("ghost-reader.renderer.mirror_layout")
local utils = require("ghost-reader.utils")

local M = {}
local namespace_name = "GhostReaderMirror"
local provider_registry = {}
local installed_providers = {}

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

local function mirror_config(ctx)
  local buffer = ctx.config and ctx.config.buffer or {}
  return buffer.layout or {}, buffer.virt_text_priority or 1000
end

local function position_key(position)
  if not position or position.chapter_index == nil or position.line_index == nil then return nil end
  return table.concat({ position.chapter_index, position.line_index, position.segment_index or 1 }, ":")
end

local function block_key(block)
  return position_key(block and (block.position or block))
end

local function comment_parts(buf)
  return unpack(comment_prefixes[vim.bo[buf].filetype] or { "// ", "" })
end

local function display_width(text)
  return vim.fn.strwidth(text or "")
end

local function usable_width(ctx)
  local info = vim.fn.getwininfo(ctx.target_win)[1] or {}
  return math.max(1, vim.api.nvim_win_get_width(ctx.target_win) - (info.textoff or 0))
end

local function text_width(ctx)
  local prefix, suffix = comment_parts(ctx.target_buf)
  return math.max(1, usable_width(ctx) - display_width(prefix) - display_width(suffix))
end

local function wrapped_lines(ctx, text)
  local lines = vim.split(text or "", "\n", { plain = true })
  local wrapped = {}
  for _, line in ipairs(lines) do
    for _, segment in ipairs(utils.wrap_display(line, text_width(ctx))) do
      wrapped[#wrapped + 1] = segment
    end
  end
  return #wrapped > 0 and wrapped or { "" }
end

local function is_folded(ctx, row)
  return vim.api.nvim_win_call(ctx.target_win, function()
    return vim.fn.foldclosed(row) ~= -1
  end)
end

local function layout_signature(ctx, opts)
  return table.concat({
    ctx.target_buf,
    ctx.target_win,
    vim.api.nvim_buf_line_count(ctx.target_buf),
    usable_width(ctx),
    opts.region_lines or 0,
    opts.max_blocks_per_region or 0,
    opts.max_lines_per_block or 0,
    opts.min_gap_lines or 0,
    opts.max_total_blocks or 0,
    opts.edge_padding or 0,
  }, ":")
end

local function ensure_slots(ctx)
  local mirror = state(ctx)
  local opts = mirror_config(ctx)
  local signature = layout_signature(ctx, opts)
  if mirror.layout_signature ~= signature then
    mirror.slots = layout.slots(vim.api.nvim_buf_line_count(ctx.target_buf), opts, function(row)
      return is_folded(ctx, row)
    end)
    mirror.layout_signature = signature
    mirror.prepared_by_row = nil
    mirror.rendered_by_key = nil
    mirror.reader_rows = nil
    mirror.active_row = nil
  end
  return mirror.slots or {}
end

local function padded_comment(ctx, row, text)
  local source = vim.api.nvim_buf_get_lines(ctx.target_buf, row - 1, row, false)[1] or ""
  local indent = source:match("^%s*") or ""
  local prefix, suffix = comment_parts(ctx.target_buf)
  local width = usable_width(ctx)
  local content = indent .. prefix .. (text or "") .. suffix
  if display_width(content) > width then
    content = prefix .. (text or "") .. suffix
  end
  return content .. string.rep(" ", math.max(0, width - display_width(content)))
end

local function prepare_rows(ctx, blocks, slots)
  local mirror = state(ctx)
  local prepared_by_row = {}
  local rendered_by_key = {}
  local reader_rows = {}
  for index = 1, math.min(#blocks, #slots) do
    local slot = slots[index]
    local block = blocks[index]
    local key = block_key(block)
    reader_rows[index] = slot.row
    if key then rendered_by_key[key] = slot.row end
    local content = type(block.text) == "table" and block.text or { block.text or "" }
    for offset = 0, math.min(slot.height, #content) - 1 do
      local row = slot.row + offset
      prepared_by_row[row] = {
        virt_text = {{ padded_comment(ctx, row, content[offset + 1] or ""), "GhostReaderMirror" }},
      }
    end
  end
  mirror.prepared_by_row = prepared_by_row
  mirror.rendered_by_key = rendered_by_key
  mirror.reader_rows = reader_rows
end

local function request_redraw()
  vim.cmd("redraw")
end

local function capture_view(ctx, mirror)
  if not mirror.saved_view then
    mirror.saved_view = vim.api.nvim_win_call(ctx.target_win, vim.fn.winsaveview)
  end
end

local function restore_view(ctx, mirror)
  if mirror.saved_view and vim.api.nvim_win_is_valid(ctx.target_win) then
    vim.api.nvim_win_call(ctx.target_win, function()
      vim.fn.winrestview(mirror.saved_view)
    end)
  end
  mirror.saved_view = nil
end

local function activate(ctx, mirror, row)
  if not row or not vim.api.nvim_win_is_valid(ctx.target_win)
    or vim.api.nvim_win_get_buf(ctx.target_win) ~= ctx.target_buf then
    return false
  end
  mirror.active_row = row
  local cursor = vim.api.nvim_win_get_cursor(ctx.target_win)
  vim.api.nvim_win_set_cursor(ctx.target_win, { row, 0 })
  return true
end

local function draw_window(namespace, win, buf, top, bottom)
  local mirror = provider_registry[namespace]
  if not mirror or not mirror.visible or mirror.target_win ~= win or mirror.target_buf ~= buf then
    return false
  end
  for row = top + 1, bottom do
    local prepared = mirror.prepared_by_row and mirror.prepared_by_row[row]
    if prepared then
      vim.api.nvim_buf_set_extmark(buf, namespace, row - 1, 0, {
        ephemeral = true,
        virt_text = prepared.virt_text,
        virt_text_pos = "overlay",
        virt_text_hide = true,
        hl_mode = "replace",
        priority = mirror.priority,
      })
    end
  end
end

local function install_provider(namespace)
  if installed_providers[namespace] then return end
  vim.api.nvim_set_decoration_provider(namespace, {
    on_win = function(_, win, buf, top, bottom)
      return draw_window(namespace, win, buf, top, bottom)
    end,
  })
  installed_providers[namespace] = true
end

function M.supports(buf, win)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_buf_is_loaded(buf)
    and vim.api.nvim_win_get_buf(win) == buf
    and vim.bo[buf].buftype == ""
end

function M.start(ctx)
  if not M.supports(ctx.target_buf, ctx.target_win) then return false end
  local mirror = state(ctx)
  mirror.namespace = mirror.namespace or vim.api.nvim_create_namespace(namespace_name)
  vim.api.nvim_set_hl(0, "GhostReaderMirror", { link = "Comment", default = true })
  install_provider(mirror.namespace)
  return true
end

function M.render(ctx, frame)
  if not M.supports(ctx.target_buf, ctx.target_win) then return false end
  local mirror = state(ctx)
  if not mirror.namespace and not M.start(ctx) then return false end
  local opts, priority = mirror_config(ctx)
  local slots = ensure_slots(ctx)
  capture_view(ctx, mirror)

  local active_key = position_key(frame and frame.position)
  if not active_key then
    for _, block in ipairs((frame and frame.blocks) or {}) do
      if block.active then
        active_key = block_key(block)
        break
      end
    end
  end
  local anchor = active_key and mirror.rendered_by_key and mirror.rendered_by_key[active_key]
  if not anchor then
    prepare_rows(ctx, (frame and frame.blocks) or {}, slots)
    active_key = active_key or block_key((frame and frame.blocks or {})[1])
    anchor = active_key and mirror.rendered_by_key[active_key] or mirror.reader_rows[1]
  end

  if anchor and is_folded(ctx, anchor) then
    M.invalidate_layout(ctx)
    slots = ensure_slots(ctx)
    prepare_rows(ctx, (frame and frame.blocks) or {}, slots)
    anchor = active_key and mirror.rendered_by_key[active_key] or mirror.reader_rows[1]
  end

  mirror.target_win = ctx.target_win
  mirror.target_buf = ctx.target_buf
  mirror.priority = priority
  mirror.visible = true
  provider_registry[mirror.namespace] = mirror
  request_redraw()
  activate(ctx, mirror, anchor)
  return true
end

function M.reader_buf(ctx)
  return ctx.target_buf
end

function M.hide(ctx)
  local mirror = state(ctx)
  mirror.visible = false
  if mirror.namespace then provider_registry[mirror.namespace] = mirror end
  request_redraw()
  restore_view(ctx, mirror)
  return true
end

function M.restore(ctx, frame)
  return M.render(ctx, frame)
end

function M.invalidate_layout(ctx)
  local mirror = state(ctx)
  mirror.layout_signature = nil
end

function M.stop(ctx)
  local mirror = state(ctx)
  mirror.visible = false
  if mirror.namespace then provider_registry[mirror.namespace] = nil end
  request_redraw()
  restore_view(ctx, mirror)
  mirror.namespace = nil
  mirror.slots = nil
  mirror.layout_signature = nil
  mirror.prepared_by_row = nil
  mirror.rendered_by_key = nil
  mirror.reader_rows = nil
  mirror.active_row = nil
  mirror.target_win = nil
  mirror.target_buf = nil
  mirror.priority = nil
  return true
end

function M.page_size(ctx)
  if not M.supports(ctx.target_buf, ctx.target_win) then
    local opts = mirror_config(ctx)
    return opts.max_total_blocks or 1
  end
  return #ensure_slots(ctx)
end

function M.segment_count(ctx, text)
  local opts = mirror_config(ctx)
  local lines = wrapped_lines(ctx, text)
  return math.max(1, math.ceil(#lines / math.max(1, opts.max_lines_per_block or 1)))
end

function M.segment_text(ctx, text, index)
  local opts = mirror_config(ctx)
  local per_block = math.max(1, opts.max_lines_per_block or 1)
  local lines = wrapped_lines(ctx, text)
  local first = ((index or 1) - 1) * per_block + 1
  local result = {}
  for current = first, math.min(first + per_block - 1, #lines) do
    result[#result + 1] = lines[current]
  end
  return result
end

return M
