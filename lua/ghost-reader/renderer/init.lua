local M = {}

local renderers = {
  minimal_diff = require("ghost-reader.renderer.minimal_diff"),
  clone_buffer = require("ghost-reader.renderer.clone_buffer"),
  sparse_notes = require("ghost-reader.renderer.sparse_notes"),
  code_camouflage = require("ghost-reader.renderer.code_camouflage"),
  dual_mode = require("ghost-reader.renderer.dual_mode"),
}

function M.render(lines, mode, opts)
  local renderer = renderers[mode]
  if not renderer then
    renderer = renderers.minimal_diff
  end
  return renderer.render(lines, opts)
end

return M
