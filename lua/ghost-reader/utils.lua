local M = {}

function M.file_exists(path)
  return vim.fn.filereadable(path) == 1
end

function M.detect_format(path)
  local ext = path:match("%.([^%.]+)$")
  if ext then ext = ext:lower() end
  if ext == "epub" then return "epub"
  elseif ext == "md" or ext == "markdown" then return "markdown"
  elseif ext == "txt" or ext == "text" then return "txt"
  else return nil
  end
end

function M.file_hash(path)
  local stat = vim.loop.fs_stat(path)
  if not stat then return nil end
  return string.format("%x", stat.mtime.sec) .. "_" .. string.format("%x", stat.size)
end

function M.ensure_dir(path)
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.mkdir(path, "p")
  end
end

function M.command_exists(cmd)
  return vim.fn.executable(cmd) == 1
end

return M
