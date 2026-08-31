--[[
  history.lua - 书籍历史记录模块

  角色：管理"最近打开的书籍"列表。记录用户打开过的书籍路径和时间，
  最多保留 20 条。历史数据以 JSON 格式持久化到磁盘。

  本文件涉及的关键概念：
  - [Lua概念] io.open / f:read / f:write — Lua 标准文件 I/O
  - [Lua概念] pcall — 安全调用（错误处理）
  - [Lua概念] table.insert / table.remove — 表操作
  - [Lua概念] #entries — 长度运算符
  - [Neovim API] vim.json — JSON 编解码
  - [Neovim API] os.time() — 获取时间戳

  关联模块：被 init.lua 调用来记录和读取历史。
]]

local M = {}
local utils = require("ghost-reader.utils")

-- 构建历史文件的保存路径
local function history_path(config)
  local dir = config.paths.data_dir .. "data/"
  -- 回忆：ensure_dir 在目录不存在时自动创建（见 utils.lua）
  utils.ensure_dir(dir)
  return dir .. "history.json"
end

function M.load(config)
  local path = history_path(config)
  -- [Lua概念] io.open(path, mode) 打开文件。
  -- "r" = 只读，"w" = 只写（覆盖），"a" = 追加。
  -- [Lua概念] 冒号语法 f:read() 等价于 io.read(f)（自动传入 f 作为 self）。
  local f = io.open(path, "r")
  if not f then return {} end
  -- [Lua概念] f:read("*a") 读取文件全部内容。"*a" = all。
  -- 其他模式："*l" = 读取一行（默认），"*n" = 读取一个数字。
  local data = f:read("*a")
  f:close()
  -- [Lua概念] pcall(function, args...) 是"安全调用"：
  --   如果函数正常执行，返回 true, 结果
  --   如果函数抛出错误，返回 false, 错误消息
  -- 这里防止 JSON 格式损坏导致插件崩溃。
  local ok, decoded = pcall(vim.json.decode, data)
  -- [Neovim API] vim.json.decode(str) 将 JSON 字符串解析为 Lua 表。
  -- vim.json.encode(tbl) 将 Lua 表编码为 JSON 字符串。
  if ok and type(decoded) == "table" then return decoded end
  return {}
end

function M.save(config, entries)
  local path = history_path(config)
  local f = io.open(path, "w")
  if not f then return end
  f:write(vim.json.encode(entries))
  f:close()
end

-- 记录一次书籍打开操作
function M.record(path, config)
  local entries = M.load(config)
  -- 去重：如果这本书已在历史中，先移除旧记录（后面会重新插入到最前面）
  -- [Lua概念] ipairs(t) 按整数索引顺序遍历（1, 2, 3, ...），适合数组。
  for i, e in ipairs(entries) do
    if e.path == path then
      -- [Lua概念] table.remove(t, pos) 删除表中指定位置的元素，后面的元素会自动前移。
      table.remove(entries, i)
      break
    end
  end
  -- [Lua概念] table.insert(t, 1, value) 在位置 1 插入（即插入到数组最前面）。
  -- [Neovim API] vim.fn.fnamemodify(path, ":t") 从完整路径中提取文件名。
  --   ":t" = tail（仅文件名），":h" = head（仅目录），":r" = root（去掉扩展名）。
  -- [Lua概念] os.time() 返回当前时间的 Unix 时间戳（秒数）。
  table.insert(entries, 1, {
    path = path,
    name = vim.fn.fnamemodify(path, ":t"),
    last_opened = os.time(),
  })
  -- 保留最近 20 条记录
  -- [Lua概念] #entries 获取表的数组长度（只对连续整数索引有效）。
  if #entries > 20 then
    for i = #entries, 21, -1 do
      -- [Lua概念] entries[i] = nil 从表中删除该键。
      -- Lua 没有 delete/splice 操作，设为 nil 就是删除。
      entries[i] = nil
    end
  end
  M.save(config, entries)
end

return M
