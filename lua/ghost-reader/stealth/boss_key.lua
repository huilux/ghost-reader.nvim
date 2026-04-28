local M = {}

local snapshot = nil
local is_stealth = false

function M.capture(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  snapshot = {
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
    name = vim.api.nvim_buf_get_name(buf),
    filetype = vim.bo[buf].filetype,
    cursor = vim.api.nvim_win_get_cursor(0),
  }
end

function M.capture_from_current()
  M.capture(vim.api.nvim_get_current_buf())
end

function M.activate(preset_lines, preset_name, preset_filetype, target_buf)
  if is_stealth then return end
  target_buf = target_buf or vim.api.nvim_get_current_buf()

  local reader = require("ghost-reader.reader")
  if reader.state then
    reader._snapshot = {
      state = vim.deepcopy(reader.state),
      buf_lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false),
    }
  end

  local lines = preset_lines or { "-- nothing to show" }
  vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, lines)
  if preset_name then
    pcall(vim.api.nvim_buf_set_name, target_buf, preset_name)
  end
  if preset_filetype then
    vim.bo[target_buf].filetype = preset_filetype
  end
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  is_stealth = true
end

function M.deactivate(target_buf)
  if not is_stealth then return false end
  target_buf = target_buf or vim.api.nvim_get_current_buf()

  local reader = require("ghost-reader.reader")
  if reader.state and reader._snapshot then
    local lines = reader._snapshot.buf_lines
    vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, lines)
    if snapshot and snapshot.name then
      pcall(vim.api.nvim_buf_set_name, target_buf, snapshot.name)
    end
    if snapshot and snapshot.filetype then
      vim.bo[target_buf].filetype = snapshot.filetype
    end
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  end

  is_stealth = false
  return true
end

function M.is_active()
  return is_stealth
end

function M.get_snapshot()
  return snapshot
end

function M.toggle(preset_lines, preset_name, preset_filetype, target_buf)
  if is_stealth then
    return M.deactivate(target_buf)
  else
    M.activate(preset_lines, preset_name, preset_filetype, target_buf)
    return true
  end
end

return M
