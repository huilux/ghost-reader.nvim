local helpers = require("tests.helpers")

describe("session", function()
  before_each(function()
    helpers.reset_modules()
  end)

  it("tracks lifecycle, visibility, and controls for an opened overlay session", function()
    local session = require("ghost-reader.session")
    local cfg = require("ghost-reader.config").setup()

    local buf = helpers.new_normal_buffer({ "one", "two", "three" })
    local book_path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "alpha", "", "beta" }, book_path)
    package.loaded["ghost-reader.bookshelf"] = {
      open = function()
        return {
          path = book_path,
          format = "txt",
          chapters = {
            { title = "Chapter 1", lines = { "alpha", "beta" } },
          },
          toc = { { title = "Chapter 1" } },
        }
      end,
    }

    assert.is_true(session.open({ path = book_path, renderer = "overlay", buffer = buf, config = cfg }))
    assert.equal("ACTIVE", session.state.lifecycle)
    assert.equal("VISIBLE", session.state.visibility)
    assert.equal("ACTIVE", session.state.controls)
    assert.equal("overlay", session.state.mode)

    assert.is_true(session.toggle_hide())
    assert.equal("HARD_HIDDEN", session.state.visibility)
    assert.equal("INACTIVE", session.state.controls)

    assert.is_true(session.restore())
    assert.equal("VISIBLE", session.state.visibility)
    assert.equal("ACTIVE", session.state.controls)

    assert.is_true(session.stop())
    assert.equal("IDLE", session.state.lifecycle)
  end)
end)
