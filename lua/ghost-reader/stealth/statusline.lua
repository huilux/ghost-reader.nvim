local M = {}

local saved_state = nil

function M.save()
  saved_state = {
    statusline = vim.o.statusline,
    laststatus = vim.o.laststatus,
  }
end

function M.restore()
  if saved_state then
    vim.o.statusline = saved_state.statusline
    vim.o.laststatus = saved_state.laststatus
  end
end

function M.apply(fake_path, fake_filetype)
  local win = vim.api.nvim_get_current_win()
  local short_path = vim.fn.fnamemodify(fake_path, ":~:.")
  vim.api.nvim_set_option_value("statusline", " %t %m %y %=%l,%c ", { win = win })

  if fake_path then
    pcall(vim.api.nvim_buf_set_name, 0, fake_path)
  end
  if fake_filetype then
    vim.bo.filetype = fake_filetype
  end
end

return M
