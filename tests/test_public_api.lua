local helpers = require("tests.helpers")

describe("public api", function()
  before_each(function()
    helpers.reset_modules()
  end)

  it("exports the final facade methods", function()
    local reader = require("ghost-reader")
    assert.is_function(reader.setup)
    assert.is_function(reader.open)
    assert.is_function(reader.open_statusline)
    assert.is_function(reader.close)
    assert.is_function(reader.toc)
    assert.is_function(reader.select_book)
    assert.is_function(reader.toggle_controls)
    assert.is_function(reader.toggle_hide)
  end)

  it("restores a hidden session on no-arg open", function()
    local calls = {}
    package.loaded["ghost-reader.session"] = {
      get = function()
        return { visibility = "SOFT_HIDDEN", controls = "INACTIVE" }
      end,
      restore = function()
        calls[#calls + 1] = "restore"
        return true
      end,
      toggle_controls = function()
        calls[#calls + 1] = "toggle_controls"
        return true
      end,
      configure = function() end,
      start = function()
        calls[#calls + 1] = "start"
        return true
      end,
      stop = function() end,
      toc = function() end,
      dispatch = function() end,
    }
    package.loaded["ghost-reader.history"] = { load = function() return {} end }
    package.loaded["ghost-reader.keymaps"] = { setup = function() end }
    package.loaded["ghost-reader.actions"] = {
      control = function() calls[#calls + 1] = "action_control" end,
      hide = function() calls[#calls + 1] = "action_hide" end,
    }

    local reader = require("ghost-reader")
    reader.setup()
    assert.is_true(reader.open())
    assert.same({ "restore" }, calls)
  end)

  it("reactivates inactive controls on no-arg open when the session is already visible", function()
    local calls = {}
    package.loaded["ghost-reader.session"] = {
      get = function()
        return { visibility = "VISIBLE", controls = "INACTIVE" }
      end,
      restore = function()
        calls[#calls + 1] = "restore"
        return true
      end,
      toggle_controls = function()
        calls[#calls + 1] = "toggle_controls"
        return true
      end,
      configure = function() end,
      start = function()
        calls[#calls + 1] = "start"
        return true
      end,
      stop = function() end,
      toc = function() end,
      dispatch = function() end,
    }
    package.loaded["ghost-reader.history"] = { load = function() return {} end }
    package.loaded["ghost-reader.keymaps"] = { setup = function() end }
    package.loaded["ghost-reader.actions"] = {}

    local reader = require("ghost-reader")
    reader.setup()
    assert.is_true(reader.open())
    assert.same({ "toggle_controls" }, calls)
  end)

  it("offers a mode picker for history and new-path selection but honors explicit statusline mode", function()
    local prompts = {}
    local opened = {}
    package.loaded["ghost-reader.session"] = {
      get = function() return nil end,
      restore = function() end,
      toggle_controls = function() end,
      configure = function() end,
      start = function(path, mode)
        opened[#opened + 1] = { path = path, mode = mode }
        return true
      end,
      stop = function() end,
      toc = function() end,
      dispatch = function() end,
    }
    package.loaded["ghost-reader.history"] = {
      load = function()
        return {
          { name = "Book A", path = "/tmp/book-a.txt" },
        }
      end,
    }
    package.loaded["ghost-reader.keymaps"] = { setup = function() end }
    package.loaded["ghost-reader.actions"] = {}

    local ui_select = vim.ui.select
    local ui_input = vim.ui.input
    vim.ui.select = function(items, opts, on_choice)
      prompts[#prompts + 1] = opts.prompt
      if opts.prompt == "Select mode:" then
        on_choice("overlay", 1)
      else
        on_choice(items[1], 1)
      end
    end
    vim.ui.input = function(opts, on_choice)
      prompts[#prompts + 1] = opts.prompt
      on_choice("/tmp/new-book.txt")
    end

    local reader = require("ghost-reader")
    reader.setup()
    reader.select_book()
    reader.select_book("statusline")

    vim.ui.select = ui_select
    vim.ui.input = ui_input

    assert.same({ "Select book:", "Select mode:", "Select book:" }, prompts)
    assert.same({
      { path = "/tmp/book-a.txt", mode = "overlay" },
      { path = "/tmp/book-a.txt", mode = "statusline" },
    }, opened)
  end)
end)
