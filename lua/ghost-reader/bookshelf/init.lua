local M = {}

local parsers = {
  txt = require("ghost-reader.bookshelf.parser_txt"),
  markdown = require("ghost-reader.bookshelf.parser_md"),
  epub = require("ghost-reader.bookshelf.parser_epub"),
}

local current_book = nil

function M.open(path, opts)
  opts = opts or {}
  local utils = require("ghost-reader.utils")
  local fmt = utils.detect_format(path)
  if not fmt then
    return nil, "unsupported format: " .. (path:match("%.([^%.]+)$") or "unknown")
  end

  local parser = parsers[fmt]
  if not parser then
    return nil, "no parser for format: " .. fmt
  end

  local book, err = parser.parse(path, opts)
  if err then return nil, err end

  current_book = book
  current_book.format = fmt
  return book
end

function M.get_current()
  return current_book
end

function M.close()
  current_book = nil
end

return M
