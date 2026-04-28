local config = require("ghost-reader.config")

describe("config", function()
  it("returns defaults when no user config", function()
    local cfg = config.setup({})
    assert.equal("<Esc><Esc>", cfg.boss_key.keys)
    assert.equal(true, cfg.boss_key.use_current_buffer)
  end)

  it("merges user keymaps over defaults", function()
    local cfg = config.setup({
      keymaps = { next_page = "<C-f>", prev_page = "<C-b>" },
    })
    assert.equal("<C-f>", cfg.keymaps.next_page)
    assert.equal("<C-b>", cfg.keymaps.prev_page)
    assert.equal("]c", cfg.keymaps.next_chapter)
  end)

  it("deep merges boss_key table", function()
    local cfg = config.setup({
      boss_key = { keys = "<C-b><C-b>" },
    })
    assert.equal("<C-b><C-b>", cfg.boss_key.keys)
    assert.equal("<leader>gr", cfg.boss_key.restore_keys)
    assert.equal(true, cfg.boss_key.use_current_buffer)
  end)

  it("uses default dirs when nil", function()
    local cfg = config.setup({})
    assert.is_truthy(cfg.cache_dir:find("ghost%-reader"))
    assert.is_truthy(cfg.data_dir:find("ghost%-reader"))
  end)
end)
