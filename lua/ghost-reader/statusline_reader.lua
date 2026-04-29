local M = {}

local bookshelf = require("ghost-reader.bookshelf")
local progress = require("ghost-reader.reader.progress")
local history = require("ghost-reader.history")

M.state = nil
M.timer = nil
M.saved_statusline = nil

local function display_line(text)
  local win = vim.api.nvim_get_current_win()
  local max = vim.o.columns - 20
  if #text > max then
    text = text:sub(1, max) .. "..."
  end
  vim.api.nvim_set_option_value("statusline",
    " %t %m %y %= " .. text .. " %l,%c ",
    { win = win })
end

local function advance()
  if not M.state then return end
  local st = M.state

  st.line_offset = st.line_offset + 1
  local chapter = st.book.chapters[st.chapter_index]
  if not chapter then M.stop(); return end

  if st.line_offset > #chapter.lines then
    if st.chapter_index >= #st.book.chapters then
      M.stop()
      return
    end
    st.chapter_index = st.chapter_index + 1
    st.line_offset = 1
    chapter = st.book.chapters[st.chapter_index]
  end

  local line = chapter.lines[st.line_offset]
  if line and line ~= "" then
    display_line(line)
  end
end

function M.start(path, config)
  if M.timer then M.stop() end

  local book, err = bookshelf.open(path)
  if err then
    vim.notify("[ghost-reader] " .. err, vim.log.levels.ERROR)
    return
  end

  local chapter_index = 1
  local line_offset = 0

  local fake_book = { path = path, chapters = book.chapters }
  local saved = progress.load(fake_book, config)
  if saved then
    chapter_index = math.min(saved.chapter_index or 1, #book.chapters)
    line_offset = saved.line_offset or 0
  end

  M.saved_statusline = vim.o.statusline
  M.state = {
    book = book,
    chapter_index = chapter_index,
    line_offset = line_offset,
    interval = (config.statusline and config.statusline.interval) or 3000,
    config = config,
  }

  -- show first line immediately
  advance()

  M.timer = vim.fn.timer_start(M.state.interval, function()
    if M.state then advance() end
  end, { ["repeat"] = -1 })

  history.record(path, config)
  local name = vim.fn.fnamemodify(path, ":t:r")
  vim.notify(
    string.format("[ghost-reader] statusline: %s\n+/- 调速 p 暂停 q 退出", name),
    vim.log.levels.INFO
  )

  M._set_keymaps()
end

function M.stop()
  if M.timer then
    vim.fn.timer_stop(M.timer)
    M.timer = nil
  end
  if M.saved_statusline then
    vim.api.nvim_set_option_value("statusline", M.saved_statusline,
      { win = vim.api.nvim_get_current_win() })
    M.saved_statusline = nil
  end
  if M.state then
    local fake_book = { path = M.state.book.path, chapters = M.state.book.chapters }
    progress.save(fake_book, M.state, M.state.config)
    bookshelf.close()
  end
  M.state = nil
  pcall(vim.keymap.del, "n", "+", { buffer = 0 })
  pcall(vim.keymap.del, "n", "-", { buffer = 0 })
  pcall(vim.keymap.del, "n", "p", { buffer = 0 })
  pcall(vim.keymap.del, "n", "q", { buffer = 0 })
end

function M._set_keymaps()
  local opts = { buffer = 0, nowait = true, silent = true }

  vim.keymap.set("n", "+", function()
    if not M.state then return end
    M.state.interval = math.max(500, M.state.interval - 500)
    vim.fn.timer_stop(M.timer)
    M.timer = vim.fn.timer_start(M.state.interval, function()
      if M.state then advance() end
    end, { ["repeat"] = -1 })
    vim.notify("[ghost-reader] speed: " .. M.state.interval .. "ms", vim.log.levels.INFO)
  end, opts)

  vim.keymap.set("n", "-", function()
    if not M.state then return end
    M.state.interval = math.min(15000, M.state.interval + 500)
    vim.fn.timer_stop(M.timer)
    M.timer = vim.fn.timer_start(M.state.interval, function()
      if M.state then advance() end
    end, { ["repeat"] = -1 })
    vim.notify("[ghost-reader] speed: " .. M.state.interval .. "ms", vim.log.levels.INFO)
  end, opts)

  vim.keymap.set("n", "p", function()
    if M.timer and M.state then
      vim.fn.timer_stop(M.timer)
      M.timer = nil
      vim.notify("[ghost-reader] paused", vim.log.levels.INFO)
    elseif M.state then
      M.timer = vim.fn.timer_start(M.state.interval, function()
        if M.state then advance() end
      end, { ["repeat"] = -1 })
      vim.notify("[ghost-reader] resumed", vim.log.levels.INFO)
    end
  end, opts)

  vim.keymap.set("n", "q", function()
    M.stop()
    vim.notify("[ghost-reader] statusline reader stopped", vim.log.levels.INFO)
  end, opts)
end

return M
