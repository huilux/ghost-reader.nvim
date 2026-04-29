local M = {}

local comment_prefixes = {
  python = "# ",
  lua = "-- ",
  javascript = "// ",
  typescript = "// ",
  typescriptreact = "// ",
  go = "// ",
  rust = "// ",
  java = "// ",
  c = "// ",
  cpp = "// ",
  css = "/* ",
  html = "<!-- ",
  sh = "# ",
  zsh = "# ",
  bash = "# ",
  yaml = "# ",
  toml = "# ",
  json = "// ",
  markdown = "<!-- ",
}

local tags = { "TODO", "FIXME", "NOTE", "HACK", "XXX", "REFACTOR", "OPTIMIZE", "REVIEW" }

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

local function wrap_comment(text, prefix, tag, indent, max_width)
  local header = indent .. prefix .. tag .. ": "
  local header_w = vim.fn.strwidth(header)
  local body_w = max_width - header_w
  if body_w < 20 then body_w = 20 end

  local text_w = vim.fn.strwidth(text)
  if text_w <= body_w then
    return { header .. text }
  end

  local lines = {}
  -- first line has tag header
  local cur = header
  local cur_w = header_w
  local i = 1
  local first = true

  while i <= #text do
    local ch, next_i = utf8_next(text, i)
    local cw = vim.fn.strwidth(ch)
    if cur_w + cw > max_width then
      table.insert(lines, cur)
      cur = indent .. prefix .. (first and "" or "  ")
      cur_w = vim.fn.strwidth(cur)
      first = false
    end
    cur = cur .. ch
    cur_w = cur_w + cw
    i = next_i
  end
  if cur ~= indent .. prefix then
    table.insert(lines, cur)
  end

  return lines
end

local function get_real_buffer_lines()
  local bufs = vim.api.nvim_list_bufs()
  local candidates = {}
  for _, buf in ipairs(bufs) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
      local bt = vim.bo[buf].buftype
      if bt == "" or bt == nil then
        local ft = vim.bo[buf].filetype
        if ft ~= "" and not ft:find("^git") then
          local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          if #lines >= 20 then
            table.insert(candidates, {
              lines = lines,
              ft = ft,
              path = vim.api.nvim_buf_get_name(buf),
            })
          end
        end
      end
    end
  end
  return candidates
end

local function pick_real_skeleton()
  local candidates = get_real_buffer_lines()
  if #candidates == 0 then return nil end
  -- Prefer larger files
  table.sort(candidates, function(a, b) return #a.lines > #b.lines end)
  local pick = candidates[math.random(math.min(3, #candidates))]
  return pick
end

function M.render(book_lines, opts)
  opts = opts or {}
  local lang = opts.lang or "python"

  -- Try to use real buffer as skeleton, fall back to preset
  local real = pick_real_skeleton()
  local skeleton, ft, path

  if real then
    skeleton = real.lines
    ft = real.ft
    path = real.path
  else
    local presets = require("ghost-reader.stealth.presets")
    local preset = presets.get(opts.preset or "random")
    skeleton = preset.lines
    ft = preset.filetype or lang
    path = preset.path
  end

  local prefix = comment_prefixes[ft] or comment_prefixes[lang] or "// "
  local skel_len = #skeleton

  local result = {}
  local book_cursor = 1
  local insert_interval = math.random(5, 8)
  local line_count = 0
  local tag_idx = math.random(1, #tags)
  local skel_idx = 1

  while book_cursor <= #book_lines do
    local skel_line = skeleton[skel_idx]
    table.insert(result, skel_line)
    skel_idx = skel_idx % skel_len + 1
    line_count = line_count + 1

    if line_count >= insert_interval then
      local book_text = book_lines[book_cursor]
      local tag = tags[tag_idx]
      tag_idx = tag_idx % #tags + 1
      local indent = skel_line:match("^(%s+)") or ""
      local wrapped = wrap_comment(book_text, prefix, tag, indent, 80)
      for _, wl in ipairs(wrapped) do
        table.insert(result, wl)
      end
      book_cursor = book_cursor + 1
      line_count = 0
      insert_interval = math.random(5, 8)
    end
  end

  return {
    lines = result,
    filetype = ft,
    fake_path = path or "source.py",
  }
end

return M
