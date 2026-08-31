local M = {}

M.overlay = require("ghost-reader.renderer.overlay")
M.mirror = require("ghost-reader.renderer.mirror")
M.statusline = require("ghost-reader.renderer.statusline")
M.legacy = require("ghost-reader.renderer.sparse_notes")

function M.create(mode, ctx)
  if mode == "mirror" then
    return M.mirror
  end
  if mode == "statusline" then
    return M.statusline
  end
  return M.overlay
end

function M.render(mode, ctx, frame)
  if type(mode) == "table" and ctx == nil then
    return M.legacy.render(mode)
  end
  return M.create(mode, ctx).render(ctx, frame)
end

return M
