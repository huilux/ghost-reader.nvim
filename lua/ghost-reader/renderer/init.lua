local M = {}

M.mirror = require("ghost-reader.renderer.mirror")
M.statusline = require("ghost-reader.renderer.statusline")

local renderers = {
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
  local requested = name or (ctx and ctx.mode) or "mirror"
  local renderer = M.get(requested)
  ctx.mode = requested
  ctx.view_name = requested
  if renderer.start and renderer.start(ctx) == false then
    return nil
  end
  return renderer
end

return M
