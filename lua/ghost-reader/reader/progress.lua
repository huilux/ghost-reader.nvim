local M = {}

local utils = require("ghost-reader.utils")

local function data_path(book, config)
  local book_hash = utils.file_hash(book.path) or "unknown"
  local data_dir = (config.paths and config.paths.data_dir) or (vim.fn.stdpath("data") .. "/ghost-reader/")
  local path = data_dir .. "data/"
  utils.ensure_dir(path)
  return path .. book_hash .. ".json"
end

local function is_positive_integer(value)
  return type(value) == "number" and value > 0 and math.floor(value) == value
end

local function total_lines(book)
  local total = 0
  for _, chapter in ipairs(book.chapters or {}) do
    total = total + #(chapter.lines or {})
  end
  return total
end

local function completed_lines(book, position)
  local completed = 0
  for chapter_index = 1, math.max(0, position.chapter_index - 1) do
    completed = completed + #(book.chapters[chapter_index].lines or {})
  end
  return completed + math.max(0, position.line_index - 1)
end

function M.save(book, position, config)
  local path = data_path(book, config)
  local f = io.open(path, "w")
  if not f then
    return
  end
  f:write(vim.json.encode({
    version = 2,
    book_path = book.path,
    position = {
      chapter_index = position.chapter_index,
      line_index = position.line_index,
      segment_index = position.segment_index,
    },
    last_read = os.time(),
  }))
  f:close()
end

function M.load(book, config)
  local path = data_path(book, config)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()

  local ok, decoded = pcall(vim.json.decode, data)
  if not ok or type(decoded) ~= "table" or decoded.version ~= 2 or type(decoded.position) ~= "table" then
    return nil
  end

  local position = decoded.position
  if not (is_positive_integer(position.chapter_index) and is_positive_integer(position.line_index) and is_positive_integer(position.segment_index)) then
    return nil
  end

  return {
    version = 2,
    book_path = decoded.book_path,
    position = {
      chapter_index = position.chapter_index,
      line_index = position.line_index,
      segment_index = position.segment_index,
    },
    last_read = decoded.last_read,
  }
end

function M.show(book, position)
  local total = math.max(1, total_lines(book))
  local done = completed_lines(book, position)
  local pct = math.floor((done / total) * 100)
  local chapter_total = #(book.chapters or {})
  local chapter_line_total = #(book.chapters[position.chapter_index] and book.chapters[position.chapter_index].lines or {})
  local line = string.format(
    "Chapter %d/%d · Line %d/%d · %d%%",
    position.chapter_index,
    chapter_total,
    position.line_index,
    math.max(1, chapter_line_total),
    pct
  )
  utils.notify(line)
end

return M
