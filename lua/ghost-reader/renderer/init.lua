local M = {}

local renderers = {
  minimal_diff = require("ghost-reader.renderer.minimal_diff"),
  code_camouflage = require("ghost-reader.renderer.code_camouflage"),
}

function M.render(lines, mode, opts)
  local renderer = renderers[mode]
  if not renderer then
    renderer = renderers.minimal_diff
  end
  return renderer.render(lines, opts)
end

return M
