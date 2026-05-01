--[[
  renderer/init.lua - 渲染器调度模块

  角色：薄调度层，将渲染请求转发给具体的渲染器实现。
  目前只有 sparse_notes（稀疏注释）渲染器，但设计上支持未来扩展更多渲染器。

  本文件涉及的关键概念：
  - [Lua概念] 薄封装/代理模式：一个模块只是另一个模块的转发层

  关联模块：调度 sparse_notes.lua。
  被 reader/init.lua 调用。
]]

local M = {}
local sparse_notes = require("ghost-reader.renderer.sparse_notes")

-- 所有渲染器的统一接口：render(lines, opts) → { lines, filetype, fake_path }
function M.render(lines, opts)
  return sparse_notes.render(lines, opts)
end

return M
