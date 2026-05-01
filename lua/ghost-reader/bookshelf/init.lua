--[[
  bookshelf/init.lua - 书籍解析调度器

  角色：检测文件格式，将解析任务分发给对应的解析器模块。
  维护 current_book 作为模块级状态。

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

-- [Lua概念] 模块级变量：在模块作用域中定义的局部变量。
-- 因为 Lua 的模块只会被 require() 加载一次（结果会被缓存），
-- 所以这个变量会在多次函数调用之间保持其值。
-- 这类似于其他语言中的"私有静态变量"或"模块私有状态"。
local current_book = nil

function M.open(path, opts)
  opts = opts or {}
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

  -- [Lua概念] Lua 函数支持多返回值。
  -- 这里 parser.parse 可能返回 book, nil（成功）或 nil, err（失败）。
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
