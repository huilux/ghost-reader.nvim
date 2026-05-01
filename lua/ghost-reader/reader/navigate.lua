--[[
  reader/navigate.lua - 翻页/翻章导航逻辑

  角色：纯逻辑模块，处理翻页、翻章、跳转等导航操作。
  不涉及任何 Neovim API 调用——所有函数只操作 state 表。
  这种设计使得导航逻辑可以在没有 Neovim 的环境中测试。

  本文件涉及的关键概念：
  - [Lua概念] 表作为引用传递（函数内修改影响调用方）
  - [Lua概念] 多返回值用作状态标记 (state, success)
  - [Lua概念] math.min 数值比较

  关联模块：被 reader/init.lua 和 reader/statusline.lua 调用。
]]

local M = {}

-- 获取当前页面要显示的行
function M.get_page_lines(chapter_lines, offset, page_size)
  local lines = {}
  -- 从 offset+1 开始，取 page_size 行（或到章节末尾）
  for i = offset + 1, math.min(offset + page_size, #chapter_lines) do
    table.insert(lines, chapter_lines[i])
  end
  return lines
end

-- [Lua概念] 所有导航函数都遵循相同的签名：
--   function M.xxx(state, ...) → return state, success
-- state 是一个表，包含 { book, chapter_index, line_offset, ... }。
-- [Lua概念] Lua 中表是引用类型（传递的是指针），
-- 所以函数内修改 state.chapter_index 会直接影响调用方的 state。
-- 返回 state 只是为了方便链式调用，不是必须的。
-- 第二个返回值是布尔值：true = 成功翻页，false = 已到边界。

function M.next_page(state, page_size)
  local new_offset = state.line_offset + page_size
  local chapter = state.book.chapters[state.chapter_index]
  if not chapter then return state, false end
  if new_offset >= #chapter.lines then
    -- 当前章节剩余内容不够一页，自动跳到下一章
    return M.next_chapter(state)
  end
  state.line_offset = new_offset
  return state, true
end

function M.prev_page(state, page_size)
  local new_offset = state.line_offset - page_size
  if new_offset < 0 then
    -- 已到当前章节开头，跳到上一章
    return M.prev_chapter(state)
  end
  state.line_offset = new_offset
  return state, true
end

function M.next_chapter(state)
  if state.chapter_index >= #state.book.chapters then
    -- 已是最后一章，无法继续
    return state, false
  end
  state.chapter_index = state.chapter_index + 1
  state.line_offset = 0
  return state, true
end

function M.prev_chapter(state)
  if state.chapter_index <= 1 then
    -- 已是第一章，无法继续
    return state, false
  end
  state.chapter_index = state.chapter_index - 1
  state.line_offset = 0
  return state, true
end

function M.go_to_chapter(state, chapter_index)
  if chapter_index < 1 or chapter_index > #state.book.chapters then
    return state, false
  end
  state.chapter_index = chapter_index
  state.line_offset = 0
  return state, true
end

return M
