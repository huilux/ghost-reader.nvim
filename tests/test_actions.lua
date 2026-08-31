local helpers = require("tests.helpers")

describe("actions", function()
  before_each(function()
    helpers.reset_modules()
    _G.dispatched = nil
  end)

  it("dispatches a named action lazily", function()
    package.loaded["ghost-reader.session"] = { dispatch = function(name) _G.dispatched = name end }
    require("ghost-reader.actions").next_content()
    assert.equal("next_content", _G.dispatched)
  end)

  it("routes open to the public facade", function()
    local calls = 0
    package.loaded["ghost-reader"] = {
      select_book = function(mode)
        calls = calls + 1
        _G.dispatched = mode or "default"
      end,
    }
    require("ghost-reader.actions").open()
    assert.equal("default", _G.dispatched)
    assert.equal(1, calls)
  end)

  it("routes statusline open to the requested mode", function()
    package.loaded["ghost-reader"] = { select_book = function(mode) _G.dispatched = mode or "default" end }
    require("ghost-reader.actions").statusline()
    assert.equal("statusline", _G.dispatched)
  end)
end)
