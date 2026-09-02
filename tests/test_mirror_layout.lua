local layout = require("ghost-reader.renderer.mirror_layout")

local opts = {
  region_lines = 50,
  max_blocks_per_region = 3,
  max_lines_per_block = 2,
  min_gap_lines = 6,
  max_total_blocks = 12,
  edge_padding = 2,
}

describe("mirror layout", function()
  it("spreads capped slots across the full buffer", function()
    local slots = layout.slots(500, opts)
    assert.equal(12, #slots)
    assert.is_true(slots[1].row <= 50)
    assert.is_true(slots[#slots].row > 450)

    local counts = {}
    for _, slot in ipairs(slots) do
      local region = math.floor((slot.row - 1) / 50) + 1
      counts[region] = (counts[region] or 0) + 1
      assert.is_true(counts[region] <= 3)
    end
  end)

  it("keeps configured space between block reservations", function()
    local slots = layout.slots(120, opts)
    for i = 2, #slots do
      local previous_end = slots[i - 1].row + slots[i - 1].height - 1
      assert.is_true(slots[i].row - previous_end > 6)
    end
  end)

  it("is deterministic and respects edge padding", function()
    local first = layout.slots(100, opts)
    local second = layout.slots(100, opts)
    assert.same(first, second)
    assert.is_true(first[1].row >= 3)
    assert.is_true(first[#first].row + first[#first].height - 1 <= 98)
  end)

  it("excludes reservations that cross folded rows", function()
    local slots = layout.slots(100, opts, function(row)
      return row >= 40 and row <= 70
    end)
    for _, slot in ipairs(slots) do
      for row = slot.row, slot.row + slot.height - 1 do
        assert.is_false(row >= 40 and row <= 70)
      end
    end
  end)

  it("relaxes spacing to provide one slot in a short buffer", function()
    local slots = layout.slots(2, opts)
    assert.equal(1, #slots)
    assert.equal(1, slots[1].row)
    assert.equal(2, slots[1].height)
  end)
end)
