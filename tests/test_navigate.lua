local navigate = require("ghost-reader.reader.navigate")

describe("navigate", function()
  local book = {
    chapters = {
      { title = "One", lines = { "one", "two" } },
      { title = "Two", lines = { "three" } },
    },
  }

  local function segments(chapter_index, line_index)
    return (chapter_index == 1 and line_index == 1) and 2 or 1
  end

  it("moves through segments before the next logical line", function()
    local original = { chapter_index = 1, line_index = 1, segment_index = 1 }
    local next_pos = navigate.next_content(book, original, segments)

    assert.same({ chapter_index = 1, line_index = 1, segment_index = 2 }, next_pos)
    assert.same({ chapter_index = 1, line_index = 1, segment_index = 1 }, original)
  end)

  it("crosses chapter boundaries", function()
    local pos = { chapter_index = 1, line_index = 2, segment_index = 1 }
    local next_pos, moved = navigate.next_content(book, pos, segments)

    assert.is_true(moved)
    assert.same({ chapter_index = 2, line_index = 1, segment_index = 1 }, next_pos)
  end)

  it("moves to the previous segment before the previous line", function()
    local pos = { chapter_index = 1, line_index = 1, segment_index = 2 }
    local prev_pos, moved = navigate.prev_content(book, pos, segments)

    assert.is_true(moved)
    assert.same({ chapter_index = 1, line_index = 1, segment_index = 1 }, prev_pos)
  end)

  it("does not move before the first unit", function()
    local pos = { chapter_index = 1, line_index = 1, segment_index = 1 }
    local prev_pos, moved = navigate.prev_content(book, pos, segments)

    assert.is_false(moved)
    assert.same(pos, prev_pos)
  end)

  it("does not move after the last unit", function()
    local pos = { chapter_index = 2, line_index = 1, segment_index = 1 }
    local next_pos, moved = navigate.next_content(book, pos, segments)

    assert.is_false(moved)
    assert.same(pos, next_pos)
  end)

  it("moves three units as one page batch", function()
    local pos = { chapter_index = 1, line_index = 1, segment_index = 1 }
    local next_pos = navigate.next_page(book, pos, 3, segments)

    assert.same({ chapter_index = 2, line_index = 1, segment_index = 1 }, next_pos)
  end)

  it("moves one unit for a one-step page batch", function()
    local pos = { chapter_index = 1, line_index = 1, segment_index = 1 }
    local next_pos = navigate.next_page(book, pos, 1, segments)

    assert.same({ chapter_index = 1, line_index = 1, segment_index = 2 }, next_pos)
  end)

  it("resets line and segment on chapter jump", function()
    local pos = { chapter_index = 1, line_index = 2, segment_index = 2 }
    local next_pos = navigate.next_chapter(book, pos, segments)

    assert.same({ chapter_index = 2, line_index = 1, segment_index = 1 }, next_pos)
  end)

  it("normalizes invalid saved indices", function()
    local pos = navigate.normalize(book, {
      chapter_index = 0,
      line_index = -2,
      segment_index = 99,
    }, segments)

    assert.same({ chapter_index = 1, line_index = 1, segment_index = 2 }, pos)
  end)

  it("peeks without mutation", function()
    local pos = { chapter_index = 1, line_index = 1, segment_index = 1 }
    local peeked = navigate.peek(book, pos, 3, segments)

    assert.same(3, #peeked)
    assert.same({ chapter_index = 1, line_index = 1, segment_index = 1 }, peeked[1])
    assert.same({ chapter_index = 1, line_index = 1, segment_index = 2 }, peeked[2])
    assert.same({ chapter_index = 1, line_index = 2, segment_index = 1 }, peeked[3])
    assert.same({ chapter_index = 1, line_index = 1, segment_index = 1 }, pos)
  end)

  it("peeks backward in reading order without mutating the position", function()
    local pos = { chapter_index = 2, line_index = 1, segment_index = 1 }
    local peeked = navigate.peek_backward(book, pos, 3, segments)

    assert.same({
      { chapter_index = 1, line_index = 1, segment_index = 2 },
      { chapter_index = 1, line_index = 2, segment_index = 1 },
      { chapter_index = 2, line_index = 1, segment_index = 1 },
    }, peeked)
    assert.same({ chapter_index = 2, line_index = 1, segment_index = 1 }, pos)
  end)

  it("stops backward peeking at the first unit in reading order", function()
    local pos = { chapter_index = 2, line_index = 1, segment_index = 1 }
    local peeked = navigate.peek_backward(book, pos, 99, segments)

    assert.same({
      { chapter_index = 1, line_index = 1, segment_index = 1 },
      { chapter_index = 1, line_index = 1, segment_index = 2 },
      { chapter_index = 1, line_index = 2, segment_index = 1 },
      { chapter_index = 2, line_index = 1, segment_index = 1 },
    }, peeked)
    assert.same({ chapter_index = 2, line_index = 1, segment_index = 1 }, pos)
  end)
end)
