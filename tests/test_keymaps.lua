local helpers = require("tests.helpers")
local config = require("ghost-reader.config")
local keymaps = require("ghost-reader.keymaps")

describe("keymaps", function()
  local function maparg_in_buf(buf, lhs)
    return vim.api.nvim_buf_call(buf, function()
      return vim.fn.maparg(lhs, "n", false, true)
    end)
  end

  before_each(function()
    helpers.reset_modules()
  end)

  it("restores a pre-existing buffer mapping", function()
    local buf = helpers.new_normal_buffer({ "one" })
    vim.keymap.set("n", "j", "gj", { buffer = buf, desc = "user j" })
    local session = { mode = "mirror" }
    keymaps.attach(session, config.setup(), buf)
    assert.equal("Ghost Reader: next content", maparg_in_buf(buf, "j").desc)
    keymaps.detach(session)
    local restored = maparg_in_buf(buf, "j")
    assert.equal("gj", restored.rhs)
    assert.equal("user j", restored.desc)
  end)

  it("deletes only plugin mappings when no previous map exists", function()
    local buf = helpers.new_normal_buffer({ "one" })
    local session = { mode = "mirror" }
    keymaps.attach(session, config.setup(), buf)
    keymaps.detach(session)
    assert.same({}, maparg_in_buf(buf, "j"))
  end)

  it("installs statusline extras only in statusline mode", function()
    local buf = helpers.new_normal_buffer({ "one" })
    local statusline_session = { mode = "statusline" }
    keymaps.attach(statusline_session, config.setup(), buf)
    assert.is_truthy(vim.fn.maparg("a", "n", false, true).rhs)
    assert.is_truthy(vim.fn.maparg("+", "n", false, true).rhs)
    assert.is_truthy(vim.fn.maparg("-", "n", false, true).rhs)
    keymaps.detach(statusline_session)

    local mirror_session = { mode = "mirror" }
    keymaps.attach(mirror_session, config.setup(), buf)
    assert.same({}, maparg_in_buf(buf, "a"))
    assert.same({}, maparg_in_buf(buf, "+"))
    assert.same({}, maparg_in_buf(buf, "-"))
    keymaps.detach(mirror_session)
  end)

  it("skips false bindings", function()
    local buf = helpers.new_normal_buffer({ "one" })
    local session = { mode = "mirror" }
    keymaps.attach(session, config.setup({ keymaps = { reader = { help = false } } }), buf)
    assert.same({}, maparg_in_buf(buf, "?"))
    keymaps.detach(session)
  end)

  it("leaves escape and the old control-layer hide key untouched", function()
    local buf = helpers.new_normal_buffer({ "one" })
    local session = { mode = "mirror" }
    keymaps.attach(session, config.setup(), buf)
    assert.same({}, maparg_in_buf(buf, "<Esc>"))
    assert.same({}, maparg_in_buf(buf, "gh"))
    keymaps.detach(session)
  end)

  it("cleans the captured buffer after current buffer changes", function()
    local first = helpers.new_normal_buffer({ "one" })
    local second = vim.api.nvim_create_buf(true, false)
    vim.keymap.set("n", "j", "gj", { buffer = first, desc = "user j" })
    local session = { mode = "mirror" }
    keymaps.attach(session, config.setup(), first)
    vim.api.nvim_set_current_buf(second)
    keymaps.detach(session)
    assert.equal("gj", maparg_in_buf(first, "j").rhs)
    assert.same({}, maparg_in_buf(second, "j"))
  end)

  it("detaches safely after the mapped buffer was deleted", function()
    local buf = helpers.new_normal_buffer({ "one" })
    local session = { mode = "mirror" }
    keymaps.attach(session, config.setup(), buf)
    vim.api.nvim_buf_delete(buf, { force = true })

    assert.has_no_error(function()
      keymaps.detach(session)
    end)
    assert.is_nil(session.reader_buf)
    assert.is_nil(session.reader_maps)
  end)

  it("sets global mappings idempotently", function()
    local cfg = config.setup()
    keymaps.setup(cfg)
    keymaps.setup(cfg)
    local expected = {
      { lhs = "<leader>rr", rhs = "<Plug>(GhostReaderOpen)" },
      { lhs = "<Esc><Esc>", rhs = "<Plug>(GhostReaderHide)" },
      { lhs = "<leader>rt", rhs = "<Plug>(GhostReaderToc)" },
      { lhs = "<leader>rq", rhs = "<Plug>(GhostReaderClose)" },
    }
    for _, item in ipairs(expected) do
      local resolved = item.lhs:gsub("<leader>", vim.g.mapleader or "\\")
      local map = vim.fn.maparg(resolved, "n", false, true)
      assert.equal(item.rhs, map.rhs)
    end
    assert.same({}, vim.fn.maparg((vim.g.mapleader or "\\") .. "rs", "n", false, true))
    assert.same({}, vim.fn.maparg((vim.g.mapleader or "\\") .. "rm", "n", false, true))
    assert.same({}, vim.fn.maparg((vim.g.mapleader or "\\") .. "rh", "n", false, true))
  end)

  it("removes a previously installed global mapping after its key changes", function()
    local old_cfg = config.setup({ keymaps = { global = { hide = "<leader>rh" } } })
    keymaps.setup(old_cfg)
    local old_lhs = (vim.g.mapleader or "\\") .. "rh"
    assert.equal("<Plug>(GhostReaderHide)", vim.fn.maparg(old_lhs, "n", false, true).rhs)

    keymaps.setup(config.setup())

    assert.same({}, vim.fn.maparg(old_lhs, "n", false, true))
    assert.equal("<Plug>(GhostReaderHide)", vim.fn.maparg("<Esc><Esc>", "n", false, true).rhs)
  end)

  it("removes a previously installed global mapping when it is disabled", function()
    keymaps.setup(config.setup())
    assert.equal("<Plug>(GhostReaderHide)", vim.fn.maparg("<Esc><Esc>", "n", false, true).rhs)

    local disabled_cfg = config.setup({ keymaps = { global = { hide = false } } })
    keymaps.setup(disabled_cfg)

    assert.same({}, vim.fn.maparg("<Esc><Esc>", "n", false, true))
  end)

  it("removes an installed leader mapping after mapleader changes", function()
    local original_leader = vim.g.mapleader
    vim.g.mapleader = ","
    keymaps.setup(config.setup({ keymaps = { global = { hide = "<leader>rh" } } }))
    assert.equal("<Plug>(GhostReaderHide)", vim.fn.maparg(",rh", "n", false, true).rhs)

    vim.g.mapleader = ";"
    keymaps.setup(config.setup())
    vim.g.mapleader = original_leader

    assert.same({}, vim.fn.maparg(",rh", "n", false, true))
  end)
end)
