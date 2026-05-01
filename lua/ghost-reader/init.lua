--[[
  init.lua - 主模块（公共 API）

  角色：这是插件的公共入口模块。用户和外部代码通过 require("ghost-reader") 与此模块交互。
  提供 setup()（初始化配置）、open()（打开书籍）、close()（关闭）、select_book()（选择书籍）、
  toc()（目录）等公共 API。

  这是最后阅读的文件，因为它需要理解前面所有子模块的职责才能看懂编排流程。

  本文件涉及的关键概念：
  - [Neovim API] vim.ui.select 选择对话框
  - [Neovim API] vim.ui.input 输入对话框
  - [Lua概念] 懒初始化模式（if not M.config then M.setup() end）
  - [Lua概念] 模块间协调/编排

  关联模块：协调 config、utils、reader、history、reader_statusline。
]]

local M = {}
local config = require("ghost-reader.config")
local utils = require("ghost-reader.utils")
local reader = require("ghost-reader.reader")
local history = require("ghost-reader.history")
local reader_statusline = require("ghost-reader.reader.statusline")

-- [Lua概念] M.config = nil 表示"尚未初始化"。
-- 第一次调用 M.setup() 时才会被赋值。
-- 其他函数在使用前会检查：if not M.config then M.setup() end（懒初始化模式）。
M.config = nil

-- 初始化插件配置
function M.setup(user_config)
  -- 调用 config.setup 合并默认值和用户自定义值
  M.config = config.setup(user_config or {})
  -- 确保缓存和数据目录存在
  utils.ensure_dir(M.config.cache_dir)
  utils.ensure_dir(M.config.data_dir)
  return M.config
end

-- 打开一本书（全屏模式）
function M.open(path)
  -- [Lua概念] 懒初始化：如果还没调用 setup()，先用默认配置初始化。
  if not M.config then M.setup() end
  local ok = reader.open(path, M.config)
  if ok then
    -- 记录到历史
    history.record(path, M.config)
  end
end

-- 关闭阅读模式
function M.close()
  reader.close()
end

-- 显示目录（在当前阅读的书中跳转章节）
function M.toc()
  local reader = require("ghost-reader.reader")
  if not reader.state then return end
  local book = reader.state.book
  local items = {}
  for _, entry in ipairs(book.toc) do
    table.insert(items, entry.title)
  end
  -- 回忆：vim.ui.select 显示选择对话框（见 reader/init.lua 中的详细说明）
  vim.ui.select(items, { prompt = "Table of Contents:" }, function(_, idx)
    if idx then reader.go_to_chapter(idx) end
  end)
end

-- 智能选择书籍：根据当前状态决定下一步操作
function M.select_book()
  if not M.config then M.setup() end

  -- 情况1：状态栏模式被老板键隐藏了 → 恢复它
  if reader_statusline.state and reader_statusline._hidden then
    reader_statusline.restore()
    return
  end

  -- 情况2：全屏模式的 Buffer 存在（可能在后台）→ 切回它
  if reader.state and vim.api.nvim_buf_is_valid(reader.state.buf) then
    reader.state.prev_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_current_buf(reader.state.buf)
    return
  end

  -- 情况3：状态栏模式正在运行 → 不需要操作
  if reader_statusline.state then
    return
  end

  -- 情况4：没有任何阅读状态 → 从历史中选择一本书或输入新路径
  local entries = history.load(M.config)
  local items = {}
  for _, e in ipairs(entries) do
    table.insert(items, e.name .. "  (" .. e.path .. ")")
  end
  -- 在列表末尾添加"输入新路径"选项
  table.insert(items, "+ 输入新路径...")

  -- [Neovim API] vim.ui.select(items, opts, on_choice) 显示选择列表。
  -- on_choice(item, idx) 回调：item 是选中的文本，idx 是索引。
  -- idx 为 nil 表示用户取消了选择。
  vim.ui.select(items, { prompt = "Select book:" }, function(_, idx)
    if not idx then return end
    local path
    if idx <= #entries then
      -- 选择了历史中的书
      path = entries[idx].path
    else
      -- 选择了"输入新路径"
      -- [Neovim API] vim.ui.input(opts, on_choice) 显示文本输入框。
      -- completion = "file" 启用文件路径补全。
      vim.ui.input({ prompt = "Book path: ", completion = "file" }, function(input)
        if input and input ~= "" then M.open(vim.fn.expand(input)) end
      end)
      return
    end
    -- 选择阅读模式
    local mode_items = { "sparse_notes (全屏)", "statusline (状态栏)" }
    vim.ui.select(mode_items, { prompt = "Reading mode:" }, function(_, mode_idx)
      if not mode_idx then M.open(path); return end
      if mode_idx == 1 then
        M.open(path)
      else
        reader_statusline.start(path, M.config)
      end
    end)
  end)
end

return M
