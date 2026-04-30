local M = {}
local navigate = require("ghost-reader.reader.navigate")
local bookshelf = require("ghost-reader.bookshelf")
local utils = require("ghost-reader.utils")
local statusline = require("ghost-reader.stealth.statusline")
local renderer = require("ghost-reader.renderer")
local progress = require("ghost-reader.reader.progress")

M.state = nil
M.page_size = 40

function M.open(path, config)
  local book, err = bookshelf.open(path)
  if err then
    vim.notify("[ghost-reader] " .. err, vim.log.levels.ERROR)
    return false
  end

  local prev_buf = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)

  local state = {
    book = book,
    buf = buf,
    prev_buf = prev_buf,
    chapter_index = 1,
    line_offset = 0,
    config = config,
  }

  local saved = progress.load(book, config)
  if saved then
    state.chapter_index = math.min(saved.chapter_index or 1, #book.chapters)
    state.line_offset = saved.line_offset or 0
  end

  M.state = state
  M.page_size = math.floor(vim.o.lines * 0.85)

  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].modifiable = true

  statusline.save()
  M._render(state)
  M._set_keymaps(buf, config.keymaps)

  local book_name = vim.fn.fnamemodify(path, ":t:r")
  vim.notify(
    string.format("[ghost-reader] %s · %d chapters\nJ/K=翻页 ]c/[c=章节 <Esc><Esc>=老板键",
      book_name, #book.chapters),
    vim.log.levels.INFO
  )
  vim.api.nvim_create_autocmd({ "BufUnload", "CursorHold" }, {
    buffer = buf,
    callback = function()
      if M.state then
        progress.save(M.state.book, M.state, M.state.config)
      end
    end,
  })
  return true
end

function M._render(state)
  local chapter = state.book.chapters[state.chapter_index]
  if not chapter then return end
  local raw_lines = navigate.get_page_lines(chapter.lines, state.line_offset, M.page_size)
  if #raw_lines == 0 then raw_lines = { "(empty chapter)" } end

  local rendered = renderer.render(raw_lines)

  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, rendered.lines)
  vim.bo[state.buf].filetype = rendered.filetype
  if rendered.fake_path then
    pcall(vim.api.nvim_buf_set_name, state.buf, rendered.fake_path)
  end
  vim.api.nvim_buf_call(state.buf, function()
    vim.cmd("normal! gg")
  end)

  statusline.apply(rendered.fake_path, rendered.filetype)
end

function M._set_keymaps(buf, keymaps)
  local function map(key, action)
    if not key then return end
    local resolved = key:gsub("<leader>", vim.g.mapleader or "\\")
    vim.keymap.set("n", resolved, action, { buffer = buf, nowait = true, silent = true })
  end

  map(keymaps.next_page, function() M.next_page() end)
  map(keymaps.prev_page, function() M.prev_page() end)
  map(keymaps.next_chapter, function() M.next_chapter() end)
  map(keymaps.prev_chapter, function() M.prev_chapter() end)
  map(keymaps.boss_key, function()
    if M.state and vim.api.nvim_buf_is_valid(M.state.prev_buf) then
      progress.save(M.state.book, M.state, M.state.config)
      vim.api.nvim_set_current_buf(M.state.prev_buf)
    end
  end)

  map(keymaps.toc, function()
    if not M.state then return end
    local items = {}
    for _, entry in ipairs(M.state.book.toc) do
      table.insert(items, entry.title)
    end
    vim.ui.select(items, { prompt = "Table of Contents:" }, function(_, idx)
      if idx then M.go_to_chapter(idx) end
    end)
  end)

  map(keymaps.progress, function()
    if M.state then progress.show(M.state.book, M.state) end
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

function M.restore()
  if M.state and vim.api.nvim_buf_is_valid(M.state.buf) then
    vim.api.nvim_set_current_buf(M.state.buf)
  end
end

function M.close()
  if M.state and vim.api.nvim_buf_is_valid(M.state.buf) then
    vim.api.nvim_buf_delete(M.state.buf, { force = true })
  end
  bookshelf.close()
  M.state = nil
end

return M
