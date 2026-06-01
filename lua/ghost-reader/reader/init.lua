--[[
  reader/init.lua - 全屏阅读模式控制器

  角色：管理全屏阅读模式的完整生命周期——打开书籍、创建 Buffer、设置键映射、
  渲染内容、处理导航、保存进度、关闭清理。
  是全屏模式的中枢控制器，协调 bookshelf、navigate、progress、renderer、stealth 子模块。

  本文件涉及的关键概念：
  - [Neovim基础] Buffer 创建与类型（nofile、scratch）
  - [Neovim基础] Buffer 局部键映射原理（为什么用 { buffer = bufnr }）
  - [Neovim基础] Leader Key 概念与 <leader> 展开
  - [Neovim API] nvim_create_buf / nvim_set_current_buf Buffer 操作
  - [Neovim API] vim.bo[buf] Buffer 局部选项
  - [Neovim API] vim.keymap.set 键映射
  - [Neovim API] nvim_create_autocmd 自动命令
  - [Neovim API] nvim_buf_call 在 Buffer 上下文中执行函数

  关联模块：被主模块 init.lua 调用。协调 bookshelf、navigate、progress、renderer、stealth。
]]

local M = {}
local navigate = require("ghost-reader.reader.navigate")
local bookshelf = require("ghost-reader.bookshelf")
local utils = require("ghost-reader.utils")
local statusline = require("ghost-reader.stealth.statusline")
local renderer = require("ghost-reader.renderer")
local progress = require("ghost-reader.reader.progress")

-- [Lua概念] M.state 和 M.page_size 是模块级状态。
-- 回忆：模块级变量在多次函数调用之间保持值（见 bookshelf/init.lua 的 current_book）。
M.state = nil
M.page_size = 40

