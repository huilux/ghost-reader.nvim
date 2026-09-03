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

describe("notify", function()
  after_each(function()
    utils.set_silent(false)
  end)

  it("suppresses messages while silent is enabled", function()
    local messages = {}
    local original_notify = vim.notify
    vim.notify = function(msg) messages[#messages + 1] = msg end

    utils.set_silent(true)
    utils.notify("hidden message")
    assert.equal(0, #messages)

    utils.set_silent(false)
    utils.notify("visible message")
    assert.equal(1, #messages)
    assert.is_truthy(messages[1]:find("visible message", 1, true))

    vim.notify = original_notify
  end)
end)
