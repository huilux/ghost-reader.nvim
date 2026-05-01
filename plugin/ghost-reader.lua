--[[
  plugin/ghost-reader.lua - 插件入口点

  角色：注册所有用户命令（:GhostReader、:GhostReaderClose 等）。
  Neovim 启动时会自动加载 plugin/ 目录下的文件，所以命令在启动后就可使用。

  [Neovim基础] 插件加载机制：
  - plugin/ 目录：启动时自动执行（source）。适合注册命令，但不应该放重型逻辑。
  - lua/ 目录：通过 require() 按需加载（懒加载）。业务逻辑放在这里。
  - 本文件只负责"注册命令"，命令内部通过 require() 按需加载真正的逻辑。

  [Neovim基础] runtimepath 与路径解析：
  - require("ghost-reader") → 在 runtimepath 下的 lua/ 目录中查找 ghost-reader/init.lua
  - require("ghost-reader.stealth") → 查找 lua/ghost-reader/stealth/init.lua

  本文件涉及的关键概念：
  - [Neovim基础] vim.g 全局变量与防重复加载
  - [Neovim API] nvim_create_user_command 注册用户命令
  - [Neovim API] vim.fn.expand 展开文件路径
  - [Lua概念] 匿名函数 function(opts) ... end
]]

-- [Neovim基础] 防重复加载模式：
-- vim.g 访问 Vimscript 的全局变量（g: 作用域）。
-- 第一次加载时 vim.g.loaded_ghost_reader 为 nil（falsy），不会 return。
-- 然后立即设为 true，后续如果再次加载就会直接 return，避免命令重复注册。
if vim.g.loaded_ghost_reader then
  return
end
vim.g.loaded_ghost_reader = true

-- [Neovim API] nvim_create_user_command(name, handler, opts) 注册一个 :Command 命令。
-- name: 命令名（大驼峰，用户输入 :GhostReader 来调用）
-- handler: 命令被调用时执行的函数，接收 opts 参数表
-- opts: 命令选项
--   nargs = "?" 表示接受 0 或 1 个参数（可选参数）
--   complete = "file" 启用文件路径补全（按 Tab 自动补全文件名）
vim.api.nvim_create_user_command("GhostReader", function(opts)
  -- [Lua概念] 匿名函数：function(opts) ... end 是内联定义的函数。
  -- [Neovim API] require() 在这里才调用，实现懒加载：
  -- 只有用户执行 :GhostReader 时，才会加载主模块的代码。
  local gr = require("ghost-reader")
  local path = opts.args
  if path ~= "" then
    -- [Neovim API] vim.fn.expand(path) 展开路径中的特殊字符（如 ~ → 家目录）
    gr.open(vim.fn.expand(path))
  else
    gr.select_book()
  end
end, { nargs = "?", complete = "file" })

vim.api.nvim_create_user_command("GhostReaderClose", function()
  require("ghost-reader").close()
end, {})

vim.api.nvim_create_user_command("GhostReaderBoss", function()
  local stealth = require("ghost-reader.stealth")
  stealth.activate_boss_key()
end, {})

vim.api.nvim_create_user_command("GhostReaderRestore", function()
  local stealth = require("ghost-reader.stealth")
  stealth.deactivate_boss_key()
end, {})

vim.api.nvim_create_user_command("GhostReaderStatusline", function(opts)
  local gr = require("ghost-reader")
  -- [Lua概念] if not gr.config then gr.setup() end 是懒初始化模式：
  -- 只在配置还没初始化时才调用 setup()，避免重复初始化。
  if not gr.config then gr.setup() end
  local path = opts.args
  if path ~= "" then
    require("ghost-reader.reader.statusline").start(vim.fn.expand(path), gr.config)
  else
    gr.select_book()
  end
end, { nargs = "?", complete = "file" })
