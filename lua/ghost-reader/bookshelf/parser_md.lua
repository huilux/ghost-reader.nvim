local M = {}

function M.parse(path)
  local book = {
    format = "markdown",
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

  local has_headings = false
  for _, line in ipairs(all_lines) do
    if line:match("^#+%s") then
      has_headings = true
      break
    end
  end

  if not has_headings then
    local non_empty = {}
    for _, line in ipairs(all_lines) do
      if line ~= "" then table.insert(non_empty, line) end
    end
    table.insert(book.chapters, {
      title = vim.fn.fnamemodify(path, ":t"),
      lines = non_empty,
    })
    table.insert(book.toc, { title = book.chapters[1].title, level = 1, index = 1 })
    return book
  end

  local current_chapter = nil
  for _, line in ipairs(all_lines) do
    local level, title = line:match("^(#+)%s+(.+)$")
    if level then
      local heading_level = #level
      table.insert(book.toc, {
        title = title,
        level = heading_level,
        index = #book.chapters + 1,
      })
      if heading_level == 1 then
        current_chapter = {
          title = title,
          lines = {},
        }
        table.insert(book.chapters, current_chapter)
        -- Fix TOC index to point to actual chapter
        book.toc[#book.toc].index = #book.chapters
      elseif current_chapter then
        -- Sub-headings are content lines within the current chapter
        table.insert(current_chapter.lines, line)
      end
    elseif current_chapter and line ~= "" then
      table.insert(current_chapter.lines, line)
    end
  end

  return book
end

return M
