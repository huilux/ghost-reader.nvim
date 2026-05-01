--[[
  utils.lua - 工具函数模块

  角色：整个插件的"工具箱"，提供文件检测、格式识别、目录创建等基础功能。
  所有函数都是纯函数或薄封装，不涉及插件业务逻辑。

  本文件涉及的关键概念（建议阅读顺序：这是第一个文件）：
  - [Lua概念] local M = {} 模块模式
  - [Lua概念] require() 路径解析
  - [Lua概念] Lua 字符串模式（非正则表达式）
  - [Neovim API] vim.fn 桥接 Vimscript 函数
  - [Neovim API] vim.loop (libuv) 文件系统操作
  - [Neovim API] string.format 格式化字符串
]]

-- [Lua概念] 模块模式：Lua 没有原生的"模块"或"类"概念。
-- 社区约定用"一个表 + return"来模拟模块：
--   1. local M = {} 创建一个空表
--   2. 所有公开函数挂在 M 上（如 M.file_exists）
--   3. 文件末尾 return M 暴露这个表
-- 其他文件通过 require("ghost-reader.utils") 获取这个表，就能调用 M 上的函数。
local M = {}

-- [Lua概念] 函数定义的两种写法：
--   function M.file_exists(path) ... end   ← 语法糖，更常用
--   M.file_exists = function(path) ... end  ← 等价写法
-- 本项目统一使用第一种。
function M.file_exists(path)
  -- [Neovim API] vim.fn 是访问 Vimscript 函数的桥梁。
  -- filereadable() 是 Vimscript 内置函数，返回整数：0 = 不可读，1 = 可读。
  -- [Lua概念] 注意：Lua 中 0 是 truthy（为真）！所以必须显式与 1 比较，不能写成 if vim.fn.filereadable(path) then。
  return vim.fn.filereadable(path) == 1
end

function M.detect_format(path)
  -- [Lua概念] Lua 字符串模式（pattern）≠ 正则表达式！
  --
  -- path:match(pattern) 在字符串中查找匹配，返回捕获组内容。
  -- 这里的模式 "%.([^%.]+)$" 解读：
  --   %.    = 转义的点号（. 在模式中是"任意字符"，% 将其转回字面量点号）
  --   ()    = 捕获组，匹配到的内容会被返回
  --   [^%.] = 字符类：不是点号的任意字符（^ 在 [] 内表示"非"）
  --   +     = 重复一次或多次
  --   $     = 锚定到字符串末尾
  -- 整体含义：匹配最后一个点号后面的内容，即文件扩展名。
  -- 例如 "book.epub" → 返回 "epub"
  local ext = path:match("%.([^%.]+)$")
  -- [Lua概念] :lower() 是字符串方法，将字符串转为小写。
  -- 冒号语法 str:lower() 等价于 string.lower(str)
  if ext then ext = ext:lower() end
  if ext == "epub" then return "epub"
  elseif ext == "md" or ext == "markdown" then return "markdown"
  elseif ext == "txt" or ext == "text" then return "txt"
  else return nil
  end
end

function M.file_hash(path)
  -- [Neovim API] vim.loop 是 libuv（跨平台异步 I/O 库）的 Lua 绑定。
  -- fs_stat() 返回文件状态信息表（包含 size、mtime 等），文件不存在则返回 nil。
  local stat = vim.loop.fs_stat(path)
  if not stat then return nil end
  -- [Lua概念] string.format 格式化字符串，类似 C 语言的 sprintf。
  -- %x = 将整数转为十六进制字符串。
  -- 用"修改时间（秒）+ 文件大小"作为文件的唯一标识（哈希）。
  -- .. 是 Lua 的字符串拼接运算符。
  return string.format("%x", stat.mtime.sec) .. "_" .. string.format("%x", stat.size)
end

function M.ensure_dir(path)
  -- vim.fn.isdirectory 返回整数：0 = 不是目录，1 = 是目录
  if vim.fn.isdirectory(path) == 0 then
    -- [Neovim API] vim.fn.mkdir 创建目录。
    -- 第二个参数 "p" 表示递归创建（类似 shell 的 mkdir -p），
    -- 即如果父目录不存在也会一并创建。
    vim.fn.mkdir(path, "p")
  end
end

function M.command_exists(cmd)
  -- vim.fn.executable 检查系统命令是否可用，返回 0 或 1
  return vim.fn.executable(cmd) == 1
end

-- [Lua概念] 模块文件必须在最后一行 return M，
-- 否则 require() 的调用方会收到 nil。
return M
