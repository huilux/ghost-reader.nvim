local M = {}
local config = require("ghost-reader.config")
local utils = require("ghost-reader.utils")

M.config = nil

function M.setup(user_config)
  M.config = config.setup(user_config or {})
  utils.ensure_dir(M.config.cache_dir)
  utils.ensure_dir(M.config.data_dir)
  return M.config
end

function M.open(path)
  if not M.config then M.setup() end
  -- Will be implemented in Task 6
end

function M.close()
  -- Will be implemented in Task 6
end

return M
