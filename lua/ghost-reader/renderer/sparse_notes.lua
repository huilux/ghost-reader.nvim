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

  local result = {}
  local book_cursor = 1
  local insert_interval = math.random(4, 6)
  local line_count = 0
  local tag_idx = 1

  for _, line in ipairs(skeleton) do
    table.insert(result, line)
    line_count = line_count + 1

    if book_cursor <= #book_lines and line_count >= insert_interval then
      local book_text = book_lines[book_cursor]
      if #book_text > 60 then
        book_text = book_text:sub(1, 57) .. ".."
      end
      local tag = tags[tag_idx]
      tag_idx = tag_idx % #tags + 1
      local indent = line:match("^(%s)") or ""
      table.insert(result, indent .. prefix .. tag .. ": " .. book_text)
      book_cursor = book_cursor + 1
      line_count = 0
      insert_interval = math.random(4, 6)
    end
  end

  while book_cursor <= #book_lines and #result < 200 do
    local book_text = book_lines[book_cursor]
    if #book_text > 60 then
      book_text = book_text:sub(1, 57) .. ".."
    end
    local tag = tags[tag_idx]
    tag_idx = tag_idx % #tags + 1
    table.insert(result, prefix .. tag .. ": " .. book_text)
    book_cursor = book_cursor + 1
  end

  return {
    lines = result,
    filetype = ft,
    fake_path = path,
  }
end

return M
