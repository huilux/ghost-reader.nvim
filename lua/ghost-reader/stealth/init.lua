local M = {}
local boss_key = require("ghost-reader.stealth.boss_key")

M.boss_key = boss_key

function M.setup(config)
  M.config = config
end

function M.activate_boss_key(target_buf)
  local presets = require("ghost-reader.stealth.presets")
  local snapshot = boss_key.get_snapshot()
  local use_current = M.config.boss_key.use_current_buffer

  if use_current and snapshot and #snapshot.lines > 1 then
    boss_key.activate(snapshot.lines, snapshot.name, snapshot.filetype, target_buf)
  else
    local preset_name = M.config.boss_key.preset
    local preset = presets.get(preset_name)
    boss_key.activate(preset.lines, preset.path, preset.filetype, target_buf)
  end
end

function M.deactivate_boss_key(target_buf)
  return boss_key.deactivate(target_buf)
end

return M
