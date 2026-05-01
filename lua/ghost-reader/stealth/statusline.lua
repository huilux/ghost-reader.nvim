--[[
  stealth/statusline.lua - 状态栏伪装模块

  角色：保存和恢复 Neovim 状态栏的原始配置。阅读时将状态栏替换为看起来"正常"的格式，
  让别人看你的屏幕时不会发现你在看书。

  本文件涉及的关键概念：
  - [Neovim基础] vim.o / vim.wo 选项层级（全局选项 vs 窗口局部选项）
  - [Neovim API] nvim_set_option_value 设置指定作用域的选项
  - [Neovim API] vim.fn.fnamemodify 路径修饰

  关联模块：被 reader/init.lua 调用。
]]

local M = {}

local saved_state = nil

-- 保存当前状态栏配置（在进入阅读模式前调用）
function M.save()
  -- [Neovim基础] vim.o 访问 Neovim 的全局选项。
  -- Neovim 选项有三个层级：
  --   vim.o  = 全局选项（所有窗口共享的默认值）
  --   vim.bo = Buffer 局部选项（每个 Buffer 可以有不同的值）
  --   vim.wo = Window 局部选项（每个 Window 可以有不同的值）
  -- statusline 是一个字符串，定义状态栏的显示格式。
  -- laststatus 控制何时显示状态栏（0=永不，1=至少两个窗口时，2=总是，3=总是且唯一）。
  saved_state = {
    statusline = vim.o.statusline,
    laststatus = vim.o.laststatus,
  }
end

-- 恢复之前保存的状态栏配置
function M.restore()
  if saved_state then
    vim.o.statusline = saved_state.statusline
    vim.o.laststatus = saved_state.laststatus
  end
end

-- 应用伪装的状态栏（在阅读时调用）
function M.apply(fake_path, fake_filetype)
  local win = vim.api.nvim_get_current_win()
  -- [Neovim API] vim.fn.fnamemodify(path, ":~:.") 组合修饰符：
  --   ":~" = 如果在 home 目录下，用 ~ 替换 home 路径
  --   ":." = 如果在当前目录下，用相对路径
  -- 结果：显示最短的路径形式
  local short_path = vim.fn.fnamemodify(fake_path, ":~:.")
  -- [Neovim API] nvim_set_option_value(name, value, opts) 设置选项。
  -- 比 vim.o 更灵活，可以通过 { win = win } 指定作用域为某个窗口。
  -- 格式字符串中： %t=文件名 %m=修改标记 %y=文件类型 %=左右分隔 %l行号 %c列号
  vim.api.nvim_set_option_value("statusline", " %t %m %y %=%l,%c ", { win = win })

  -- 用假路径替换 Buffer 名称，让状态栏显示假文件名
  if fake_path then
    -- 回忆：pcall 安全调用（见 history.lua）
    pcall(vim.api.nvim_buf_set_name, 0, fake_path)
  end
  if fake_filetype then
    vim.bo.filetype = fake_filetype
  end
end

return M
