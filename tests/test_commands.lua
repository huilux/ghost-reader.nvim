local helpers = require("tests.helpers")

describe("commands", function()
  before_each(function()
    helpers.reset_modules()
  end)

  it("registers only the final command surface", function()
    local commands = {}
    local original_create = vim.api.nvim_create_user_command
    vim.api.nvim_create_user_command = function(name, fn, opts)
      commands[#commands + 1] = name
    end

    package.loaded["ghost-reader"] = {
      setup = function() end,
      open = function() end,
      open_statusline = function() end,
      close = function() end,
      toc = function() end,
    }
    package.loaded["ghost-reader.actions"] = {
      control = function() end,
      hide = function() end,
    }

    dofile("plugin/ghost-reader.lua")

    vim.api.nvim_create_user_command = original_create

    table.sort(commands)
    assert.same({
      "GhostReader",
      "GhostReaderClose",
      "GhostReaderControl",
      "GhostReaderHide",
      "GhostReaderStatusline",
      "GhostReaderToc",
    }, commands)
  end)
end)
