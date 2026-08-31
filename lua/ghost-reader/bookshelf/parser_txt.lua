--[[
  bookshelf/parser_txt.lua - 纯文本解析器

  角色：将纯文本文件（.txt）解析为统一的"book"数据结构。
  自动检测章节标题（支持中文"第X章"和英文"Chapter X"格式）。
  如果文件没有章节标题，则按固定行数分页。

  本文件涉及的关键概念：
  - [Lua概念] 字符模式中的字符类（%d、[...] 等）
  - [Lua概念] for...in 迭代器（f:lines() 逐行读取）
  - [Lua概念] ipairs 有序遍历
  - [Lua概念] table.insert 插入元素
  - [Lua概念] math.floor / math.min 数学函数
  - [Lua概念] # 运算符获取表长度

  关联模块：被 bookshelf/init.lua 调用。
]]

local M = {}

-- 章节标题的正则模式列表。
-- [Lua概念] Lua 表可以用 { val1, val2, ... } 直接创建数组（整数索引从 1 开始）。
local default_chapter_patterns = {
  -- [Lua概念] Lua 字符模式中的字符类：
  --   %d = 数字（0-9）
  --   %s = 空白字符
  --   [一二三四五六七八九十百千万] = 自定义字符集，匹配集合中的任意一个字符
  --   [章节回卷部篇] = 自定义字符集
  --   + = 前面的模式重复一次或多次
  --   ^ = 锚定到行首
  -- 这个模式匹配："第一章"、"第12节"、"第三回"等中文章节标题
  "^第[一二三四五六七八九十百千万%d]+[章节回卷部篇]",
  -- 匹配英文章节："Chapter 1"、"Chapter 12" 等
  "^Chapter%s+%d+",
  -- 匹配大写："CHAPTER 1" 等
  "^CHAPTER%s+%d+",
  -- 匹配数字开头："1. xxx"、"12. xxx" 等
  "^%d+%.",
}

-- 检查一行文本是否是章节标题
local function match_chapter(line, patterns)
  -- 回忆：ipairs 按顺序遍历数组索引（见 history.lua）
  for _, pat in ipairs(patterns) do
    if line:match(pat) then
      -- 中文章节标题需要额外判断：避免把"第三章中提到..."这样的句子误识别为标题。
      -- 启发式规则：如果章节标记后面紧跟的不是空格或行尾，
      -- 且包含句末标点，则认为是普通句子而非标题。
      if pat:find("章节回卷部篇") then
        local after = line:match("^第[一二三四五六七八九十百千万%d]+[章节回卷部篇](.*)")
        if after and #after > 0 and not after:match("^[%s ]") then
          if after:match("[。！？，、；：]") then
            return false
          end
        end
      end
      return true
    end
  end
  return false
end

-- [Lua概念] Lua 函数可以返回多个值，常用约定：
--   成功时返回 result
--   失败时返回 nil, "error message"
function M.parse(path, opts)
  opts = opts or {}
  local patterns = opts.chapter_patterns or default_chapter_patterns
  local lines_per_page = opts.lines_per_page or 50

  -- 这是本插件中所有解析器共用的"book"数据结构约定：
  --   format: 文件格式标识
  --   path: 文件路径
  --   chapters: 章节数组，每个元素是 { title, lines }
  --   toc: 目录数组，每个元素是 { title, level, index }
  local book = {
    format = "txt",
    path = path,
    chapters = {},
    toc = {},
  }

  local f = io.open(path, "r")
  if not f then return nil, "file not found: " .. path end

  local all_lines = {}
  -- [Lua概念] for var in iterator do ... end 是 Lua 的泛型循环。
  -- f:lines() 返回一个迭代器函数，每次调用返回文件的下一行，文件读完返回 nil（循环结束）。
  for line in f:lines() do
    -- 回忆：table.insert(t, value) 在数组末尾添加元素（见 history.lua）
    table.insert(all_lines, line)
  end
  f:close()

  local current_chapter = nil
  local has_chapters = false

  for _, line in ipairs(all_lines) do
    if match_chapter(line, patterns) then
      has_chapters = true
      current_chapter = {
        title = line,
        lines = {},
      }
      table.insert(book.chapters, current_chapter)
      -- [Lua概念] #book.chapters 获取数组当前长度。
      -- 因为上面刚 insert 过，所以 #book.chapters 就是新章节的索引。
      table.insert(book.toc, { title = line, level = 1, index = #book.chapters })
    elseif current_chapter then
      if line ~= "" then
        table.insert(current_chapter.lines, line)
      end
    end
  end

  -- 如果没有检测到章节标题，按固定行数分页
  if not has_chapters then
    -- [Lua概念] 数值 for 循环：for i = start, stop, step do ... end
    -- 这里步长为 lines_per_page，每次跳过一页的行数。
    for i = 1, #all_lines, lines_per_page do
      local chunk = {}
      -- [Lua概念] math.min(a, b) 返回较小值，防止超出数组范围。
      for j = i, math.min(i + lines_per_page - 1, #all_lines) do
        if all_lines[j] ~= "" then
          table.insert(chunk, all_lines[j])
        end
      end
      -- [Lua概念] math.floor(x) 向下取整。
      table.insert(book.chapters, {
        title = string.format("Page %d", math.floor(i / lines_per_page) + 1),
        lines = chunk,
      })
      table.insert(book.toc, {
        title = book.chapters[#book.chapters].title,
        level = 1,
        index = #book.chapters,
      })
    end
  end

  return book
end

return M
