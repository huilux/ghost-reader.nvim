local M = {}

function M.get_page_lines(chapter_lines, offset, page_size)
  local lines = {}
  for i = offset + 1, math.min(offset + page_size, #chapter_lines) do
    table.insert(lines, chapter_lines[i])
  end
  return lines
end

function M.next_page(state, page_size)
  local new_offset = state.line_offset + page_size
  local chapter = state.book.chapters[state.chapter_index]
  if not chapter then return state, false end
  if new_offset >= #chapter.lines then
    return M.next_chapter(state)
  end
  state.line_offset = new_offset
  return state, true
end

function M.prev_page(state, page_size)
  local new_offset = state.line_offset - page_size
  if new_offset < 0 then
    return M.prev_chapter(state)
  end
  state.line_offset = new_offset
  return state, true
end

function M.next_chapter(state)
  if state.chapter_index >= #state.book.chapters then
    return state, false
  end
  state.chapter_index = state.chapter_index + 1
  state.line_offset = 0
  return state, true
end

function M.prev_chapter(state)
  if state.chapter_index <= 1 then
    return state, false
  end
  state.chapter_index = state.chapter_index - 1
  state.line_offset = 0
  return state, true
end

function M.go_to_chapter(state, chapter_index)
  if chapter_index < 1 or chapter_index > #state.book.chapters then
    return state, false
  end
  state.chapter_index = chapter_index
  state.line_offset = 0
  return state, true
end

return M
