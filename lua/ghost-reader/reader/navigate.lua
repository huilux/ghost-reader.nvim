local M = {}

local function copy(pos)
  return {
    chapter_index = pos.chapter_index,
    line_index = pos.line_index,
    segment_index = pos.segment_index,
  }
end

function M.get_page_lines(chapter_lines, offset, page_size)
  local lines = {}
  for i = (offset or 0) + 1, math.min((offset or 0) + (page_size or 0), #chapter_lines) do
    lines[#lines + 1] = chapter_lines[i]
  end
  return lines
end

local function chapter_count(book)
  return #(book and book.chapters or {})
end

local function line_count(book, chapter_index)
  local chapter = book.chapters[chapter_index]
  return chapter and #(chapter.lines or {}) or 0
end

local function segment_total(book, position, segment_count)
  local count = segment_count(position.chapter_index, position.line_index)
  return math.max(1, tonumber(count) or 1)
end

local function clamp(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

function M.normalize(book, position, segment_count)
  local chapters = chapter_count(book)
  if chapters == 0 then
    return copy({ chapter_index = 1, line_index = 1, segment_index = 1 })
  end

  local chapter_index = clamp(tonumber(position.chapter_index) or 1, 1, chapters)
  local lines = math.max(1, line_count(book, chapter_index))
  local line_index = clamp(tonumber(position.line_index) or 1, 1, lines)
  local segments = segment_total(book, { chapter_index = chapter_index, line_index = line_index }, segment_count)
  local segment_index = clamp(tonumber(position.segment_index) or 1, 1, segments)

  return {
    chapter_index = chapter_index,
    line_index = line_index,
    segment_index = segment_index,
  }
end

local function advance(book, position, segment_count, direction)
  local pos = M.normalize(book, position, segment_count)
  local chapters = chapter_count(book)
  if chapters == 0 then
    return copy(pos), false
  end

  local segments = segment_total(book, pos, segment_count)
  if direction > 0 then
    if pos.segment_index < segments then
      pos.segment_index = pos.segment_index + 1
      return pos, true
    end
    local lines = line_count(book, pos.chapter_index)
    if pos.line_index < lines then
      pos.line_index = pos.line_index + 1
      pos.segment_index = 1
      return pos, true
    end
    if pos.chapter_index < chapters then
      pos.chapter_index = pos.chapter_index + 1
      pos.line_index = 1
      pos.segment_index = 1
      return pos, true
    end
    return pos, false
  end

  if pos.segment_index > 1 then
    pos.segment_index = pos.segment_index - 1
    return pos, true
  end
  if pos.line_index > 1 then
    pos.line_index = pos.line_index - 1
    pos.segment_index = segment_total(book, pos, segment_count)
    return pos, true
  end
  if pos.chapter_index > 1 then
    pos.chapter_index = pos.chapter_index - 1
    pos.line_index = math.max(1, line_count(book, pos.chapter_index))
    pos.segment_index = segment_total(book, pos, segment_count)
    return pos, true
  end
  return pos, false
end

function M.next_content(book, position, segment_count)
  return advance(book, position, segment_count, 1)
end

function M.prev_content(book, position, segment_count)
  return advance(book, position, segment_count, -1)
end

function M.next_page(book, position, step, segment_count)
  local pos = copy(M.normalize(book, position, segment_count))
  local moved = false
  for _ = 1, math.max(0, tonumber(step) or 0) do
    local next_pos, did_move = M.next_content(book, pos, segment_count)
    pos = next_pos
    moved = moved or did_move
    if not did_move then
      break
    end
  end
  return pos, moved
end

function M.prev_page(book, position, step, segment_count)
  local pos = copy(M.normalize(book, position, segment_count))
  local moved = false
  for _ = 1, math.max(0, tonumber(step) or 0) do
    local prev_pos, did_move = M.prev_content(book, pos, segment_count)
    pos = prev_pos
    moved = moved or did_move
    if not did_move then
      break
    end
  end
  return pos, moved
end

function M.next_chapter(book, position, segment_count)
  local pos = M.normalize(book, position, segment_count)
  if pos.chapter_index >= chapter_count(book) then
    return pos, false
  end
  return {
    chapter_index = pos.chapter_index + 1,
    line_index = 1,
    segment_index = 1,
  }, true
end

function M.prev_chapter(book, position, segment_count)
  local pos = M.normalize(book, position, segment_count)
  if pos.chapter_index <= 1 then
    return pos, false
  end
  return {
    chapter_index = pos.chapter_index - 1,
    line_index = 1,
    segment_index = 1,
  }, true
end

function M.go_to_chapter(book, position, chapter_index, segment_count)
  local pos = M.normalize(book, position, segment_count)
  local target = clamp(tonumber(chapter_index) or 1, 1, chapter_count(book))
  if target == pos.chapter_index then
    return pos, false
  end
  return {
    chapter_index = target,
    line_index = 1,
    segment_index = 1,
  }, true
end

function M.peek(book, position, count, segment_count)
  local items = {}
  local pos = copy(M.normalize(book, position, segment_count))
  local limit = math.max(1, tonumber(count) or 1)
  items[1] = copy(pos)
  for i = 2, limit do
    local next_pos, moved = M.next_content(book, pos, segment_count)
    if not moved then
      break
    end
    pos = next_pos
    items[#items + 1] = copy(pos)
  end
  return items
end

return M
