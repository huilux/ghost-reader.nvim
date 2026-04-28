local M = {}
local navigate = require("ghost-reader.reader.navigate")
local bookshelf = require("ghost-reader.bookshelf")
local utils = require("ghost-reader.utils")

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

  M._render(state)
  M._set_keymaps(buf, config.keymaps)
  return true
end

function M._render(state)
  local chapter = state.book.chapters[state.chapter_index]
  if not chapter then return end
  local lines = navigate.get_page_lines(chapter.lines, state.line_offset, M.page_size)
  if #lines == 0 then lines = { "(empty chapter)" } end
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
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
  -- Will be implemented in Task 8
end

function M.restore()
  -- Will be implemented in Task 7
end

function M.close()
  if M.state and vim.api.nvim_buf_is_valid(M.state.buf) then
    vim.api.nvim_buf_delete(M.state.buf, { force = true })
  end
  bookshelf.close()
  M.state = nil
end

return M
