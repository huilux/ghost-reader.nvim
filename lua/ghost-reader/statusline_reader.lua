local M = {}

local bookshelf = require("ghost-reader.bookshelf")
local progress = require("ghost-reader.reader.progress")
local history = require("ghost-reader.history")

M.state = nil
M.timer = nil
M.chunks = {}
M.chunk_idx = 0
M._buf = nil
M._win = nil
M._augroup = nil
M._hidden = false

local function utf8_next(s, i)
  if i > #s then return nil end
  local b = s:byte(i)
  local len
  if b < 0x80 then len = 1
  elseif b < 0xE0 then len = 2
  elseif b < 0xF0 then len = 3
  else len = 4
  end
  return s:sub(i, i + len - 1), i + len
end

local function char_width(ch)
  return vim.fn.strwidth(ch)
end

local function split_to_chunks(text, max_width)
  if text == "" then return { "" } end
  local chunks = {}
  local current = ""
  local cur_w = 0
  local i = 1

  while i <= #text do
    local ch
    ch, i = utf8_next(text, i)
    local cw = char_width(ch)

    if cur_w + cw > max_width and current ~= "" then
      table.insert(chunks, current)
      current = ch
      cur_w = cw
    else
      current = current .. ch
      cur_w = cur_w + cw
    end
  end

  if current ~= "" then
    table.insert(chunks, current)
  end

  return chunks
end

local function get_max_width()
  return vim.o.columns - 4
end

local function load_chunks(text)
  M.chunks = split_to_chunks(text, get_max_width())
  M.chunk_idx = 1
end

local function create_float_win()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.api.nvim_win_close(M._win, true)
  end
  if M._buf and vim.api.nvim_buf_is_valid(M._buf) then
    vim.api.nvim_buf_delete(M._buf, { force = true })
  end

  M._buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M._buf].buftype = "nofile"
  vim.bo[M._buf].bufhidden = "wipe"

  local total_w = vim.o.columns
  local total_h = vim.o.lines
  local row = total_h - 3

  M._win = vim.api.nvim_open_win(M._buf, false, {
    relative = "editor",
    width = total_w,
    height = 1,
    row = row,
    col = 0,
    style = "minimal",
    focusable = false,
    zindex = 50,
  })
  vim.wo[M._win].winhl = "Normal:Comment"
  vim.wo[M._win].wrap = false
end

local function refresh_display()
  if not M._buf or not vim.api.nvim_buf_is_valid(M._buf) then return end
  local st = M.state
  local icon = st and (st.auto_mode and "▶ " or "‖ ") or ""
  local text = M.chunks[M.chunk_idx] or ""
  vim.api.nvim_buf_set_lines(M._buf, 0, -1, false, { icon .. text })
end

local function advance_line()
  if not M.state then return false end
  local st = M.state
  local chapter = st.book.chapters[st.chapter_index]
  if not chapter then return false end

  while true do
    st.line_offset = st.line_offset + 1
    if st.line_offset > #chapter.lines then
      if st.chapter_index >= #st.book.chapters then
        load_chunks("(END)")
        return false
      end
      st.chapter_index = st.chapter_index + 1
      st.line_offset = 0
      chapter = st.book.chapters[st.chapter_index]
    else
      local line = chapter.lines[st.line_offset]
      if line and line ~= "" then
        load_chunks(line)
        return true
      end
    end
  end
end

local function advance()
  if not M.state then return end
  -- show next chunk of current line
  if M.chunk_idx < #M.chunks then
    M.chunk_idx = M.chunk_idx + 1
  else
    advance_line()
  end
  refresh_display()
end

local function go_back_line()
  if not M.state then return end
  local st = M.state
  local chapter = st.book.chapters[st.chapter_index]
  if not chapter then return end

  while true do
    st.line_offset = st.line_offset - 1
    if st.line_offset < 1 then
      if st.chapter_index <= 1 then
        st.line_offset = 1
        chapter = st.book.chapters[1]
        break
      end
      st.chapter_index = st.chapter_index - 1
      chapter = st.book.chapters[st.chapter_index]
      st.line_offset = #chapter.lines
    end
    if chapter.lines[st.line_offset] and chapter.lines[st.line_offset] ~= "" then
      break
    end
  end

  load_chunks(chapter.lines[st.line_offset] or "")
end

local function go_back()
  if not M.state then return end
  -- go to previous chunk, or previous line
  if M.chunk_idx > 1 then
    M.chunk_idx = M.chunk_idx - 1
  else
    go_back_line()
  end
  refresh_display()
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
  M.chunks = {}
  M.chunk_idx = 0

  create_float_win()

  M._augroup = vim.api.nvim_create_augroup("ghost-reader-statusline", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = M._augroup,
    callback = function()
      if M._win and vim.api.nvim_win_is_valid(M._win) then
        vim.api.nvim_win_set_config(M._win, {
          relative = "editor",
          width = vim.o.columns,
          height = 1,
          row = vim.o.lines - 3,
          col = 0,
        })
      end
    end,
  })

  advance_line()
  refresh_display()

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
  if M._augroup then
    vim.api.nvim_del_augroup_by_name("ghost-reader-statusline")
    M._augroup = nil
  end
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.api.nvim_win_close(M._win, true)
  end
  M._win = nil
  if M._buf and vim.api.nvim_buf_is_valid(M._buf) then
    vim.api.nvim_buf_delete(M._buf, { force = true })
  end
  M._buf = nil
  if M.state then
    local fake_book = { path = M.state.book.path, chapters = M.state.book.chapters }
    progress.save(fake_book, M.state, M.state.config)
    bookshelf.close()
  end
  M.state = nil
  M.chunks = {}
  M.chunk_idx = 0
  M._hidden = false
  for _, key in ipairs({ "J", "K", "+", "-", "m", "q", "<Esc>", "<leader>gr" }) do
    pcall(vim.keymap.del, "n", key, { buffer = 0 })
  end
end

function M.hide()
  if not M.state or M._hidden then return end
  M._hidden = true
  if M.timer then
    vim.fn.timer_stop(M.timer)
    M.timer = nil
  end
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.api.nvim_win_close(M._win, true)
    M._win = nil
  end
  if M._buf and vim.api.nvim_buf_is_valid(M._buf) then
    vim.api.nvim_buf_delete(M._buf, { force = true })
    M._buf = nil
  end
end

function M.restore()
  if not M.state or not M._hidden then return end
  M._hidden = false
  create_float_win()
  refresh_display()
  if M.state.auto_mode then start_timer() end
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
    refresh_display()
  end, opts)

  vim.keymap.set("n", "q", function()
    M.stop()
    vim.notify("[ghost-reader] stopped", vim.log.levels.INFO)
  end, opts)

  vim.keymap.set("n", "<Esc><Esc>", function()
    M.hide()
  end, opts)

  vim.keymap.set("n", "<leader>gr", function()
    M.restore()
  end, opts)
end

return M
