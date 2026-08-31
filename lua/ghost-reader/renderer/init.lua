local M = {}

M.overlay = require("ghost-reader.renderer.overlay")
M.mirror = require("ghost-reader.renderer.mirror")
M.statusline = require("ghost-reader.renderer.statusline")
M.legacy = require("ghost-reader.renderer.sparse_notes")

local renderers = {
  overlay = M.overlay,
  mirror = M.mirror,
  statusline = M.statusline,
}

function M.get(name)
  local renderer = renderers[name]
  if not renderer then
    error("unknown renderer: " .. tostring(name))
  end
  return renderer
end

function M.create(ctx, name)
  local requested = name or (ctx and ctx.mode) or "overlay"
  local renderer = M.get(requested)
  if requested == "overlay" then
    local buf = ctx.target_buf or vim.api.nvim_get_current_buf()
    local win = ctx.target_win or vim.api.nvim_get_current_win()
    if not renderer.supports(buf, win) then
      if ctx.config and ctx.config.reader and ctx.config.reader.mirror_fallback ~= false then
        ctx.mode = "overlay"
        ctx.view_name = "mirror"
        return M.mirror
      end
    end
    ctx.mode = "overlay"
    ctx.view_name = "overlay"
    return renderer
  end
  ctx.mode = requested
  ctx.view_name = requested
  return renderer
end

function M.render(mode, ctx, frame)
  if type(mode) == "table" and ctx == nil then
    return M.legacy.render(mode)
  end
  local renderer = M.create(ctx, mode)
  local ok = renderer.render(ctx, frame)
  if ok == false then
    return false
  end
  return true
end

return M
