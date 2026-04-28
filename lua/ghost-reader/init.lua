local M = {}
local config = require("ghost-reader.config")
local utils = require("ghost-reader.utils")
local reader = require("ghost-reader.reader")

M.config = nil

function M.setup(user_config)
  M.config = config.setup(user_config or {})
  utils.ensure_dir(M.config.cache_dir)
  utils.ensure_dir(M.config.data_dir)
  return M.config
end

function M.open(path)
  if not M.config then M.setup() end
  return reader.open(path, M.config)
end

function M.close()
  reader.close()
end

function M.toc()
  local reader = require("ghost-reader.reader")
  if not reader.state then return end
  local book = reader.state.book
  local items = {}
  for _, entry in ipairs(book.toc) do
    table.insert(items, entry.title)
  end
  vim.ui.select(items, { prompt = "Table of Contents:" }, function(_, idx)
    if idx then reader.go_to_chapter(idx) end
  end)
end

return M
