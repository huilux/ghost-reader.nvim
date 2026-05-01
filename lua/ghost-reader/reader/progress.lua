--[[
  reader/progress.lua - 阅读进度保存/加载

  角色：将阅读进度（章节索引 + 行偏移）保存为 JSON 文件，下次打开同一本书时恢复。
  用文件的"修改时间+大小"作为唯一标识（哈希），确保同一文件总是恢复到上次位置。

  本文件涉及的关键概念：
  - [Lua概念] string.format 的 %% 转义
  - [Neovim API] vim.notify 通知系统
  - [Neovim API] vim.log.levels 日志级别

  关联模块：被 reader/init.lua 和 reader/statusline.lua 调用。
]]

local M = {}
local utils = require("ghost-reader.utils")

-- 保存当前阅读进度到 JSON 文件
function M.save(book, state, config)
  local book_hash = utils.file_hash(book.path) or "unknown"
  local data_dir = config.data_dir .. "data/"
  utils.ensure_dir(data_dir)
  local path = data_dir .. book_hash .. ".json"

  local f = io.open(path, "w")
  if not f then return end
  -- 回忆：vim.json.encode 将 Lua 表转为 JSON 字符串（见 history.lua）
  f:write(vim.json.encode({
    book_path = book.path,
    chapter_index = state.chapter_index,
    line_offset = state.line_offset,
    last_read = os.time(),
  }))
  f:close()
end

-- 加载之前保存的阅读进度
function M.load(book, config)
  local book_hash = utils.file_hash(book.path) or "unknown"
  local data_dir = config.data_dir .. "data/"
  local path = data_dir .. book_hash .. ".json"

  local f = io.open(path, "r")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  -- 回忆：pcall 安全调用（见 history.lua）
  local ok, decoded = pcall(vim.json.decode, data)
  if ok then return decoded end
  return nil
end

-- 在通知中显示当前阅读进度
function M.show(book, state)
  local chapter = state.chapter_index
  local total = #book.chapters
  -- [Lua概念] math.floor 向下取整
  local pct = math.floor((chapter / total) * 100)
  -- [Lua概念] string.format 中 %% 输出字面量 %（因为 % 是格式化占位符前缀，需要转义）。
  -- 其他常用占位符：%d = 整数，%s = 字符串，%x = 十六进制
  local line = string.format("[ghost-reader] Chapter %d/%d · %d%%", chapter, total, pct)
  -- [Neovim API] vim.notify(msg, level) 在 Neovim 中显示通知消息。
  -- vim.log.levels 定义了日志级别常量：
  --   TRACE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4
  vim.notify(line, vim.log.levels.INFO)
end

return M
