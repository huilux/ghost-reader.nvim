local M = {}
local config = require("ghost-reader.config")
local utils = require("ghost-reader.utils")
local reader = require("ghost-reader.reader")
local history = require("ghost-reader.history")
local reader_statusline = require("ghost-reader.reader.statusline")

M.config = nil

function M.setup(user_config)
  M.config = config.setup(user_config or {})
  utils.ensure_dir(M.config.cache_dir)
  utils.ensure_dir(M.config.data_dir)
  return M.config
end

function M.open(path)
  if not M.config then M.setup() end
  local ok = reader.open(path, M.config)
  if ok then
    history.record(path, M.config)
  end
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

function M.select_book()
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
        if input and input ~= "" then M.open(vim.fn.expand(input)) end
      end)
      return
    end
    local mode_items = { "sparse_notes (全屏)", "statusline (状态栏)" }
    vim.ui.select(mode_items, { prompt = "Reading mode:" }, function(_, mode_idx)
      if not mode_idx then M.open(path); return end
      if mode_idx == 1 then
        M.open(path)
      else
        reader_statusline.start(path, M.config)
      end
    end)
  end)
end

return M
