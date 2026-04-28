local M = {}
local utils = require("ghost-reader.utils")

local function history_path(config)
  local dir = config.data_dir .. "data/"
  utils.ensure_dir(dir)
  return dir .. "history.json"
end

function M.load(config)
  local path = history_path(config)
  local f = io.open(path, "r")
  if not f then return {} end
  local data = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, data)
  if ok and type(decoded) == "table" then return decoded end
  return {}
end

function M.save(config, entries)
  local path = history_path(config)
  local f = io.open(path, "w")
  if not f then return end
  f:write(vim.json.encode(entries))
  f:close()
end

function M.record(path, config)
  local entries = M.load(config)
  -- dedup: move existing to front
  for i, e in ipairs(entries) do
    if e.path == path then
      table.remove(entries, i)
      break
    end
  end
  table.insert(entries, 1, {
    path = path,
    name = vim.fn.fnamemodify(path, ":t"),
    last_opened = os.time(),
  })
  -- keep last 20
  if #entries > 20 then
    for i = #entries, 21, -1 do
      entries[i] = nil
    end
  end
  M.save(config, entries)
end

return M
