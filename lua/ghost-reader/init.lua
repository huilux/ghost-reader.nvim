local M = {}
local config = require("ghost-reader.config")
local utils = require("ghost-reader.utils")
local session = require("ghost-reader.session")
local history = require("ghost-reader.history")

M.config = nil

local function select_book(preferred_mode)
  if not M.config then M.setup() end
  local entries = history.load(M.config)
  local items = {}
  for _, e in ipairs(entries) do
    table.insert(items, e.name .. "  (" .. e.path .. ")")
  end
  table.insert(items, "+ 输入新路径...")

  vim.ui.select(items, { prompt = "Select book:" }, function(_, idx)
    if not idx then return end
    local path
    if idx <= #entries then
      path = entries[idx].path
    else
      vim.ui.input({ prompt = "Book path: ", completion = "file" }, function(input)
        if input and input ~= "" then
          session.configure(M.config)
          session.start(vim.fn.expand(input), preferred_mode or "overlay")
        end
      end)
      return
    end
    session.configure(M.config)
    session.start(path, preferred_mode or "overlay")
  end)
end

function M.setup(user_config)
  M.config = config.setup(user_config or {})
  utils.ensure_dir(M.config.paths.cache_dir)
  utils.ensure_dir(M.config.paths.data_dir)
  return M.config
end

function M.open(path)
  if not M.config then M.setup() end
  if not path or path == "" then
    return select_book("overlay")
  end
  session.configure(M.config)
  session.start(path, "overlay")
end

function M.open_statusline(path)
  if not M.config then M.setup() end
  if not path or path == "" then
    return select_book("statusline")
  end
  session.configure(M.config)
  session.start(path, "statusline")
end

function M.close()
  session.stop()
end

function M.toc()
  session.toc()
end

return M
