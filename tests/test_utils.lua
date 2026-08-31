local utils = require("ghost-reader.utils")

describe("wrap_display", function()
  it("wraps Chinese text by display width", function()
    local text = "中文English混排"
    local segments = utils.wrap_display(text, 4)

    assert.is_truthy(#segments > 1)

    local rebuilt = table.concat(segments)
    assert.equal(text, rebuilt)

    for _, segment in ipairs(segments) do
      assert.is_true(vim.fn.strwidth(segment) <= 4)
    end
  end)
end)
