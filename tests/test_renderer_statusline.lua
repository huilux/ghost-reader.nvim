local statusline = require("ghost-reader.renderer.statusline")

local function make_context()
  vim.cmd("enew!")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha", "beta", "gamma" })
  vim.bo[buf].buftype = ""
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(win, 12)

  return {
    target_buf = buf,
    target_win = win,
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
  it("reuses one float while updating, hiding, restoring, and stopping", function()
    local ctx = make_context()

    assert.is_true(statusline.start(ctx))
    assert.is_true(statusline.render(ctx, {
      blocks = {
        { text = "first line", active = true },
        { text = "second line", active = false },
      },
    }))

    local first = assert(statusline.state).win
    assert.is_true(vim.api.nvim_win_is_valid(first))

    assert.is_true(statusline.render(ctx, {
      blocks = {
        { text = "updated line", active = true },
      },
    }))
    assert.equal(first, statusline.state.win)

    assert.is_true(statusline.hide(ctx))
    assert.is_false(vim.api.nvim_win_is_valid(first))

    assert.is_true(statusline.restore(ctx, {
      blocks = {
        { text = "restored line", active = true },
      },
    }))
    assert.is_true(vim.api.nvim_win_is_valid(assert(statusline.state).win))

    assert.is_true(statusline.stop(ctx))
    assert.is_nil(statusline.state)
  end)

  it("cleans up when the timer expires", function()
    local ctx = make_context()

    assert.is_true(statusline.start(ctx))
    assert.is_true(statusline.render(ctx, {
      blocks = {
        { text = "timer line", active = true },
      },
    }))

    assert.is_truthy(vim.wait(300, function()
      return not statusline.state or not statusline.state.timer or not statusline.state.win
    end, 10))
    assert.is_nil(statusline.state)
  end)

  it("does not send routine notifications for title or path", function()
    local ctx = make_context()
    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level, opts)
      notifications[#notifications + 1] = { msg = msg, level = level, opts = opts }
    end

    local ok, err = pcall(function()
      assert.is_true(statusline.start(ctx))
      assert.is_true(statusline.render(ctx, {
        title = "secret-title",
        path = "/tmp/secret-path.txt",
        blocks = { { text = "privacy line", active = true } },
      }))
      assert.is_true(statusline.hide(ctx))
      assert.is_true(statusline.restore(ctx, {
        title = "secret-title",
        path = "/tmp/secret-path.txt",
        blocks = { { text = "privacy line", active = true } },
      }))
      assert.is_true(statusline.stop(ctx))
    end)

    vim.notify = original_notify
    if not ok then error(err) end

    for _, entry in ipairs(notifications) do
      assert.is.falsy(tostring(entry.msg):find("secret%-title", 1, true))
      assert.is.falsy(tostring(entry.msg):find("secret%-path", 1, true))
    end
  end)
end)
