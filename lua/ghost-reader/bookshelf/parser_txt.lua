local M = {}

local default_chapter_patterns = {
  "^第[一二三四五六七八九十百千万%d]+[章节回卷部篇]",
  "^Chapter%s+%d+",
  "^CHAPTER%s+%d+",
  "^%d+%.",
}

local function match_chapter(line, patterns)
  for _, pat in ipairs(patterns) do
    if line:match(pat) then
      -- For CJK-style patterns, if the chapter marker is not followed by
      -- whitespace or end-of-line, apply heuristic to distinguish titles
      -- from sentences that merely reference a chapter.
      if pat:find("章节回卷部篇") then
        local after = line:match("^第[一二三四五六七八九十百千万%d]+[章节回卷部篇](.*)")
        if after and #after > 0 and not after:match("^[%s ]") then
          -- No space after marker: check if it looks like a sentence
          -- (contains sentence-ending punctuation mid-way or verb patterns)
          if after:match("[。！？，、；：]") then
            return false
          end
        end
      end
      return true
    end
  end
  return false
end

function M.parse(path, opts)
  opts = opts or {}
  local patterns = opts.chapter_patterns or default_chapter_patterns
  local lines_per_page = opts.lines_per_page or 50

  local book = {
    format = "txt",
    path = path,
    chapters = {},
    toc = {},
  }

  local f = io.open(path, "r")
  if not f then return book end

  local all_lines = {}
  for line in f:lines() do
    table.insert(all_lines, line)
  end
  f:close()

  local current_chapter = nil
  local has_chapters = false

  for _, line in ipairs(all_lines) do
    if match_chapter(line, patterns) then
      has_chapters = true
      current_chapter = {
        title = line,
        lines = {},
      }
      table.insert(book.chapters, current_chapter)
      table.insert(book.toc, { title = line, level = 1, index = #book.chapters })
    elseif current_chapter then
      if line ~= "" then
        table.insert(current_chapter.lines, line)
      end
    end
  end

  if not has_chapters then
    for i = 1, #all_lines, lines_per_page do
      local chunk = {}
      for j = i, math.min(i + lines_per_page - 1, #all_lines) do
        if all_lines[j] ~= "" then
          table.insert(chunk, all_lines[j])
        end
      end
      table.insert(book.chapters, {
        title = string.format("Page %d", math.floor(i / lines_per_page) + 1),
        lines = chunk,
      })
      table.insert(book.toc, {
        title = book.chapters[#book.chapters].title,
        level = 1,
        index = #book.chapters,
      })
    end
  end

  return book
end

return M
