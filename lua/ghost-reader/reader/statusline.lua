--[[
  reader/statusline.lua - 状态栏阅读模式

  角色：在编辑器底部创建一个 1 行高的浮动窗口，逐行显示书籍文字。
  与全屏模式不同，状态栏模式不影响用户当前的编辑工作——浮动窗口叠加在状态栏位置，
  用户可以继续写代码，同时偷偷看书。

  支持两种子模式：
  - 自动模式（auto）：按设定间隔自动翻行
  - 手动模式（manual）：用 J/K 手动翻行

  这是本插件中最复杂的模块（375 行），涉及浮动窗口生命周期管理、定时器、
  UTF-8 文本分块、键映射管理等。

  本文件涉及的关键概念：
  - [Neovim基础] 浮动窗口创建与配置（nvim_open_win）
  - [Neovim基础] Autocmd 事件驱动模型（VimResized）
  - [Neovim基础] Augroup 分组管理
  - [Neovim API] vim.fn.timer_start / timer_stop 定时器
  - [Neovim API] vim.wo[win] Window 局部选项
  - [Neovim API] nvim_win_set_config 更新窗口配置
  - [Lua概念] 模块级状态管理

  关联模块：被主模块 init.lua 调用。协调 bookshelf、progress、history。
]]

local M = {}
local utils = require("ghost-reader.utils")
local bookshelf = require("ghost-reader.bookshelf")
local progress = require("ghost-reader.reader.progress")
local history = require("ghost-reader.history")

-- 模块级状态
M.state = nil     -- 当前阅读状态
M.timer = nil     -- 自动翻行定时器
M.chunks = {}     -- 当前行的文本分块（超长行会被拆分为多个分块）
M.chunk_idx = 0   -- 当前显示的分块索引
M._buf = nil      -- 浮动窗口使用的 Buffer
M._win = nil      -- 浮动窗口的 Window ID
M._augroup = nil  -- 自动命令分组
M._hidden = false -- 是否处于隐藏状态（老板键触发时）

-- UTF-8 逐字符迭代器（提取到 utils.utf8_next，回忆 sparse_notes.lua 中的详细说明）

-- 获取单个字符的显示宽度
local function char_width(ch)
  -- [Neovim API] vim.fn.strwidth 返回字符的显示宽度。
  -- ASCII = 1，CJK 字符 = 2。回忆 sparse_notes.lua 中的详细说明。
  return vim.fn.strwidth(ch)
end

-- 将一行文本按最大显示宽度拆分为多个分块
-- 这样超长的行可以在浮动窗口中分多次显示
local function split_to_chunks(text, max_width)
  if text == "" then return { "" } end
  local chunks = {}
  local current = ""
  local cur_w = 0
  local i = 1

  while i <= #text do
    local ch
    ch, i = utils.utf8_next(text, i)
    local cw = char_width(ch)

    -- 累加宽度超过最大宽度时，当前分块结束，开始新分块
    if cur_w + cw > max_width and current ~= "" then
      table.insert(chunks, current)
      current = ch
      cur_w = cw
    else
      current = current .. ch
      cur_w = cur_w + cw
    end
  end

  if current ~= "" then
    table.insert(chunks, current)
  end

  return chunks
end

-- 获取浮动窗口的最大显示宽度
local function get_max_width()
  -- [Neovim API] vim.o.columns 获取编辑器的总列数（宽度）。
  -- 减 4 是为了留出左右边距。
  return vim.o.columns - 4
end

-- 加载一行文本并拆分为分块
local function load_chunks(text)
  M.chunks = split_to_chunks(text, get_max_width())
  M.chunk_idx = 1
end

