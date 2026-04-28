local M = {}

local comment_prefixes = {
  python = "# ",
  lua = "-- ",
  javascript = "// ",
  typescript = "// ",
  typescriptreact = "// ",
  go = "// ",
  rust = "// ",
}

local tags = { "TODO", "FIXME", "NOTE", "HACK", "XXX" }

function M.render(book_lines, opts)
  opts = opts or {}
  local lang = opts.lang or "python"
  local presets = require("ghost-reader.stealth.presets")
  local preset = presets.get(opts.preset or "random")

  local skeleton = vim.deepcopy(preset.lines)
  local ft = preset.filetype or lang
  local prefix = comment_prefixes[ft] or comment_prefixes[lang] or comment_prefixes.python
  local path = preset.path

  -- Repeat skeleton to fill the screen (target ~120 lines)
  local target_lines = 120
  local full_skeleton = {}
  while #full_skeleton < target_lines do
    for _, line in ipairs(skeleton) do
      table.insert(full_skeleton, line)
      if #full_skeleton >= target_lines then break end
    end
  end

  local result = {}
  local book_cursor = 1
  local insert_interval = math.random(2, 3)
  local line_count = 0
  local tag_idx = 1

  for _, line in ipairs(full_skeleton) do
    table.insert(result, line)
    line_count = line_count + 1

    if book_cursor <= #book_lines and line_count >= insert_interval then
      local book_text = book_lines[book_cursor]
      local tag = tags[tag_idx]
      tag_idx = tag_idx % #tags + 1
      local indent = line:match("^(%s)") or ""
      table.insert(result, indent .. prefix .. tag .. ": " .. book_text)
      book_cursor = book_cursor + 1
      line_count = 0
      insert_interval = math.random(2, 3)
    end
  end

  -- If book text remains, spread them evenly into the result (not clustered at bottom)
  if book_cursor <= #book_lines then
    local remaining = {}
    while book_cursor <= #book_lines do
      table.insert(remaining, book_lines[book_cursor])
      book_cursor = book_cursor + 1
    end
    local step = math.max(1, math.floor(#result / (#remaining + 1)))
    local insert_positions = {}
    for i = 1, #remaining do
      local pos = math.min(step * i + i, #result + 1)
      table.insert(insert_positions, pos)
    end
    -- Insert in reverse to keep positions valid
    for i = #remaining, 1, -1 do
      local pos = insert_positions[i]
      local tag = tags[(tag_idx + i - 2) % #tags + 1]
      local text = prefix .. tag .. ": " .. remaining[i]
      table.insert(result, pos, text)
    end
  end

  return {
    lines = result,
    filetype = ft,
    fake_path = path,
  }
end

return M
