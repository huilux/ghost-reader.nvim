--[[
  config.lua - 配置管理模块

  角色：定义插件的默认配置，并提供 deep_merge 函数将用户自定义配置合并到默认值上。

  本文件涉及的关键概念：
  - [Lua概念] 嵌套表（Lua 的表可以无限嵌套，模拟"对象"结构）
  - [Lua概念] pairs() 迭代器（遍历表的所有键值对）
  - [Lua概念] type() 函数（检查值的类型）
  - [Neovim API] vim.deepcopy（深拷贝表）
  - [Neovim API] vim.fn.stdpath（获取 Neovim 标准目录路径）

  关联模块：被 init.lua 调用来初始化插件配置。
]]

-- 回忆：local M = {} 是 Lua 的模块模式（详见 utils.lua）
local M = {}

-- [Lua概念] 嵌套表：Lua 的表（table）是唯一的数据结构，
-- 既可以当数组用，也可以当字典/对象用。这里用表来定义配置项。
-- 字符串键可以用点号语法访问：defaults.boss_key.keys
local defaults = {
  boss_key = {
    keys = "<Esc><Esc>",       -- 老板键快捷键
    use_current_buffer = true,  -- 是否用当前 buffer 的内容作为伪装
    preset = "random",          -- 伪装代码的预设名称，"random" 表示随机选取
  },
  keymaps = {
    next_page = "J",            -- 下一页
    prev_page = "K",            -- 上一页
    next_chapter = "]c",        -- 下一章
    prev_chapter = "[c",        -- 上一章
    toc = "<leader>gt",         -- 打开目录
    progress = "gp",            -- 显示阅读进度
    boss_key = "<Esc><Esc>",    -- 老板键
  },
  statusline = {
    interval = 3000,            -- 状态栏模式自动翻行间隔（毫秒）
    mode = "auto",              -- "auto" = 自动翻行，"manual" = 手动翻行
  },
  cache_dir = nil,              -- 缓存目录，nil 表示自动生成
  data_dir = nil,               -- 数据目录，nil 表示自动生成
}

-- [Lua概念] local function 表示函数只在当前文件可见（私有函数）。
-- 这是一个递归函数：对于嵌套的表，会递归地合并内层表。
local function deep_merge(base, override)
  -- [Neovim API] vim.deepcopy 创建表的深拷贝（完全独立的副本）。
  -- 必须拷贝，不能直接修改 base，因为 defaults 是共享的模块级变量。
  local result = vim.deepcopy(base)
  -- [Lua概念] pairs(t) 遍历表的所有键值对（顺序不确定）。
  -- 与 ipairs 不同：ipairs 只遍历整数索引（数组），pairs 遍历所有键。
  -- [Lua概念] "override or {}" 是 Lua 的"默认值惯用法"：
  --   如果 override 是 nil，则 or 会取后面的 {}（空表）。
  for k, v in pairs(override or {}) do
    -- [Lua概念] type(v) 返回值的类型字符串： "table"、"string"、"number"、"nil" 等。
    -- Lua 中表（table）是唯一的复合类型——没有数组、字典、对象的区别，都是 table。
    if type(v) == "table" and type(result[k]) == "table" then
      -- 两边都是表，递归合并内层
      result[k] = deep_merge(result[k], v)
    else
      -- 直接用用户的值覆盖默认值
      result[k] = v
    end
  end
  return result
end

-- setup() 是 Neovim 插件的标准入口函数。
-- 用户在 config 中写：require("ghost-reader").setup({ ... })
function M.setup(user_config)
  local cfg = deep_merge(defaults, user_config)
  -- [Neovim API] vim.fn.stdpath("cache") 返回 Neovim 的缓存目录路径（如 ~/.cache/nvim）。
  -- vim.fn.stdpath("data") 返回数据目录路径（如 ~/.local/share/nvim）。
  if not cfg.cache_dir then
    cfg.cache_dir = vim.fn.stdpath("cache") .. "/ghost-reader/"
  end
  if not cfg.data_dir then
    cfg.data_dir = vim.fn.stdpath("data") .. "/ghost-reader/"
  end
  return cfg
end

return M
