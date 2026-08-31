local M = {}

M.overlay = require("ghost-reader.renderer.overlay")
M.mirror = require("ghost-reader.renderer.mirror")
M.statusline = require("ghost-reader.renderer.statusline")

local renderers = {
  overlay = M.overlay,
  mirror = M.mirror,
  statusline = M.statusline,
}

function M.get(name)
  local renderer = renderers[name]
  if not renderer then
    error("unknown reader view: " .. tostring(name))
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
        if M.mirror.start(ctx) == false then
          return nil
        end
        return M.mirror
      end
    end
    ctx.mode = "overlay"
    ctx.view_name = "overlay"
    if renderer.start and renderer.start(ctx) == false then
      return nil
    end
    return renderer
  end
  ctx.mode = requested
  ctx.view_name = requested
  if renderer.start and renderer.start(ctx) == false then
    return nil
  end
  return renderer
end

return M
