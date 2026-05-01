--[[
  stealth/init.lua - 隐身模式门面模块

  角色：将 boss_key 和 presets 子模块组合起来，提供统一的 API。
  采用"门面模式"（Facade）：外部只需调用 stealth.activate_boss_key()，
  不需要关心内部是如何选择预设、如何切换 Buffer 的。

  本文件涉及的关键概念：
  - [Lua概念] 门面模式（Facade）：用一个模块包装多个子模块
  - [Lua概念] 模块属性引用（M.boss_key = boss_key）

  关联模块：组合 boss_key.lua 和 presets.lua。
  被主模块 init.lua 和 plugin/ghost-reader.lua 调用。
]]

local M = {}
local boss_key = require("ghost-reader.stealth.boss_key")

-- [Lua概念] 将子模块直接挂在 M 上，外部可以通过 stealth.boss_key.xxx 访问。
-- 这是 Lua 中实现模块组合的简单方式。
M.boss_key = boss_key

function M.setup(config)
  M.config = config
end

-- 激活老板键
function M.activate_boss_key(target_buf)
  local presets = require("ghost-reader.stealth.presets")
  -- 先捕获当前 Buffer 的内容作为快照（用于后续恢复）
  local snapshot = boss_key.get_snapshot()
  local use_current = M.config.boss_key.use_current_buffer

  if use_current and snapshot and #snapshot.lines > 1 then
    -- 配置为"使用当前 Buffer 内容"作为伪装：用用户正在编辑的真实代码来伪装
    boss_key.activate(snapshot.lines, snapshot.name, snapshot.filetype, target_buf)
  else
    -- 使用预设的假代码作为伪装
    local preset_name = M.config.boss_key.preset
    -- 回忆：presets.get("random") 会随机选择一套预设（见 presets.lua）
    local preset = presets.get(preset_name)
    boss_key.activate(preset.lines, preset.path, preset.filetype, target_buf)
  end
end

-- 取消老板键，恢复原始内容
function M.deactivate_boss_key(target_buf)
  return boss_key.deactivate(target_buf)
end

return M
