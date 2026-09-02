describe("renderer.init", function()
  it("exposes only mirror and statusline adapters", function()
    local renderer = require("ghost-reader.renderer")
    assert.is_nil(renderer.overlay)
    assert.is_table(renderer.mirror)
    assert.is_table(renderer.statusline)
    assert.is_function(renderer.create)
  end)

  it("raises the exact unknown renderer error", function()
    local renderer = require("ghost-reader.renderer")
    assert.has_error(function()
      renderer.get("bogus")
    end, "unknown reader view: bogus")
  end)

  it("uses mirror by default and propagates start failures", function()
    package.loaded["ghost-reader.renderer.mirror"] = nil
    local started = 0
    local render_calls = 0
    package.loaded["ghost-reader.renderer.mirror"] = {
      start = function() started = started + 1; return true end,
      render = function() render_calls = render_calls + 1; return true end,
      hide = function() return true end,
      restore = function() return true end,
      stop = function() return true end,
      page_size = function() return 1 end,
      segment_count = function() return 1 end,
      segment_text = function(_, text) return text end,
    }
    package.loaded["ghost-reader.renderer"] = nil
    local renderer = require("ghost-reader.renderer")
    local ctx = {
      target_buf = vim.api.nvim_get_current_buf(),
      target_win = vim.api.nvim_get_current_win(),
      config = { reader = { renderer = "mirror" } },
      view_state = {},
      mode = nil,
      view_name = nil,
    }
    local adapter = renderer.create(ctx)
    assert.equal("mirror", ctx.mode)
    assert.equal("mirror", ctx.view_name)
    assert.equal(1, started)
    assert.is_function(adapter.render)
    assert.is_true(adapter.render(ctx, { blocks = { { text = "x", active = true } } }))
    assert.equal(1, render_calls)

    package.loaded["ghost-reader.renderer.mirror"].start = function() return false end
    assert.is_nil(renderer.create(ctx, "mirror"))
  end)
end)
