local M = {}
local config = require("ghost-reader.config")
local utils = require("ghost-reader.utils")
local session = require("ghost-reader.session")
local history = require("ghost-reader.history")

M.config = nil

local function choose_mode(default_mode, on_choice, on_cancel)
  if default_mode then
    return on_choice(default_mode)
  end
  vim.ui.select({ "overlay", "statusline", "mirror" }, { prompt = "Select mode:" }, function(choice)
    if choice then
      on_choice(choice)
    elseif on_cancel then
      on_cancel()
    end
  end)
end

local function pause_visible_session()
  local current = type(session.get) == "function" and session.get() or nil
  if not current or current.visibility ~= "VISIBLE" then
    return function() end
  end
  if not session.hide("hard") then
    return function() end
  end
  return function()
    if session.get() == current and current.visibility == "HARD_HIDDEN" then
      session.restore()
    end
  end
end

local function start_or_resume(path, mode, resume)
  session.configure(M.config)
  local opened = session.start(path, mode)
  if opened == false then
    resume()
  end
  return opened
end

local function choose_book(preferred_mode)
  if not M.config then M.setup() end
  local resume = pause_visible_session()
  local entries = history.load(M.config)
  local items = {}
  for _, e in ipairs(entries) do
    table.insert(items, e.name .. "  (" .. e.path .. ")")
  end
  table.insert(items, "+ 输入新路径...")

  vim.ui.select(items, { prompt = "Select book:" }, function(_, idx)
    if not idx then
      resume()
      return
    end
    local path
    if idx <= #entries then
      path = entries[idx].path
    else
      vim.ui.input({ prompt = "Book path: ", completion = "file" }, function(input)
        if input and input ~= "" then
          choose_mode(preferred_mode, function(mode)
            start_or_resume(vim.fn.expand(input), mode, resume)
          end, resume)
        else
          resume()
        end
      end)
      return
    end
    choose_mode(preferred_mode, function(mode)
      start_or_resume(path, mode, resume)
    end, resume)
  end)
end

function M.setup(user_config)
  M.config = config.setup(user_config or {})
  utils.ensure_dir(M.config.paths.cache_dir)
  utils.ensure_dir(M.config.paths.data_dir)
  require("ghost-reader.keymaps").setup(M.config)
  return M.config
end

function M.select_book(preferred_mode)
  return choose_book(preferred_mode)
end

function M.open(path)
  if not M.config then M.setup() end
  if not path or path == "" then
    return choose_book()
  end
  local resume = pause_visible_session()
  return choose_mode(nil, function(mode)
    return start_or_resume(path, mode, resume)
  end, resume)
end

function M.open_statusline(path)
  if not M.config then M.setup() end
  if not path or path == "" then
    return choose_book("statusline")
  end
  session.configure(M.config)
  session.start(path, "statusline")
end

function M.close()
  session.stop()
end

function M.toc()
  session.toc()
end

function M.toggle_hide()
  return session.toggle_hide()
end

return M