-- 创建底部的浮动窗口
local function create_float_win()
  -- 如果之前有窗口/Buffer 存在，先清理
  utils.safe_close_win(M._win)
  utils.safe_delete_buf(M._buf)

  -- [Neovim基础] 创建新的 Buffer 和浮动窗口。
  -- Buffer: listed=false（不在 :ls 中显示），scratch=true（临时）
  M._buf = vim.api.nvim_create_buf(false, true)
  -- [Neovim基础] Buffer 局部选项：
  --   buftype = "nofile": 不关联文件，不需要保存
  --   bufhidden = "wipe": 当窗口关闭时自动删除 Buffer
  vim.bo[M._buf].buftype = "nofile"
  vim.bo[M._buf].bufhidden = "wipe"

  -- 计算浮动窗口的位置：放在编辑器底部（状态栏上方）
  local total_w = vim.o.columns -- 编辑器总宽度
  local total_h = vim.o.lines   -- 编辑器总高度
  local row = total_h - 3       -- 底部第 3 行（状态栏上方）

  -- [Neovim基础] nvim_open_win(buf, enter, config) 创建浮动窗口。
  -- buf: 要在窗口中显示的 Buffer
  -- enter: false = 不将光标移入新窗口（用户光标仍在原位置）
  -- config:
  --   relative = "editor": 相对于编辑器屏幕定位
  --   style = "minimal": 无边框、无行号、无折叠列等装饰
  --   focusable = false: 窗口不接受焦点（用户不能 Tab 到这个窗口）
  --   zindex = 50: 层叠顺序（普通窗口是 0，数值越大越靠前）
  M._win = vim.api.nvim_open_win(M._buf, false, {
    relative = "editor",
    width = total_w,
    height = 1,
    row = row,
    col = 0,
    style = "minimal",
    focusable = false,
    zindex = 50,
  })
  -- [Neovim基础] vim.wo[win] 设置 Window 局部选项。
  -- winhl = "Normal:Comment" 将 Normal 高亮组映射为 Comment 高亮组。
  -- 效果：浮动窗口中的文字看起来像注释（通常是灰色），与正常代码区分。
  vim.wo[M._win].winhl = "Normal:Comment"
  -- 禁用换行：超出窗口宽度的文字直接截断
  vim.wo[M._win].wrap = false
end

-- 刷新浮动窗口显示的内容
local function refresh_display()
  if not M._buf or not vim.api.nvim_buf_is_valid(M._buf) then return end
  local st = M.state
  -- 显示播放图标：▶ = 自动模式，‖ = 手动模式
  local icon = st and (st.auto_mode and "▶ " or "‖ ") or ""
  local text = M.chunks[M.chunk_idx] or ""
  vim.api.nvim_buf_set_lines(M._buf, 0, -1, false, { icon .. text })
end

-- 前进到下一行（如果当前行有多个分块，先显示下一个分块）
local function advance_line()
  if not M.state then return false end
  local st = M.state
  local chapter = st.book.chapters[st.chapter_index]
  if not chapter then return false end

  -- 寻找下一个非空行
  while true do
    st.line_offset = st.line_offset + 1
    if st.line_offset > #chapter.lines then
      -- 当前章节读完，跳到下一章
      if st.chapter_index >= #st.book.chapters then
        load_chunks("(END)")
        return false
      end
      st.chapter_index = st.chapter_index + 1
      st.line_offset = 0
      chapter = st.book.chapters[st.chapter_index]
    else
      local line = chapter.lines[st.line_offset]
      if line and line ~= "" then
        load_chunks(line)
        return true
      end
    end
  end
end

-- 显示下一个分块（或下一行）
local function advance()
  if not M.state then return end
  -- 当前行还有未显示的分块，显示下一个分块
  if M.chunk_idx < #M.chunks then
    M.chunk_idx = M.chunk_idx + 1
  else
    -- 当前行显示完毕，前进到下一行
    advance_line()
  end
  refresh_display()
end

-- 回退到上一行
local function go_back_line()
  if not M.state then return end
  local st = M.state
  local chapter = st.book.chapters[st.chapter_index]
  if not chapter then return end

  -- 寻找上一个非空行
  while true do
    st.line_offset = st.line_offset - 1
    if st.line_offset < 1 then
      -- 已到当前章节开头，跳到上一章末尾
      if st.chapter_index <= 1 then
        st.line_offset = 1
        chapter = st.book.chapters[1]
        break
      end
      st.chapter_index = st.chapter_index - 1
      chapter = st.book.chapters[st.chapter_index]
      st.line_offset = #chapter.lines
    end
    if chapter.lines[st.line_offset] and chapter.lines[st.line_offset] ~= "" then
      break
    end
  end

  load_chunks(chapter.lines[st.line_offset] or "")
