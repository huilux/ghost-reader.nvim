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
  local gr = require("ghost-reader")
  local path = opts.args
  if path ~= "" then
    gr.open(vim.fn.expand(path))
  else
    gr.open()
  end
end, { nargs = "?", complete = "file" })

vim.api.nvim_create_user_command("GhostReaderClose", function()
  require("ghost-reader").close()
end, {})

vim.api.nvim_create_user_command("GhostReaderHide", function()
  require("ghost-reader.actions").hide()
end, {})

vim.api.nvim_create_user_command("GhostReaderToc", function()
  require("ghost-reader.actions").toc()
end, {})

vim.api.nvim_create_user_command("GhostReaderStatusline", function(opts)
  local gr = require("ghost-reader")
  if not gr.config then gr.setup() end
  local path = opts.args
  if path ~= "" then
    gr.open_statusline(vim.fn.expand(path))
  else
    gr.open_statusline()
  end
end, { nargs = "?", complete = "file" })
