local function fresh_renderer()
  package.loaded["ghost-reader.renderer.statusline"] = nil
  return require("ghost-reader.renderer.statusline")
end

local function make_timer_stub()
  local stub = {
    starts = {},
    stopped = 0,
    closed = 0,
    callback = nil,
    interval = nil,
    repeat_interval = nil,
  }

  function stub:start(interval, repeat_interval, callback)
    self.interval = interval
    self.repeat_interval = repeat_interval
    self.callback = callback
    self.starts[#self.starts + 1] = { interval = interval, repeat_interval = repeat_interval }
  end

  function stub:stop()
    self.stopped = self.stopped + 1
  end

  function stub:close()
    self.closed = self.closed + 1
  end

  return stub
end

local function make_context()
  vim.cmd("enew!")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha", "beta", "gamma" })
  vim.bo[buf].buftype = ""

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(win, 12)

  return {
    target_buf = buf,
    target_win = win,
    generation = 7,
    config = {
      statusline = {
        interval = 25,
        autoplay = true,
        page_step = 2,
      },
    },
    view_state = {},
  }
end

describe("renderer.statusline", function()
  local original_new_timer

  before_each(function()
    original_new_timer = vim.uv.new_timer
  end)

  after_each(function()
    vim.uv.new_timer = original_new_timer
    package.loaded["ghost-reader.actions"] = nil
    package.loaded["ghost-reader.renderer.statusline"] = nil
  end)

  it("stores ownership under ctx.view_state.statusline", function()
    local renderer = fresh_renderer()
    local ctx = make_context()
    local timer = make_timer_stub()
    vim.uv.new_timer = function()
      return timer
    end

    assert.is_true(renderer.start(ctx))
    assert.is_table(ctx.view_state.statusline)
    assert.is_true(renderer.render(ctx, { blocks = { { text = "hello", active = true } } }))
    assert.is_table(ctx.view_state.statusline)
    assert.is_equal(ctx.generation, ctx.view_state.statusline.generation)
    assert.is_not_nil(ctx.view_state.statusline.win)
    assert.is_not_nil(ctx.view_state.statusline.buf)

    assert.is_true(renderer.stop(ctx))
    assert.is_nil(ctx.view_state.statusline.win)
    assert.is_nil(ctx.view_state.statusline.buf)
    assert.is_nil(ctx.view_state.statusline.timer)
  end)

  it("resizes the float and wraps by columns", function()
    local renderer = fresh_renderer()
    local ctx = make_context()
    local timer = make_timer_stub()
    vim.uv.new_timer = function()
      return timer
    end

    assert.is_true(renderer.render(ctx, { blocks = { { text = "hello", active = true } } }))
    local win = ctx.view_state.statusline.win
    local original = vim.api.nvim_win_get_width(win)
    vim.o.columns = vim.o.columns - 10

    assert.is_true(renderer.resize(ctx))
    assert.is_true(vim.api.nvim_win_is_valid(win))
    assert.is_truthy(vim.api.nvim_win_get_width(win) <= original)
    local width = math.max(20, vim.o.columns - 4)
    assert.is_equal(2, renderer.segment_count(ctx, string.rep("x", width * 2)))
    assert.is_equal("abc", renderer.segment_text(ctx, "abc", 1))
  end)

  it("clamps speed changes and toggles autoplay", function()
    local renderer = fresh_renderer()
    local ctx = make_context()
    local timer = make_timer_stub()
    vim.uv.new_timer = function()
      return timer
    end

    assert.is_true(renderer.start(ctx))
    ctx.view_state.statusline.interval = 200
    assert.is_equal(500, renderer.faster(ctx))
    assert.is_equal(1000, renderer.slower(ctx))
    ctx.view_state.statusline.interval = 14950
    assert.is_equal(15000, renderer.slower(ctx))
    assert.is_false(renderer.toggle_auto(ctx))
    assert.is_true(renderer.toggle_auto(ctx))
  end)

  it("does not rearm autoplay for stale generations or end of book", function()
    local renderer = fresh_renderer()
    local ctx = make_context()
    local timer = make_timer_stub()
    local dispatches = 0
    vim.uv.new_timer = function()
      return timer
    end
    package.loaded["ghost-reader.actions"] = {
      next_content = function()
        dispatches = dispatches + 1
        return true
      end,
    }

    assert.is_true(renderer.render(ctx, { blocks = { { text = "hello", active = true } } }))
    assert.is_not_nil(timer.callback)

    ctx.generation = ctx.generation + 1
    timer.callback()
    assert.is_truthy(vim.wait(100, function()
      return timer.closed == 1
    end, 5))
    assert.is_equal(0, dispatches)
    assert.is_equal(1, timer.stopped)
    assert.is_equal(1, timer.closed)

    ctx.generation = 7
    dispatches = 0
    timer = make_timer_stub()
    vim.uv.new_timer = function()
      return timer
    end
    package.loaded["ghost-reader.actions"] = {
      next_content = function()
        dispatches = dispatches + 1
        return false
      end,
    }

    assert.is_true(renderer.render(ctx, { blocks = { { text = "hello", active = true } } }))
    timer.callback()
    assert.is_truthy(vim.wait(100, function()
      return timer.closed == 1
    end, 5))
    assert.is_equal(1, dispatches)
    assert.is_equal(1, #timer.starts)
  end)

  it("reuses the float and hides, restores, and stops idempotently", function()
    local renderer = fresh_renderer()
    local ctx = make_context()
    local timer = make_timer_stub()
    vim.uv.new_timer = function()
      return timer
    end

    assert.is_true(renderer.render(ctx, { blocks = { { text = "hello", active = true } } }))
    local win = ctx.view_state.statusline.win
    assert.is_true(renderer.render(ctx, { blocks = { { text = "world", active = true } } }))
    assert.is_equal(win, ctx.view_state.statusline.win)

    assert.is_true(renderer.hide(ctx))
    assert.is_nil(ctx.view_state.statusline.win)
    assert.is_nil(ctx.view_state.statusline.buf)
    assert.is_nil(ctx.view_state.statusline.timer)
    assert.is_true(renderer.hide(ctx))

    assert.is_true(renderer.restore(ctx, { blocks = { { text = "again", active = true } } }))
    assert.is_not_nil(ctx.view_state.statusline.win)
    assert.is_true(renderer.stop(ctx))
    assert.is_true(renderer.stop(ctx))
  end)

  it("does not send routine notifications for title or path", function()
    local renderer = fresh_renderer()
    local ctx = make_context()
    local timer = make_timer_stub()
    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level, opts)
      notifications[#notifications + 1] = { msg = msg, level = level, opts = opts }
    end
    vim.uv.new_timer = function()
      return timer
    end

    local ok, err = pcall(function()
      assert.is_true(renderer.render(ctx, {
        title = "secret-title",
        path = "/tmp/secret-path.txt",
        blocks = { { text = "privacy line", active = true } },
      }))
      assert.is_true(renderer.stop(ctx))
    end)

    vim.notify = original_notify
    if not ok then error(err) end

    for _, entry in ipairs(notifications) do
      assert.is_nil(tostring(entry.msg):find("secret%-title", 1, true))
      assert.is_nil(tostring(entry.msg):find("secret%-path", 1, true))
    end
  end)
end)
