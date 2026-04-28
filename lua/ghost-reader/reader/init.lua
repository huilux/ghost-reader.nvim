local M = {}
local navigate = require("ghost-reader.reader.navigate")
local bookshelf = require("ghost-reader.bookshelf")
local utils = require("ghost-reader.utils")
local stealth = require("ghost-reader.stealth")
local renderer = require("ghost-reader.renderer")

M.state = nil
M.page_size = 40

function M.open(path, config)
  local book, err = bookshelf.open(path)
  if err then
    vim.notify("[ghost-reader] " .. err, vim.log.levels.ERROR)
    return false
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local state = {
    book = book,
    buf = buf,
    chapter_index = 1,
    line_offset = 0,
    config = config,
  }
  M.state = state
  M.page_size = math.floor(vim.o.lines * 0.85)

  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = true

  stealth.setup(config)
  local boss_key = require("ghost-reader.stealth.boss_key")
  boss_key.capture_from_current()

  M._render(state)
  M._set_keymaps(buf, config.keymaps)
  return true
end

function M._render(state)
  local chapter = state.book.chapters[state.chapter_index]
  if not chapter then return end
  local raw_lines = navigate.get_page_lines(chapter.lines, state.line_offset, M.page_size)
  if #raw_lines == 0 then raw_lines = { "(empty chapter)" } end

  local mode = state.config.default_mode
  local rendered = renderer.render(raw_lines, mode, {
    lang = state.config.camouflage_lang,
  })

  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, rendered.lines)
  vim.bo[state.buf].filetype = rendered.filetype
  if rendered.fake_path then
    vim.api.nvim_buf_set_name(state.buf, rendered.fake_path)
  end
  vim.api.nvim_buf_call(state.buf, function()
    vim.cmd("normal! gg")
  end)
end

function M._set_keymaps(buf, keymaps)
  local function map(key, action)
    if not key then return end
    vim.keymap.set("n", key, action, { buffer = buf, nowait = true, silent = true })
  end

  map(keymaps.next_page, function() M.next_page() end)
  map(keymaps.prev_page, function() M.prev_page() end)
  map(keymaps.next_chapter, function() M.next_chapter() end)
  map(keymaps.prev_chapter, function() M.prev_chapter() end)
  map(keymaps.restore, function() M.restore() end)
  map(keymaps.switch_mode, function() M.switch_mode() end)
  map(keymaps.boss_key, function()
    stealth.activate_boss_key(M.state and M.state.buf)
  end)
end

function M.next_page()
  if not M.state then return end
  navigate.next_page(M.state, M.page_size)
  M._render(M.state)
end

function M.prev_page()
  if not M.state then return end
  navigate.prev_page(M.state, M.page_size)
  M._render(M.state)
end

function M.next_chapter()
  if not M.state then return end
  navigate.next_chapter(M.state)
  M._render(M.state)
end

function M.prev_chapter()
  if not M.state then return end
  navigate.prev_chapter(M.state)
  M._render(M.state)
end

function M.go_to_chapter(idx)
  if not M.state then return end
  navigate.go_to_chapter(M.state, idx)
  M._render(M.state)
end

function M.switch_mode()
  if not M.state then return end
  local modes = { "minimal_diff", "code_camouflage", "dual_mode" }
  local current = M.state.config.default_mode
  local next_idx = 1
  for i, m in ipairs(modes) do
    if m == current then next_idx = i % #modes + 1; break end
  end
  M.state.config.default_mode = modes[next_idx]
  M._render(M.state)
  vim.notify("[ghost-reader] mode: " .. modes[next_idx], vim.log.levels.INFO)
end

function M.restore()
  stealth.deactivate_boss_key(M.state and M.state.buf)
  if M.state then M._render(M.state) end
end

function M.close()
  if M.state and vim.api.nvim_buf_is_valid(M.state.buf) then
    vim.api.nvim_buf_delete(M.state.buf, { force = true })
  end
  bookshelf.close()
  M.state = nil
end

return M
