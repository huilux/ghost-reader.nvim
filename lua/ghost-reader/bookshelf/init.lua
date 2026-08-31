--[[
  bookshelf/init.lua - 书籍解析调度器

  角色：检测文件格式，将解析任务分发给对应的解析器模块。
  这是一个无状态的打开入口，只负责选择解析器并校验最终 book 结构。

  本文件涉及的关键概念：
  - [Lua概念] 策略表模式（用表实现多态，无需类/继承）
  - [Lua概念] 模块级闭包状态（类似其他语言的私有静态变量）
  - [Lua概念] 多返回值约定（result, err）

  关联模块：调度 parser_txt、parser_md、parser_epub。
]]

local M = {}

-- [Lua概念] 策略表模式：用一张表将字符串键映射到模块引用。
-- 这样可以用 parsers[fmt] 动态选择解析器，而不用写一长串 if/elseif。
-- 这是 Lua 中实现多态的惯用方式（不需要类和继承）。
local parsers = {
  txt = require("ghost-reader.bookshelf.parser_txt"),
  markdown = require("ghost-reader.bookshelf.parser_md"),
  epub = require("ghost-reader.bookshelf.parser_epub"),
}

local function validate_book(book, path)
  local readable_lines = 0
  if type(book) == "table" and type(book.chapters) == "table" then
    for _, chapter in ipairs(book.chapters) do
      readable_lines = readable_lines + (type(chapter.lines) == "table" and #chapter.lines or 0)
    end
  end
  if type(book) ~= "table" or type(book.chapters) ~= "table" or #book.chapters == 0 or readable_lines == 0 then
    return nil, "book has no readable content: " .. path
  end
  return book
end

function M.open(path, parser_opts)
  parser_opts = parser_opts or {}
  local utils = require("ghost-reader.utils")
  local fmt = utils.detect_format(path)
  if not fmt then
    -- [Lua概念] 多返回值约定：出错时返回 nil, "error message"。
    -- path:match("%.([^%.]+)$") 提取扩展名（回忆 utils.lua 中的详细解释）。
    return nil, "unsupported format: " .. (path:match("%.([^%.]+)$") or "unknown")
  end

  -- 通过策略表动态获取对应格式的解析器
  local parser = parsers[fmt]
  if not parser then
    return nil, "no parser for format: " .. fmt
  end

  local book, err = parser.parse(path, parser_opts)
  if err then return nil, err end
  if book then
    book.format = fmt
  end
  return validate_book(book, path)
end

return M
