describe("renderer.init", function()
  it("exposes overlay, mirror, and statusline adapters", function()
    local renderer = require("ghost-reader.renderer")
    assert.is_table(renderer.overlay)
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

  it("calls renderer.start and propagates failures", function()
    package.loaded["ghost-reader.renderer.overlay"] = nil
    package.loaded["ghost-reader.renderer.mirror"] = nil
    local started = 0
    local render_calls = 0
    package.loaded["ghost-reader.renderer.overlay"] = {
      supports = function() return true end,
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
      config = { reader = { mirror_fallback = true } },
      view_state = {},
      mode = "overlay",
      view_name = "overlay",
    }
    package.loaded["ghost-reader.renderer.mirror"] = {
      start = function() started = started + 10; return false end,
      render = function() render_calls = render_calls + 10; return true end,
      hide = function() return true end,
      restore = function() return true end,
      stop = function() return true end,
      page_size = function() return 1 end,
      segment_count = function() return 1 end,
      segment_text = function(_, text) return text end,
    }
    assert.is_truthy(renderer.create(ctx, "overlay"))
    assert.is_true(started > 0)
    local adapter = renderer.create(ctx, "overlay")
    assert.is_function(adapter.render)
    assert.is_true(adapter.render(ctx, { blocks = { { text = "x", active = true } } }))
    assert.is_true(render_calls > 0)
  end)
end)
