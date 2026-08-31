local M = {}

local actions = require("ghost-reader.actions")

local plugin_prefix = "<Plug>(GhostReader"

local plug_defs = {
  Open = actions.open,
  Statusline = actions.statusline,
  Control = actions.control,
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
  ExitControls = actions.exit_controls,
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

  local global = config.keymaps and config.keymaps.global or {}
  local plug_map = {
    open = "Open",
    statusline = "Statusline",
    control = "Control",
    hide = "Hide",
    toc = "Toc",
    close = "Close",
  }
  for key, plug in pairs(plug_map) do
    local lhs = global[key]
    if lhs then
      set_map("n", lhs, "<Plug>(GhostReader" .. plug .. ")", { desc = "Ghost Reader: " .. key })
    end
  end
end

function M.enter_controls(session, config)
  local controls = (config.keymaps and config.keymaps.controls) or {}
  local statusline = (config.keymaps and config.keymaps.statusline) or {}
  local buf = session.control_buf
  session.control_maps = session.control_maps or {}

  local mappings = {
    { key = controls.next_content, plug = "NextContent", desc = "next content" },
    { key = controls.prev_content, plug = "PrevContent", desc = "prev content" },
    { key = controls.next_page, plug = "NextPage", desc = "next page" },
    { key = controls.prev_page, plug = "PrevPage", desc = "prev page" },
    { key = controls.next_chapter, plug = "NextChapter", desc = "next chapter" },
    { key = controls.prev_chapter, plug = "PrevChapter", desc = "prev chapter" },
    { key = controls.toc, plug = "Toc", desc = "table of contents" },
    { key = controls.progress, plug = "Progress", desc = "progress" },
    { key = controls.hide, plug = "Hide", desc = "hide" },
    { key = controls.close, plug = "Close", desc = "close" },
    { key = controls.help, plug = "Help", desc = "help" },
    { key = controls.exit_controls, plug = "ExitControls", desc = "exit controls" },
  }
  if session.mode == "statusline" then
    mappings[#mappings + 1] = { key = statusline.toggle_auto, plug = "ToggleAuto", desc = "toggle auto" }
    mappings[#mappings + 1] = { key = statusline.faster, plug = "Faster", desc = "faster" }
    mappings[#mappings + 1] = { key = statusline.slower, plug = "Slower", desc = "slower" }
  end

  for _, item in ipairs(mappings) do
    if item.key then
      local previous = capture_map(buf, item.key)
      session.control_maps[resolve(item.key)] = { buf = buf, lhs = item.key, previous = previous }
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

  session.controls_active = true
end

function M.leave_controls(session)
  if not session or not session.control_maps then
    return
  end
  for _, capture in pairs(session.control_maps) do
    if capture and capture.buf and capture.lhs then
      restore_capture(capture.buf, capture.lhs, capture.previous)
    end
  end
  session.control_maps = {}
  session.controls_active = false
end

return M
