local M = {}

local bookshelf = require("ghost-reader.bookshelf")
local progress = require("ghost-reader.reader.progress")
local history = require("ghost-reader.history")

M.state = nil
M.timer = nil
M.current_line = ""
M._saved_statusline = nil

function M.statusline()
  local mode_text = ""
  if M.state then
    mode_text = M.state.auto_mode and " ▶ " or " ‖ "
  end
  return " %t %m %y %=" .. mode_text .. M.current_line .. "  %l,%c "
end

local function update_display(text)
  if text and text ~= "" then
    M.current_line = text
  end
end

local function advance()
  if not M.state then return end
  local st = M.state
  local chapter = st.book.chapters[st.chapter_index]
  if not chapter then M.stop(); return end

  -- skip empty lines
  while true do
    st.line_offset = st.line_offset + 1
    if st.line_offset > #chapter.lines then
      if st.chapter_index >= #st.book.chapters then
        M.current_line = "(END)"
        return
      end
      st.chapter_index = st.chapter_index + 1
      st.line_offset = 0
      chapter = st.book.chapters[st.chapter_index]
    else
      break
    end
  end

  update_display(chapter.lines[st.line_offset])
end

local function go_back()
  if not M.state then return end
  local st = M.state
  local chapter = st.book.chapters[st.chapter_index]
  if not chapter then return end

  for _ = 1, 2 do
    st.line_offset = st.line_offset - 1
    if st.line_offset < 1 then
      if st.chapter_index <= 1 then
        st.line_offset = 1
        break
      end
      st.chapter_index = st.chapter_index - 1
      chapter = st.book.chapters[st.chapter_index]
      st.line_offset = #chapter.lines
    end
  end

  update_display(chapter.lines[st.line_offset])
end

local function start_timer()
  if M.timer then vim.fn.timer_stop(M.timer) end
  if not M.state or not M.state.auto_mode then return end
  M.timer = vim.fn.timer_start(M.state.interval, function()
    if M.state and M.state.auto_mode then
      advance()
      start_timer()
    end
  end)
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

  M._saved_statusline = vim.o.statusline

  local sl_cfg = config.statusline or {}
  local auto_mode = sl_cfg.mode ~= "manual"

  M.state = {
    book = book,
    chapter_index = chapter_index,
    line_offset = line_offset,
    auto_mode = auto_mode,
    interval = sl_cfg.interval or 3000,
    config = config,
  }
  M.current_line = ""

  -- use %! expression so statusline always re-evaluates
  vim.api.nvim_set_option_value("statusline",
    "%!v:lua.require('ghost-reader.statusline_reader').statusline()",
    { win = vim.api.nvim_get_current_win() })

  -- show first line
  advance()

  if auto_mode then start_timer() end

  history.record(path, config)
  M._set_keymaps()

  local name = vim.fn.fnamemodify(path, ":t:r")
  local mode_label = auto_mode and "自动" or "手动"
  vim.notify(
    string.format("[ghost-reader] %s · 状态栏%s模式\nJ/K=翻行 +/-=调速 m=切换模式 q=退出",
      name, mode_label),
    vim.log.levels.INFO
  )
end

function M.stop()
  if M.timer then
    vim.fn.timer_stop(M.timer)
    M.timer = nil
  end
  if M.state then
    local fake_book = { path = M.state.book.path, chapters = M.state.book.chapters }
    progress.save(fake_book, M.state, M.state.config)
    bookshelf.close()
  end
  M.state = nil
  M.current_line = ""
  if M._saved_statusline then
    vim.api.nvim_set_option_value("statusline", M._saved_statusline,
      { win = vim.api.nvim_get_current_win() })
    M._saved_statusline = nil
  end
  for _, key in ipairs({ "J", "K", "+", "-", "m", "q" }) do
    pcall(vim.keymap.del, "n", key, { buffer = 0 })
  end
end

function M._set_keymaps()
  local opts = { buffer = 0, nowait = true, silent = true }

  vim.keymap.set("n", "J", function()
    advance()
    if M.state and M.state.auto_mode then start_timer() end
  end, opts)

  vim.keymap.set("n", "K", function()
    go_back()
    if M.state and M.state.auto_mode then start_timer() end
  end, opts)

  vim.keymap.set("n", "+", function()
    if not M.state then return end
    M.state.interval = math.max(500, M.state.interval - 500)
    if M.state.auto_mode then start_timer() end
    vim.notify("[ghost-reader] " .. M.state.interval .. "ms", vim.log.levels.INFO)
  end, opts)

  vim.keymap.set("n", "-", function()
    if not M.state then return end
    M.state.interval = math.min(15000, M.state.interval + 500)
    if M.state.auto_mode then start_timer() end
    vim.notify("[ghost-reader] " .. M.state.interval .. "ms", vim.log.levels.INFO)
  end, opts)

  vim.keymap.set("n", "m", function()
    if not M.state then return end
    M.state.auto_mode = not M.state.auto_mode
    if M.state.auto_mode then
      start_timer()
      vim.notify("[ghost-reader] auto ▶", vim.log.levels.INFO)
    else
      if M.timer then vim.fn.timer_stop(M.timer); M.timer = nil end
      vim.notify("[ghost-reader] manual ‖", vim.log.levels.INFO)
    end
  end, opts)

  vim.keymap.set("n", "q", function()
    M.stop()
    vim.notify("[ghost-reader] stopped", vim.log.levels.INFO)
  end, opts)
end

return M
