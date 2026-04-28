local M = {}
local navigate = require("ghost-reader.reader.navigate")
local bookshelf = require("ghost-reader.bookshelf")
local utils = require("ghost-reader.utils")
local stealth = require("ghost-reader.stealth")
local statusline = require("ghost-reader.stealth.statusline")
local renderer = require("ghost-reader.renderer")
local bookmark = require("ghost-reader.reader.bookmark")
local progress = require("ghost-reader.reader.progress")

M.state = nil
M.page_size = 40

function M.open(path, config)
  local book, err = bookshelf.open(path)
  if err then
    vim.notify("[ghost-reader] " .. err, vim.log.levels.ERROR)
    return false
  end

  stealth.setup(config)
  local boss_key = require("ghost-reader.stealth.boss_key")
  boss_key.capture_from_current()

  local buf = vim.api.nvim_create_buf(false, true)

  local state = {
    book = book,
    buf = buf,
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
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = true

  statusline.save()
  M._render(state)
  M._set_keymaps(buf, config.keymaps)
  M._bookmark = nil

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
    vim.keymap.set("n", key, action, { buffer = buf, nowait = true, silent = true })
  end

  map(keymaps.next_page, function() M.next_page() end)
  map(keymaps.prev_page, function() M.prev_page() end)
  map(keymaps.next_chapter, function() M.next_chapter() end)
  map(keymaps.prev_chapter, function() M.prev_chapter() end)
  map(keymaps.restore, function() M.restore() end)
  map(keymaps.boss_key, function()
    stealth.activate_boss_key(M.state and M.state.buf)
  end)

  map(keymaps.bookmark_add, function()
    if not M.state then return end
    local row = vim.api.nvim_win_get_cursor(0)[1]
    M._bookmark = M._bookmark or bookmark.new("current")
    M._bookmark:add(row)
    vim.notify("[ghost-reader] bookmark added at line " .. row, vim.log.levels.INFO)
  end)

  map(keymaps.bookmark_list, function()
    if M.state or not M._bookmark then return end
    local items = M._bookmark:list()
    if #items == 0 then
      vim.notify("[ghost-reader] no bookmarks", vim.log.levels.WARN)
      return
    end
    vim.ui.select(items, {
      prompt = "Bookmarks:",
      format_item = function(item)
        return "L" .. item.line .. (item.note ~= "" and (" - " .. item.note) or "")
      end,
    }, function(choice)
      if choice then
        vim.api.nvim_win_set_cursor(0, { choice.line, 0 })
      end
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
