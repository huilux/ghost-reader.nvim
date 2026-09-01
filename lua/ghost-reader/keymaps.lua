local M = {}

local actions = require("ghost-reader.actions")

local plugin_prefix = "<Plug>(GhostReader"
local installed_global_maps = {}

local plug_defs = {
  Open = actions.open,
  Statusline = actions.statusline,
  Hide = actions.hide,
  Toc = actions.toc,
  Close = actions.close,
  NextContent = actions.next_content,
  PrevContent = actions.prev_content,
  NextPage = actions.next_page,
  PrevPage = actions.prev_page,
  NextChapter = actions.next_chapter,
  PrevChapter = actions.prev_chapter,
  Progress = actions.progress,
  Help = actions.help,
  ToggleAuto = actions.toggle_auto,
  Faster = actions.faster,
  Slower = actions.slower,
}

local function resolve(lhs)
  return (lhs or ""):gsub("<leader>", vim.g.mapleader or "\\")
end

local function set_map(mode, lhs, rhs, opts)
  vim.keymap.set(mode, resolve(lhs), rhs, vim.tbl_extend("force", { silent = true, nowait = true }, opts or {}))
end

local function del_map(mode, lhs, opts)
  pcall(vim.keymap.del, mode, resolve(lhs), opts or {})
end

local function find_global_map(lhs)
  local expected = vim.api.nvim_replace_termcodes(resolve(lhs), true, false, true)
  for _, map in ipairs(vim.api.nvim_get_keymap("n")) do
    local actual = map.lhsraw or vim.api.nvim_replace_termcodes(map.lhs, true, false, true)
    if actual == expected then
      return map
    end
  end
  return nil
end

local function clear_installed_global_maps()
  for _, installed in pairs(installed_global_maps) do
    local current = find_global_map(installed.lhs)
    if current and current.rhs == installed.rhs then
      del_map("n", installed.lhs)
    end
  end
  installed_global_maps = {}
end

local function capture_map(buf, lhs)
  local resolved = resolve(lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if map.lhs == resolved then
      return map
    end
  end
  return nil
end

local function restore_capture(buf, lhs, previous)
  return vim.api.nvim_buf_call(buf, function()
    if previous and next(previous) ~= nil then
      vim.fn.mapset("n", false, previous)
    else
      del_map("n", lhs, { buffer = buf })
    end
  end)
end

local function bind_plug(name, action)
  vim.keymap.set("n", plugin_prefix .. name .. ")", action, {
    silent = true,
    nowait = true,
    desc = "Ghost Reader: " .. name:gsub("([A-Z])", " %1"):gsub("^%s+", ""):lower(),
  })
end

function M.setup(config)
  config = config or require("ghost-reader.config").setup()
  for name, action in pairs(plug_defs) do
    bind_plug(name, action)
  end

  clear_installed_global_maps()

  local global = config.keymaps and config.keymaps.global or {}
  local plug_map = {
    open = "Open",
    hide = "Hide",
    toc = "Toc",
    close = "Close",
  }
  for key, plug in pairs(plug_map) do
    local lhs = global[key]
    if lhs then
      local rhs = "<Plug>(GhostReader" .. plug .. ")"
      set_map("n", lhs, rhs, { desc = "Ghost Reader: " .. key })
      installed_global_maps[key] = { lhs = resolve(lhs), rhs = rhs }
    end
  end
end

function M.attach(session, config, buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  if session.reader_buf == buf and session.reader_maps and next(session.reader_maps) ~= nil then
    return true
  end
  if session.reader_maps then
    M.detach(session)
  end

  local reader = (config.keymaps and config.keymaps.reader) or {}
  local statusline = (config.keymaps and config.keymaps.statusline) or {}
  session.reader_buf = buf
  session.reader_maps = {}

  local mappings = {
    { key = reader.next_content, plug = "NextContent", desc = "next content" },
    { key = reader.prev_content, plug = "PrevContent", desc = "prev content" },
    { key = reader.next_page, plug = "NextPage", desc = "next page" },
    { key = reader.prev_page, plug = "PrevPage", desc = "prev page" },
    { key = reader.next_chapter, plug = "NextChapter", desc = "next chapter" },
    { key = reader.prev_chapter, plug = "PrevChapter", desc = "prev chapter" },
    { key = reader.toc, plug = "Toc", desc = "table of contents" },
    { key = reader.progress, plug = "Progress", desc = "progress" },
    { key = reader.hide, plug = "Hide", desc = "hide" },
    { key = reader.close, plug = "Close", desc = "close" },
    { key = reader.help, plug = "Help", desc = "help" },
  }
  if session.mode == "statusline" then
    mappings[#mappings + 1] = { key = statusline.toggle_auto, plug = "ToggleAuto", desc = "toggle auto" }
    mappings[#mappings + 1] = { key = statusline.faster, plug = "Faster", desc = "faster" }
    mappings[#mappings + 1] = { key = statusline.slower, plug = "Slower", desc = "slower" }
  end

  for _, item in ipairs(mappings) do
    if item.key then
      local previous = capture_map(buf, item.key)
      session.reader_maps[resolve(item.key)] = { buf = buf, lhs = item.key, previous = previous }
      vim.api.nvim_buf_call(buf, function()
        vim.keymap.set("n", resolve(item.key), "<Plug>(GhostReader" .. item.plug .. ")", {
          buffer = buf,
          nowait = true,
          silent = true,
          desc = "Ghost Reader: " .. item.desc,
        })
      end)
    end
  end

  return true
end

function M.detach(session)
  if not session or not session.reader_maps then
    return
  end
  for _, capture in pairs(session.reader_maps) do
    if capture and capture.buf and capture.lhs and vim.api.nvim_buf_is_valid(capture.buf) then
      restore_capture(capture.buf, capture.lhs, capture.previous)
    end
  end
  session.reader_maps = nil
  session.reader_buf = nil
end

return M
