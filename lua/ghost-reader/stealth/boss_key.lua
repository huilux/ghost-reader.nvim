--[[
  stealth/boss_key.lua - 老板键核心逻辑

  角色：实现老板键的"瞬间切换"功能。
  当老板来了，按 <Esc><Esc> 立即将屏幕内容替换为假代码，再按一次恢复。

  本文件涉及的关键概念：
  - [Neovim基础] Buffer 内容操作（读取/设置/重命名）
  - [Neovim API] nvim_buf_get_lines / nvim_buf_set_lines 读写 Buffer 行
  - [Neovim API] nvim_buf_set_name 设置 Buffer 文件名
  - [Neovim API] nvim_win_set_cursor 设置光标位置
  - [Neovim API] vim.bo[buf] Buffer 局部选项
  - [Neovim API] vim.deepcopy 深拷贝

  关联模块：被 stealth/init.lua 调用。
]]

local M = {}

-- 模块级状态：保存切换前的 Buffer 快照
local snapshot = nil
local is_stealth = false

-- 捕获指定 Buffer 的当前状态
function M.capture(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  snapshot = {
    -- [Neovim基础] Buffer 内容操作：
    -- nvim_buf_get_lines(buf, start, end, strict_indexing)
    --   buf: Buffer 编号
    --   start: 起始行（0-based！Lua 的索引通常从 1 开始，但 Neovim API 的行号从 0 开始）
    --   end: 结束行（-1 表示最后一行之后，即"到末尾"）
    --   strict_indexing: false 表示超出范围时自动裁剪而非报错
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
    -- [Neovim API] nvim_buf_get_name(buf) 获取 Buffer 的文件名（完整路径）
    name = vim.api.nvim_buf_get_name(buf),
    -- [Neovim API] vim.bo[buf].filetype 获取指定 Buffer 的文件类型。
    -- vim.bo 是 Buffer 局部选项的快捷访问方式，[buf] 指定 Buffer 编号。
    filetype = vim.bo[buf].filetype,
    -- [Neovim API] nvim_win_get_cursor(win) 获取光标位置。
    -- 返回 { row, col }，row 是 1-based，col 是 0-based。
    cursor = vim.api.nvim_win_get_cursor(0),  -- 0 = 当前窗口
  }
end

-- 捕获当前 Buffer 的状态（便捷方法）
function M.capture_from_current()
  M.capture(vim.api.nvim_get_current_buf())
end

-- 激活老板键：将 Buffer 内容替换为假代码
function M.activate(preset_lines, preset_name, preset_filetype, target_buf)
  if is_stealth then return end
  target_buf = target_buf or vim.api.nvim_get_current_buf()

  -- 如果阅读器正在运行，保存它的完整状态以便恢复
  local reader = require("ghost-reader.reader")
  if reader.state then
    reader._snapshot = {
      -- [Neovim API] vim.deepcopy 深拷贝表，创建完全独立的副本。
      -- 必须拷贝，因为 state 在后续操作中会被修改。
      state = vim.deepcopy(reader.state),
      buf_lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false),
    }
  end

  -- [Neovim基础] nvim_buf_set_lines(buf, start, end, strict_indexing, lines)
  -- 替换 Buffer 中的行内容。
  -- 0, -1, false 表示"替换从第 0 行到末尾的所有行"。
  local lines = preset_lines or { "-- nothing to show" }
  vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, lines)
  -- [Neovim API] nvim_buf_set_name 设置 Buffer 的文件名。
  -- 这个名称会显示在状态栏和标签栏中，是伪装的关键部分。
  -- 用 pcall 包裹因为名称可能重复导致报错。
  if preset_name then
    pcall(vim.api.nvim_buf_set_name, target_buf, preset_name)
  end
  -- 设置文件类型以启用对应的语法高亮
  if preset_filetype then
    vim.bo[target_buf].filetype = preset_filetype
  end
  -- [Neovim API] nvim_win_set_cursor(win, { row, col }) 设置光标位置。
  -- win=0 表示当前窗口。row 是 1-based，col 是 0-based。
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  is_stealth = true
end

-- 取消老板键：恢复原始内容
function M.deactivate(target_buf)
  if not is_stealth then return false end
  target_buf = target_buf or vim.api.nvim_get_current_buf()

  local reader = require("ghost-reader.reader")
  if reader.state and reader._snapshot then
    -- 恢复之前保存的 Buffer 内容
    local lines = reader._snapshot.buf_lines
    vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, lines)
    if snapshot and snapshot.name then
      pcall(vim.api.nvim_buf_set_name, target_buf, snapshot.name)
    end
    if snapshot and snapshot.filetype then
      vim.bo[target_buf].filetype = snapshot.filetype
    end
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  end

  is_stealth = false
  return true
end

function M.is_active()
  return is_stealth
end

function M.get_snapshot()
  return snapshot
end

-- 切换老板键状态（激活 ↔ 取消）
function M.toggle(preset_lines, preset_name, preset_filetype, target_buf)
  if is_stealth then
    return M.deactivate(target_buf)
  else
    M.activate(preset_lines, preset_name, preset_filetype, target_buf)
    return true
  end
end

return M
