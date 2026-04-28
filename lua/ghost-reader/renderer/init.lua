local M = {}
local sparse_notes = require("ghost-reader.renderer.sparse_notes")

function M.render(lines, opts)
  return sparse_notes.render(lines, opts)
end

return M
