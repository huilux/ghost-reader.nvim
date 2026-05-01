--[[
  bookshelf/parser_md.lua - Markdown 解析器

  角色：将 Markdown 文件解析为 book 数据结构。按标题（#）分割章节。
  只将一级标题（#）作为章节分割点，二级及以下的标题作为章节内容。

  本文件涉及的关键概念：
  - [Lua概念] string.match 多捕获组（一次返回多个匹配结果）
  - [Lua概念] # 运算符获取字符串长度（字节数）
  - [Neovim API] vim.fn.fnamemodify 路径修饰

  关联模块：被 bookshelf/init.lua 调用。
]]

local M = {}

function M.parse(path)
  local book = {
    format = "markdown",
    path = path,
    chapters = {},
    toc = {},
  }

  local f = io.open(path, "r")
  if not f then return book end

  local all_lines = {}
  for line in f:lines() do
    table.insert(all_lines, line)
  end
  f:close()

  -- 先检测文件中是否有 Markdown 标题
  local has_headings = false
  for _, line in ipairs(all_lines) do
    -- 检测以 # 开头后跟空格的行（Markdown 标题格式）
    if line:match("^#+%s") then
      has_headings = true
      break
    end
  end

  -- 没有标题时，整个文件作为单个章节
  if not has_headings then
    local non_empty = {}
    for _, line in ipairs(all_lines) do
      if line ~= "" then table.insert(non_empty, line) end
    end
    table.insert(book.chapters, {
      -- [Neovim API] vim.fn.fnamemodify(path, ":t") 提取文件名（去掉目录路径）。
      -- 回忆：":t" = tail（仅文件名）。详见 utils.lua 或 history.lua 中的说明。
      title = vim.fn.fnamemodify(path, ":t"),
      lines = non_empty,
    })
    table.insert(book.toc, { title = book.chapters[1].title, level = 1, index = 1 })
    return book
  end

  -- 按标题分割章节
  local current_chapter = nil
  for _, line in ipairs(all_lines) do
    -- [Lua概念] string.match 可以有多个捕获组，返回多个值。
    -- "^(#+)%s+(.+)$" 解读：
    --   (#+) = 捕获一个或多个 # 号（标题级别标记）
    --   %s+  = 一个或多个空白
    --   (.+) = 捕获标题文本
    -- match 返回两个值：level = "##", title = "标题文本"
    local level, title = line:match("^(#+)%s+(.+)$")
    if level then
      -- [Lua概念] #level 获取字符串长度。
      -- 对于字符串，# 返回字节数（不是字符数！）。
      -- 但 # 号都是 ASCII 字符，所以字节数 = 字符数。
      -- 注意：对中文用 # 得到的是字节数（每个中文字 3 字节 UTF-8），不是字符数。
      local heading_level = #level
      table.insert(book.toc, {
        title = title,
        level = heading_level,
        index = #book.chapters + 1,
      })
      if heading_level == 1 then
        -- 只有一级标题 (#) 才创建新章节
        current_chapter = {
          title = title,
          lines = {},
        }
        table.insert(book.chapters, current_chapter)
        book.toc[#book.toc].index = #book.chapters
      elseif current_chapter then
        -- 二级及以下标题作为内容行保留在当前章节中
        table.insert(current_chapter.lines, line)
      end
    elseif current_chapter and line ~= "" then
      table.insert(current_chapter.lines, line)
    end
  end

  return book
end

return M
