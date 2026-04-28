local M = {}

local comment_patterns = {
  python = { prefix = "# ", pattern = "^(%s*)#%s*(.*)$" },
  lua = { prefix = "-- ", pattern = "^(%s*)%-%-%s*(.*)$" },
  javascript = { prefix = "// ", pattern = "^(%s*)//%s*(.*)$" },
  typescript = { prefix = "// ", pattern = "^(%s*)//%s*(.*)$" },
  typescriptreact = { prefix = "// ", pattern = "^(%s*)//%s*(.*)$" },
  go = { prefix = "// ", pattern = "^(%s*)//%s*(.*)$" },
  rust = { prefix = "// ", pattern = "^(%s*)//%s*(.*)$" },
  java = { prefix = "// ", pattern = "^(%s*)//%s*(.*)$" },
  c = { prefix = "// ", pattern = "^(%s*)//%s*(.*)$" },
  cpp = { prefix = "// ", pattern = "^(%s*)//%s*(.*)$" },
}

local function get_comment_info(line, ft)
  local cfg = comment_patterns[ft]
  if not cfg then return nil end
  local indent, content = line:match(cfg.pattern)
  if content ~= nil then
    return { indent = indent, prefix = cfg.prefix, content = content }
  end
  return nil
end

local function get_string_content(line)
  local before, quote, inner, after = line:match("^(.-)([\"'`])(.-)%2(.*)$")
  if inner and #inner >= 8 then
    return { before = before, quote = quote, inner = inner, after = after }
  end
  return nil
end

local function shorten_for_context(text, max_len)
  max_len = max_len or 50
  if #text <= max_len then return text end
  return text:sub(1, max_len - 2) .. ".."
end

function M.render(book_lines, opts)
  opts = opts or {}
  local source_lines = opts.source_lines
  local source_ft = opts.source_ft or "python"
  local source_path = opts.source_path or "source.py"
  local spacing = opts.spacing or 4

  if not source_lines or #source_lines == 0 then
    return {
      lines = { "// No source buffer captured" },
      filetype = source_ft,
      fake_path = source_path,
    }
  end

  local result = vim.deepcopy(source_lines)
  local book_cursor = 1
  local lines_since_last = 0

  for i, line in ipairs(result) do
    if book_cursor > #book_lines then break end
    if line == "" then goto continue end

    lines_since_last = lines_since_last + 1
    if lines_since_last < spacing then goto continue end

    local book_text = shorten_for_context(book_lines[book_cursor])
    book_cursor = book_cursor + 1
    lines_since_last = 0

    local comment = get_comment_info(line, source_ft)
    if comment and #comment.content >= 6 then
      result[i] = comment.indent .. comment.prefix .. book_text
      goto continue
    end

    local str = get_string_content(line)
    if str then
      result[i] = str.before .. str.quote .. book_text .. str.quote .. str.after
      goto continue
    end

    lines_since_last = spacing - 1

    ::continue::
  end

  return {
    lines = result,
    filetype = source_ft,
    fake_path = source_path,
  }
end

return M
