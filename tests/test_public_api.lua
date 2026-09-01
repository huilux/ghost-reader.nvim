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
    assert.is_nil(reader.toggle_controls)
    assert.is_function(reader.toggle_hide)
  end)

  it("opens the book selector instead of restoring a hidden session", function()
    local calls = {}
    package.loaded["ghost-reader.session"] = {
      get = function()
        return { visibility = "SOFT_HIDDEN", controls = "INACTIVE" }
      end,
      restore = function()
        calls[#calls + 1] = "restore"
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
    package.loaded["ghost-reader.history"] = {
      load = function()
        calls[#calls + 1] = "load_history"
        return {}
      end,
    }
    package.loaded["ghost-reader.keymaps"] = { setup = function() end }
    package.loaded["ghost-reader.actions"] = {
      hide = function() calls[#calls + 1] = "action_hide" end,
    }

    local reader = require("ghost-reader")
    reader.setup()
    local original_select = vim.ui.select
    vim.ui.select = function(_, opts, on_choice)
      calls[#calls + 1] = opts.prompt
      on_choice(nil, nil)
    end
    reader.open()
    vim.ui.select = original_select
    assert.same({ "load_history", "Select book:" }, calls)
  end)

  it("temporarily hides a visible session while picking and restores it on cancel", function()
    local calls = {}
    local current = { visibility = "VISIBLE" }
    package.loaded["ghost-reader.session"] = {
      get = function()
        return current
      end,
      hide = function()
        current.visibility = "HARD_HIDDEN"
        calls[#calls + 1] = "hide"
        return true
      end,
      restore = function()
        current.visibility = "VISIBLE"
        calls[#calls + 1] = "restore"
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
    package.loaded["ghost-reader.history"] = {
      load = function()
        calls[#calls + 1] = "load_history"
        return {}
      end,
    }
    package.loaded["ghost-reader.keymaps"] = { setup = function() end }
    package.loaded["ghost-reader.actions"] = {}

    local reader = require("ghost-reader")
    reader.setup()
    local original_select = vim.ui.select
    vim.ui.select = function(_, opts, on_choice)
      calls[#calls + 1] = opts.prompt
      on_choice(nil, nil)
    end
    reader.open()
    vim.ui.select = original_select
    assert.same({ "hide", "load_history", "Select book:", "restore" }, calls)
  end)

  it("restores the previous visible session when a selected replacement fails", function()
    local calls = {}
    local current = { visibility = "VISIBLE" }
    package.loaded["ghost-reader.session"] = {
      get = function() return current end,
      hide = function()
        current.visibility = "HARD_HIDDEN"
        calls[#calls + 1] = "hide"
        return true
      end,
      restore = function()
        current.visibility = "VISIBLE"
        calls[#calls + 1] = "restore"
        return true
      end,
      configure = function() end,
      start = function()
        calls[#calls + 1] = "start"
        return false
      end,
      stop = function() end,
      toc = function() end,
      dispatch = function() end,
    }
    package.loaded["ghost-reader.history"] = {
      load = function()
        return { { name = "Book A", path = "/tmp/book-a.txt" } }
      end,
    }
    package.loaded["ghost-reader.keymaps"] = { setup = function() end }
    package.loaded["ghost-reader.actions"] = {}

    local original_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      on_choice(items[1], 1)
    end

    local reader = require("ghost-reader")
    reader.setup()
    reader.open()
    vim.ui.select = original_select

    assert.same({ "hide", "start", "restore" }, calls)
    assert.equal("VISIBLE", current.visibility)
  end)

  it("offers a mode picker for history and new-path selection but honors explicit statusline mode", function()
    local prompts = {}
    local opened = {}
    package.loaded["ghost-reader.session"] = {
      get = function() return nil end,
      restore = function() end,
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

  it("offers buffer mode alongside overlay and statusline", function()
    local modes = nil
    package.loaded["ghost-reader.session"] = {
      get = function() return nil end,
      configure = function() end,
      start = function() return true end,
      stop = function() end,
      toc = function() end,
      dispatch = function() end,
    }
    package.loaded["ghost-reader.history"] = {
      load = function() return { { name = "Book A", path = "/tmp/book-a.txt" } } end,
    }
    package.loaded["ghost-reader.keymaps"] = { setup = function() end }
    package.loaded["ghost-reader.actions"] = {}

    local original_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      if opts.prompt == "Select mode:" then
        modes = items
        on_choice("mirror", 3)
      else
        on_choice(items[1], 1)
      end
    end

    local reader = require("ghost-reader")
    reader.setup()
    reader.select_book()
    vim.ui.select = original_select

    assert.same({ "overlay", "statusline", "mirror" }, modes)
  end)

  it("asks for a mode for explicit paths while statusline direct-open bypasses the picker", function()
    local prompts = {}
    local opened = {}
    package.loaded["ghost-reader.session"] = {
      configure = function() end,
      start = function(path, mode)
        opened[#opened + 1] = { path = path, mode = mode }
        return true
      end,
      stop = function() end,
      toc = function() end,
      dispatch = function() end,
    }
    package.loaded["ghost-reader.history"] = { load = function() return {} end }
    package.loaded["ghost-reader.keymaps"] = { setup = function() end }
    package.loaded["ghost-reader.actions"] = {}

    local original_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      prompts[#prompts + 1] = opts.prompt
      on_choice(items[2], 2)
    end

    local reader = require("ghost-reader")
    reader.setup()
    reader.open("/tmp/direct.txt")
    reader.open_statusline("/tmp/statusline.txt")

    vim.ui.select = original_select
    assert.same({ "Select mode:" }, prompts)
    assert.same({
      { path = "/tmp/direct.txt", mode = "statusline" },
      { path = "/tmp/statusline.txt", mode = "statusline" },
    }, opened)
  end)

  it("runs the complete book and mode picker flow on every repeated open", function()
    local prompts = {}
    local opened = {}
    package.loaded["ghost-reader.session"] = {
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
        return { { name = "Book A", path = "/tmp/book-a.txt" } }
      end,
    }
    package.loaded["ghost-reader.keymaps"] = { setup = function() end }
    package.loaded["ghost-reader.actions"] = {}

    local mode = "overlay"
    local original_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      prompts[#prompts + 1] = opts.prompt
      if opts.prompt == "Select mode:" then
        on_choice(mode, mode == "overlay" and 1 or 2)
      else
        on_choice(items[1], 1)
      end
    end

    local reader = require("ghost-reader")
    reader.setup()
    reader.open()
    mode = "statusline"
    reader.open()

    vim.ui.select = original_select
    assert.same({ "Select book:", "Select mode:", "Select book:", "Select mode:" }, prompts)
    assert.same({
      { path = "/tmp/book-a.txt", mode = "overlay" },
      { path = "/tmp/book-a.txt", mode = "statusline" },
    }, opened)
  end)
end)
