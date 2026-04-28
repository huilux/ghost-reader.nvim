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

  -- Repeat skeleton to fill ~150 lines
  local target_lines = 150
  local full_skeleton = {}
  while #full_skeleton < target_lines do
    for _, line in ipairs(skeleton) do
      table.insert(full_skeleton, line)
      if #full_skeleton >= target_lines then break end
    end
  end

  local result = {}
  local book_cursor = 1
  -- Sparse spacing: 5-8 lines between each book comment
  local insert_interval = math.random(5, 8)
  local line_count = 0
  local tag_idx = math.random(1, #tags)

  for _, line in ipairs(full_skeleton) do
    table.insert(result, line)
    line_count = line_count + 1

    if book_cursor <= #book_lines and line_count >= insert_interval then
      local book_text = book_lines[book_cursor]
      local tag = tags[tag_idx]
      tag_idx = tag_idx % #tags + 1
      -- Match the indentation of the current line
      local indent = line:match("^(%s+)") or ""
      table.insert(result, indent .. prefix .. tag .. ": " .. book_text)
      book_cursor = book_cursor + 1
      line_count = 0
      insert_interval = math.random(5, 8)
    end
  end

  -- If book text remains, spread evenly (not clustered)
  if book_cursor <= #book_lines then
    local remaining = {}
    while book_cursor <= #book_lines do
      table.insert(remaining, book_lines[book_cursor])
      book_cursor = book_cursor + 1
    end
    local step = math.max(6, math.floor(#result / (#remaining + 1)))
    local insert_positions = {}
    for i = 1, #remaining do
      local pos = math.min(step * i, #result + 1)
      table.insert(insert_positions, pos)
    end
    for i = #remaining, 1, -1 do
      local pos = insert_positions[i]
      local tag = tags[(tag_idx + i - 2) % #tags + 1]
      table.insert(result, pos, prefix .. tag .. ": " .. remaining[i])
    end
  end

  return {
    lines = result,
    filetype = ft,
    fake_path = path or "source.py",
  }
end

return M
