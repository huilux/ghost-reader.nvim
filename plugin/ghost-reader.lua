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

vim.api.nvim_create_user_command("GhostReaderControl", function()
  require("ghost-reader.actions").control()
end, {})

vim.api.nvim_create_user_command("GhostReaderHide", function()
  require("ghost-reader.actions").hide()
end, {})

vim.api.nvim_create_user_command("GhostReaderToc", function()
  require("ghost-reader.actions").toc()
end, {})

vim.api.nvim_create_user_command("GhostReaderStatusline", function(opts)
  local gr = require("ghost-reader")
  -- [Lua概念] if not gr.config then gr.setup() end 是懒初始化模式：
  -- 只在配置还没初始化时才调用 setup()，避免重复初始化。
  if not gr.config then gr.setup() end
  local path = opts.args
  if path ~= "" then
    local session = require("ghost-reader.session")
    session.configure(gr.config)
    session.start(vim.fn.expand(path), "statusline")
  else
    gr.select_book()
  end
end, { nargs = "?", complete = "file" })
