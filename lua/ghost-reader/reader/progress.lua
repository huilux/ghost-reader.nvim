local M = {}
local utils = require("ghost-reader.utils")

function M.save(book, state, config)
  local book_hash = utils.file_hash(book.path) or "unknown"
  local data_dir = config.data_dir .. "data/"
  utils.ensure_dir(data_dir)
  local path = data_dir .. book_hash .. ".json"

  local f = io.open(path, "w")
  if not f then return end
  f:write(vim.json.encode({
    book_path = book.path,
    chapter_index = state.chapter_index,
    line_offset = state.line_offset,
    last_read = os.time(),
  }))
  f:close()
end

function M.load(book, config)
  local book_hash = utils.file_hash(book.path) or "unknown"
  local data_dir = config.data_dir .. "data/"
  local path = data_dir .. book_hash .. ".json"

  local f = io.open(path, "r")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, data)
  if ok then return decoded end
  return nil
end

function M.show(book, state)
  local chapter = state.chapter_index
  local total = #book.chapters
  local pct = math.floor((chapter / total) * 100)
  local line = string.format("[ghost-reader] Chapter %d/%d · %d%%", chapter, total, pct)
  vim.notify(line, vim.log.levels.INFO)
end

return M
