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

local function file_status(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end
  return stat
end

function M.parse(path)
  local book = {
    format = "markdown",
    path = path,
    chapters = {},
    toc = {},
  }

  local stat = file_status(path)
  if not stat then return nil, "file not found: " .. path end
  if stat.type ~= "file" then return nil, "file unreadable: " .. path end

  local f = io.open(path, "r")
  if not f then return nil, "file unreadable: " .. path end

  local all_lines = {}
  for line in f:lines() do
    table.insert(all_lines, line)
  end
  f:close()

  local implicit_title = vim.fn.fnamemodify(path, ":t")
  local current_chapter = nil
  local current_chapter_index = nil

  local function ensure_implicit_chapter()
    if not current_chapter then
      current_chapter = {
        title = implicit_title,
        lines = {},
      }
      table.insert(book.chapters, current_chapter)
      current_chapter_index = #book.chapters
    end
    return current_chapter_index
  end

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
      if heading_level > 1 and not current_chapter then
        ensure_implicit_chapter()
      end
      local toc_index = current_chapter and current_chapter_index or (#book.chapters + 1)
      table.insert(book.toc, {
        title = title,
        level = heading_level,
        index = toc_index,
      })
      if heading_level == 1 then
        -- 只有一级标题 (#) 才创建新章节
        current_chapter = {
          title = title,
          lines = {},
        }
        table.insert(book.chapters, current_chapter)
        current_chapter_index = #book.chapters
        book.toc[#book.toc].index = current_chapter_index
      elseif current_chapter then
        -- 二级及以下标题作为内容行保留在当前章节中
        table.insert(current_chapter.lines, line)
      end
    elseif line ~= "" then
      ensure_implicit_chapter()
      table.insert(current_chapter.lines, line)
    end
  end

  return book
end

return M
