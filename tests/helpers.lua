local M = {}

function M.reset_modules()
  for name in pairs(package.loaded) do
    if name:match("^ghost%-reader") then
      package.loaded[name] = nil
    end
  end
end

function M.new_normal_buffer(lines, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = filetype or "lua"
  vim.bo[buf].modified = false
  return buf, vim.api.nvim_get_current_win()
end

return M