end

-- 显示上一个分块（或上一行）
local function go_back()
  if not M.state then return end
  if M.chunk_idx > 1 then
    M.chunk_idx = M.chunk_idx - 1
  else
    go_back_line()
  end
  refresh_display()
end

-- 启动/重启自动翻行定时器
local function start_timer()
  if M.timer then vim.fn.timer_stop(M.timer) end
  if not M.state or not M.state.auto_mode then return end
  -- [Neovim API] vim.fn.timer_start(ms, callback) 创建一次性定时器。
  -- ms 毫秒后调用 callback。这里在回调中手动再次调用 start_timer()
  -- 来实现"周期性"定时器（因为 timer_start 本身只触发一次）。
  M.timer = vim.fn.timer_start(M.state.interval, function()
    if M.state and M.state.auto_mode then
      advance()
      start_timer() -- 递归调用，实现周期执行
    end
  end)
end

-- 启动状态栏阅读模式
function M.start(path, config)
  -- 如果已在运行，先停止
  if M.timer then M.stop() end

  local book, err = bookshelf.open(path)
  if err then
    utils.notify(err, vim.log.levels.ERROR)
    return
  end

  -- 恢复上次阅读进度
  local chapter_index = 1
  local line_offset = 0
  local fake_book = { path = path, chapters = book.chapters }
  local saved = progress.load(fake_book, config)
  if saved then
    chapter_index = math.min(saved.chapter_index or 1, #book.chapters)
    line_offset = saved.line_offset or 0
  end

  local sl_cfg = config.statusline or {}
  local auto_mode = sl_cfg.mode ~= "manual"

  M.state = {
    book = book,
    chapter_index = chapter_index,
    line_offset = line_offset,
    auto_mode = auto_mode,
    interval = sl_cfg.interval or 3000,
    config = config,
  }
  M.chunks = {}
  M.chunk_idx = 0

  -- 创建浮动窗口
  create_float_win()

  -- [Neovim基础] nvim_create_augroup(name, opts) 创建自动命令分组。
  -- { clear = true } 清除该分组中已有的所有自动命令，防止重复注册。
  M._augroup = vim.api.nvim_create_augroup("ghost-reader-statusline", { clear = true })
  -- [Neovim基础] 监听 VimResized 事件：当终端窗口大小改变时，重新定位浮动窗口。
  -- 否则窗口位置会错位。
  vim.api.nvim_create_autocmd("VimResized", {
    group = M._augroup,
    callback = function()
      if M._win and vim.api.nvim_win_is_valid(M._win) then
        -- [Neovim API] nvim_win_set_config(win, config) 更新浮动窗口的位置和大小。
        vim.api.nvim_win_set_config(M._win, {
          relative = "editor",
          width = vim.o.columns,
          height = 1,
          row = vim.o.lines - 3,
          col = 0,
        })
      end
    end,
  })
  -- 退出前保存阅读进度
  vim.api.nvim_create_autocmd("QuitPre", {
    group = M._augroup,
    callback = function()
      if M.state then
        local fake_book = { path = M.state.book.path, chapters = M.state.book.chapters }
        progress.save(fake_book, M.state, M.state.config)
      end
    end,
  })

  -- 开始显示第一行
  advance_line()
  refresh_display()

  -- 如果是自动模式，启动定时器
  if auto_mode then start_timer() end

  -- 记录历史
  history.record(path, config)
  -- 设置键映射
  M._set_keymaps()

  local name = vim.fn.fnamemodify(path, ":t:r")
  local mode_label = auto_mode and "自动" or "手动"
  utils.notify(string.format("%s · 状态栏%s模式\nJ/K=翻行 +/-=调速 m=切换模式 q=退出",
    name, mode_label))
end

-- 停止状态栏阅读模式，清理所有资源
function M.stop()
  -- [Neovim API] vim.fn.timer_stop(timer) 停止定时器。
  if M.timer then
    vim.fn.timer_stop(M.timer)
    M.timer = nil
  end
  -- [Neovim API] nvim_del_augroup_by_name(name) 删除整个自动命令分组。
  -- 清理 VimResized 等事件监听。
  if M._augroup then
    vim.api.nvim_del_augroup_by_name("ghost-reader-statusline")
    M._augroup = nil
  end
  -- 关闭浮动窗口
  utils.safe_close_win(M._win)
  M._win = nil
  -- 删除 Buffer
  utils.safe_delete_buf(M._buf)
  M._buf = nil
  -- 保存阅读进度
  if M.state then
    local fake_book = { path = M.state.book.path, chapters = M.state.book.chapters }
    progress.save(fake_book, M.state, M.state.config)
    bookshelf.close()
  end
  M.state = nil
  M.chunks = {}
  M.chunk_idx = 0
  M._hidden = false
  -- 清理键映射
  local leader = vim.g.mapleader or "\\"
  local keys = { "J", "K" }
  for _, k in ipairs({ "g+", "g-", "gm", "gq" }) do
    table.insert(keys, leader .. k)
  end
  for _, key in ipairs(keys) do
    -- 回忆：pcall 安全调用（见 history.lua）。
    -- 用 pcall 包裹因为键映射可能不存在（用户可能已手动删除）。
    pcall(vim.keymap.del, "n", key, { buffer = 0 })
  end
end

-- 隐藏浮动窗口（老板键触发时调用，不停止阅读状态）
function M.hide()
  if not M.state or M._hidden then return end
  M._hidden = true
  -- 停止定时器
  if M.timer then
    vim.fn.timer_stop(M.timer)
    M.timer = nil
  end
  -- 关闭窗口和 Buffer
  utils.safe_close_win(M._win)
  M._win = nil
  utils.safe_delete_buf(M._buf)
  M._buf = nil
end

-- 恢复隐藏的浮动窗口
function M.restore()
  if not M.state or not M._hidden then return end
  M._hidden = false
  -- 重新创建浮动窗口
  create_float_win()
  refresh_display()
  -- 如果是自动模式，重启定时器
  if M.state.auto_mode then start_timer() end
end

-- 设置状态栏模式的键映射
function M._set_keymaps()
  -- [Neovim基础] { buffer = 0 } 表示"当前 Buffer"的局部映射。
  -- 回忆 utils.buf_map：自动解析 <leader>、nil 检查、设置 buffer/silent/nowait。
  utils.buf_map(0, "J", function()
    advance()
    -- 手动操作后重启定时器（重置倒计时）
    if M.state and M.state.auto_mode then start_timer() end
  end, "Ghost-reader 下一行")

  utils.buf_map(0, "K", function()
    go_back()
    if M.state and M.state.auto_mode then start_timer() end
  end, "Ghost-reader 上一行")

  -- <leader>g+: 加速（缩短间隔）
  utils.buf_map(0, "<leader>g+", function()
    if not M.state then return end
    M.state.interval = math.max(500, M.state.interval - 500)
    if M.state.auto_mode then start_timer() end
    utils.notify(M.state.interval .. "ms")
  end, "Ghost-reader 加速")

  -- <leader>g-: 减速（增加间隔）
  utils.buf_map(0, "<leader>g-", function()
    if not M.state then return end
    M.state.interval = math.min(15000, M.state.interval + 500)
    if M.state.auto_mode then start_timer() end
    utils.notify(M.state.interval .. "ms")
  end, "Ghost-reader 减速")

  -- <leader>gm: 切换自动/手动模式
  utils.buf_map(0, "<leader>gm", function()
    if not M.state then return end
    M.state.auto_mode = not M.state.auto_mode
    if M.state.auto_mode then
      start_timer()
      utils.notify("auto ▶")
    else
      if M.timer then
        vim.fn.timer_stop(M.timer); M.timer = nil
      end
      utils.notify("manual ‖")
    end
    refresh_display()
  end, "Ghost-reader 切换自动/手动")

  -- <leader>gq: 退出状态栏模式
  utils.buf_map(0, "<leader>gq", function()
    M.stop()
    utils.notify("stopped")
  end, "Ghost-reader 退出")

  -- <Esc><Esc>: 老板键（隐藏浮动窗口）
  utils.buf_map(0, "<Esc><Esc>", function()
    M.hide()
  end, "Ghost-reader 老板键")
end

return M