-- 打开一本书进入全屏阅读模式
function M.open(path, config)
  -- 如果已在阅读模式中，先清理旧状态
  if M.state then M.close() end

  local book, err = bookshelf.open(path)
  if err then
    utils.notify(err, vim.log.levels.ERROR)
    return false
  end

  -- [Neovim基础] nvim_get_current_buf() 获取当前活跃 Buffer 的编号。
  -- 保存下来以便退出阅读模式时恢复到原来的 Buffer。
  local prev_buf = vim.api.nvim_get_current_buf()
  -- [Neovim基础] nvim_create_buf(listed, scratch) 创建新 Buffer。
  --   listed=false: 不出现在 :ls 列表中（隐藏 Buffer）
  --   scratch=true:  临时 Buffer，不关联文件
  local buf = vim.api.nvim_create_buf(false, true)

  -- 构建阅读状态表
  local state = {
    book = book,
    buf = buf,
    prev_buf = prev_buf,
    chapter_index = 1,
    line_offset = 0,
    config = config,
  }

  -- 尝试恢复上次阅读进度
  local saved = progress.load(book, config)
  if saved then
    state.chapter_index = math.min(saved.chapter_index or 1, #book.chapters)
    state.line_offset = saved.line_offset or 0
  end

  M.state = state
  -- [Lua概念] math.floor 向下取整。
  -- vim.o.lines 获取编辑器的总行数（高度）。0.85 表示使用 85% 的屏幕高度作为一页。
  M.page_size = math.floor(vim.o.lines * 0.85)

  -- [Neovim基础] nvim_set_current_buf(buf) 将当前窗口切换到指定 Buffer。
  -- 用户会立刻看到新创建的阅读 Buffer。
  vim.api.nvim_set_current_buf(buf)
  -- [Neovim基础] vim.bo[buf] 设置 Buffer 局部选项。
  --   buftype = "nofile": 告诉 Neovim 这个 Buffer 不关联文件，不需要保存到磁盘。
  --   bufhidden = "hide": 当 Buffer 不可见时（切换到其他 Buffer）保持它存在内存中。
  --   modifiable = true: 允许修改 Buffer 内容（渲染器需要写入内容）。
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].modifiable = true

  -- 保存当前状态栏配置（用于伪装）
  statusline.save()
  -- 渲染当前页面内容
  M._render(state)
  -- 设置 Buffer 局部键映射
  M._set_keymaps(buf, config.keymaps)

  local book_name = vim.fn.fnamemodify(path, ":t:r")
  utils.notify(string.format("%s · %d chapters\nJ/K=内容跳转 ]c/[c=章节 <Esc><Esc>=老板键",
    book_name, #book.chapters))
  -- [Neovim基础] 自动命令（Autocmd）：在特定事件发生时自动执行回调。
  -- 这里注册了两个事件监听：
  --   BufUnload: Buffer 被卸载时（用户关闭或切换）保存进度
  --   CursorHold: 光标停留超过一定时间时保存进度（定时保存）
  -- { buffer = buf } 使 autocmd 仅在指定 Buffer 中生效。
  -- [Neovim基础] 当 Buffer 被删除时，与之关联的 buffer-local autocmd 会自动清理。
  vim.api.nvim_create_autocmd({ "BufUnload", "CursorHold" }, {
    buffer = buf,
    callback = function()
      if M.state then
        progress.save(M.state.book, M.state, M.state.config)
      end
    end,
  })
  -- 退出前恢复原始 buffer，确保 shada/session 捕获正确状态
  M._quit_augroup = vim.api.nvim_create_augroup("ghost-reader-quit-guard", { clear = true })
  vim.api.nvim_create_autocmd("QuitPre", {
    group = M._quit_augroup,
    callback = function()
      if M.state and vim.api.nvim_buf_is_valid(M.state.prev_buf) then
        progress.save(M.state.book, M.state, M.state.config)
        vim.api.nvim_set_current_buf(M.state.prev_buf)
      end
    end,
  })
  return true
end

-- 渲染当前页面内容到 Buffer
function M._render(state)
  local chapter = state.book.chapters[state.chapter_index]
  if not chapter then return end
  -- 获取当前页面应该显示的行（回忆 navigate.lua 的 get_page_lines）
  local raw_lines = navigate.get_page_lines(chapter.lines, state.line_offset, M.page_size)
  if #raw_lines == 0 then raw_lines = { "(empty chapter)" } end

  -- 通过渲染器将书籍文字伪装为代码注释
  local rendered = renderer.render(raw_lines)

  -- 记录内容行索引（用于 J/K 快速跳转）
  state.content_indices = rendered.content_indices or {}

  -- [Neovim基础] nvim_buf_set_lines(buf, start, end, strict, lines) 替换 Buffer 行内容。
  -- 0, -1, false 表示替换从第 0 行到末尾的全部内容。
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, rendered.lines)
  -- 设置 Buffer 的文件类型（控制语法高亮）
  vim.bo[state.buf].filetype = rendered.filetype
  -- 设置假文件名（显示在状态栏和标签栏中）
  if rendered.fake_path then
    pcall(vim.api.nvim_buf_set_name, state.buf, rendered.fake_path)
  end
  -- [Neovim API] nvim_buf_call(buf, fn) 在指定 Buffer 的上下文中执行函数。
  -- 这里用它在阅读 Buffer 中执行 vim.cmd("normal! gg") 将光标移到第一行。
  -- "normal!" 中的 ! 表示使用 Vim 默认按键定义（不触发用户自定义映射）。
  vim.api.nvim_buf_call(state.buf, function()
    vim.cmd("normal! gg")
  end)

  -- 应用伪装的状态栏
  statusline.apply(rendered.fake_path, rendered.filetype)
end

-- 设置 Buffer 局部键映射
function M._set_keymaps(buf, keymaps)
  -- [Neovim基础] vim.keymap.set(mode, lhs, rhs, opts) 创建键映射。
  -- 回忆 utils.buf_map：自动解析 <leader>、nil 检查、设置 buffer/silent/nowait。
  utils.buf_map(buf, keymaps.next_page, function() M._jump_content(1) end, "Ghost-reader 下一个内容行")
  utils.buf_map(buf, keymaps.prev_page, function() M._jump_content(-1) end, "Ghost-reader 上一个内容行")
  utils.buf_map(buf, keymaps.next_chapter, function() M.next_chapter() end, "Ghost-reader 下一章")
  utils.buf_map(buf, keymaps.prev_chapter, function() M.prev_chapter() end, "Ghost-reader 上一章")
  -- 老板键：立即切换回之前的 Buffer（看起来就像在正常写代码）
  utils.buf_map(buf, keymaps.boss_key, function()
    if M.state and vim.api.nvim_buf_is_valid(M.state.prev_buf) then
      progress.save(M.state.book, M.state, M.state.config)
      vim.api.nvim_set_current_buf(M.state.prev_buf)
    end
  end, "Ghost-reader 老板键")

  -- 目录选择
  utils.buf_map(buf, keymaps.toc, function()
    if not M.state then return end
    local items = {}
    for _, entry in ipairs(M.state.book.toc) do
      table.insert(items, entry.title)
    end
    -- [Neovim API] vim.ui.select(items, opts, on_choice) 显示选择对话框。
    -- 这是 Neovim 内置的 UI 接口，可以被 telescope、fzf 等插件替换外观。
    -- on_choice(item, idx) 是用户选择后的回调，idx 是选中的索引（1-based）。
    vim.ui.select(items, { prompt = "Table of Contents:" }, function(_, idx)
      if idx then M.go_to_chapter(idx) end
    end)
  end, "Ghost-reader 目录")

  utils.buf_map(buf, keymaps.progress, function()
    if M.state then progress.show(M.state.book, M.state) end
  end, "Ghost-reader 进度")
end

-- 跳转到下一个/上一个内容行（sparse_notes 模式下 J/K 键的功能）
-- 如果当前页没有更多内容行，自动翻页并跳到目标内容行
-- direction: 1 = 下一个, -1 = 上一个
function M._jump_content(direction)
  if not M.state then return end
  local indices = M.state.content_indices
  if not indices or #indices == 0 then
    if direction > 0 then M.next_page() else M.prev_page() end
    return
  end
  local current_line = vim.api.nvim_win_get_cursor(0)[1]

  local target
  if direction > 0 then
    for _, idx in ipairs(indices) do
      if idx > current_line then
        target = idx; break
      end
    end
  else
    for i = #indices, 1, -1 do
      if indices[i] < current_line then
        target = indices[i]; break
      end
    end
  end

  if target then
    utils.cursor_jump(target)
    return
  end

  -- 已到当前页边界，翻页后跳到目标页的首/末内容行
  if direction > 0 then M.next_page() else M.prev_page() end
  if M.state and M.state.content_indices and #M.state.content_indices > 0 then
    local fallback = direction > 0 and M.state.content_indices[1] or M.state.content_indices[#M.state.content_indices]
    utils.cursor_jump(fallback)
  end
end

-- 以下是导航操作的封装：调用 navigate 模块更新状态，然后重新渲染
function M.next_page()
  if not M.state then return end
  navigate.next_page(M.state, M.page_size)
  M._render(M.state)
end

function M.prev_page()
  if not M.state then return end
  navigate.prev_page(M.state, M.page_size)
  M._render(M.state)
end

function M.next_chapter()
  if not M.state then return end
  navigate.next_chapter(M.state)
  M._render(M.state)
end

function M.prev_chapter()
  if not M.state then return end
  navigate.prev_chapter(M.state)
  M._render(M.state)
end

function M.go_to_chapter(idx)
  if not M.state then return end
  navigate.go_to_chapter(M.state, idx)
  M._render(M.state)
end

-- 恢复到阅读 Buffer（用于从其他 Buffer 切回）
function M.restore()
  if M.state and vim.api.nvim_buf_is_valid(M.state.buf) then
    vim.api.nvim_set_current_buf(M.state.buf)
  end
end

-- 关闭阅读模式，清理资源
function M.close()
  if M.state then
    -- [Neovim API] nvim_buf_delete(buf, { force = true }) 强制删除 Buffer。
    -- 回忆：utils.safe_delete_buf 自动检查 Buffer 有效性。
    utils.safe_delete_buf(M.state.buf)
  end
  bookshelf.close()
  if M._quit_augroup then
    vim.api.nvim_del_augroup_by_name("ghost-reader-quit-guard")
    M._quit_augroup = nil
  end
  M.state = nil
end

return M
