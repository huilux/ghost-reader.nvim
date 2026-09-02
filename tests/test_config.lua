local config = require("ghost-reader.config")

describe("config", function()
  it("returns the new defaults", function()
    local cfg = config.setup()
    assert.equal("mirror", cfg.reader.renderer)
    assert.is_nil(cfg.reader.visible_blocks)
    assert.is_nil(cfg.reader.mirror_fallback)
    assert.same({
      region_lines = 50,
      max_blocks_per_region = 3,
      max_lines_per_block = 2,
      min_gap_lines = 6,
      max_total_blocks = 12,
      edge_padding = 2,
    }, cfg.buffer.layout)
    assert.equal(1000, cfg.buffer.virt_text_priority)
    assert.is_nil(cfg.stealth.overlay)
    assert.equal("j", cfg.keymaps.reader.next_content)
    assert.equal("<Esc><Esc>", cfg.keymaps.global.hide)
    assert.is_false(cfg.keymaps.reader.hide)
    assert.is_nil(cfg.keymaps.global.control)
    assert.is_nil(cfg.keymaps.global.statusline)
    assert.is_truthy(cfg.paths.cache_dir:match("ghost%-reader/$"))
    assert.is_nil(cfg.cache_dir)
    assert.is_nil(cfg.data_dir)
  end)

  it("returns configurable buffer styles", function()
    local cfg = config.setup()
    assert.equal("light", cfg.buffer.style)
    assert.equal(6, cfg.buffer.light.visible_lines)
    assert.equal(2, cfg.buffer.light.max_consecutive_lines)
    assert.equal(3, cfg.buffer.strong.visible_lines)
    assert.equal(1, cfg.buffer.strong.max_consecutive_lines)

    local custom = config.setup({
      buffer = {
        style = "strong",
        light = { visible_lines = 8, max_consecutive_lines = 4 },
        strong = { visible_lines = 5, max_consecutive_lines = 2 },
      },
    })
    assert.equal("strong", custom.buffer.style)
    assert.equal(8, custom.buffer.light.visible_lines)
    assert.equal(4, custom.buffer.light.max_consecutive_lines)
    assert.equal(5, custom.buffer.strong.visible_lines)
    assert.equal(2, custom.buffer.strong.max_consecutive_lines)
  end)

  it("rejects legacy keys", function()
    assert.has_error(function() config.setup({ boss_key = {} }) end, "unknown config key: boss_key")
    assert.has_error(function() config.setup({ statusline = { mode = "manual" } }) end,
      "unknown config key: statusline.mode")
    assert.has_error(function() config.setup({ reader = { renderer = "overlay" } }) end)
    assert.has_error(function() config.setup({ reader = { visible_blocks = 3 } }) end,
      "unknown config key: reader.visible_blocks")
    assert.has_error(function() config.setup({ reader = { mirror_fallback = true } }) end,
      "unknown config key: reader.mirror_fallback")
    assert.is_nil(config.setup({ buffer = { preset = "random" } }).buffer.preset)
    assert.equal(50, config.setup({ buffer = { preset = "random" } }).buffer.layout.region_lines)
    assert.has_error(function() config.setup({ buffer = { mystery = true } }) end,
      "unknown config key: buffer.mystery")
    assert.has_error(function() config.setup({ stealth = { overlay = {} } }) end,
      "unknown config key: stealth.overlay")
  end)

  it("accepts false to disable a mapping", function()
    local cfg = config.setup({ keymaps = { reader = { help = false } } })
    assert.is_false(cfg.keymaps.reader.help)
  end)

  it("rejects removed control-layer configuration", function()
    assert.has_error(function()
      config.setup({ keymaps = { controls = { help = false } } })
    end, "unknown config key: keymaps.controls")
    assert.has_error(function()
      config.setup({ keymaps = { global = { control = "<leader>rm" } } })
    end, "unknown config key: keymaps.global.control")
    assert.has_error(function()
      config.setup({ keymaps = { global = { statusline = "<leader>rs" } } })
    end, "unknown config key: keymaps.global.statusline")
  end)

  it("rejects invalid values", function()
    assert.has_error(function() config.setup({ statusline = { interval = "fast" } }) end)
    assert.has_error(function() config.setup({ paths = { cache_dir = 42 } }) end)
    assert.has_error(function() config.setup({ buffer = { style = "medium" } }) end)
    assert.has_error(function() config.setup({ buffer = { light = { visible_lines = 0 } } }) end)
    assert.has_error(function()
      config.setup({ buffer = { strong = { visible_lines = 2, max_consecutive_lines = 3 } } })
    end)
  end)

  it("validates distributed mirror layout", function()
    assert.has_error(function()
      config.setup({ buffer = { layout = { region_lines = 0 } } })
    end, "invalid config value at buffer.layout.region_lines: expected positive integer")
    assert.has_error(function()
      config.setup({ buffer = { layout = { edge_padding = -1 } } })
    end, "invalid config value at buffer.layout.edge_padding: expected non-negative integer")
    assert.has_error(function()
      config.setup({ buffer = { layout = { region_lines = 4, max_lines_per_block = 2, edge_padding = 2 } } })
    end, "invalid config value at buffer.layout.max_lines_per_block: does not fit region_lines after edge_padding")
  end)

  it("normalizes explicit legacy style density when layout is absent", function()
    local cfg = config.setup({
      buffer = {
        style = "light",
        light = { visible_lines = 6, max_consecutive_lines = 2 },
      },
    })
    assert.equal(3, cfg.buffer.layout.max_blocks_per_region)
    assert.equal(2, cfg.buffer.layout.max_lines_per_block)
  end)

  it("rejects malformed section values", function()
    assert.has_error(function() config.setup({ reader = false }) end, "invalid config value at reader: expected table")
    assert.has_error(function() config.setup({ statusline = "fast" }) end, "invalid config value at statusline: expected table")
    assert.has_error(function() config.setup({ stealth = false }) end, "invalid config value at stealth: expected table")
    assert.has_error(function() config.setup({ paths = false }) end, "invalid config value at paths: expected table")
    assert.has_error(function() config.setup({ keymaps = false }) end, "invalid config value at keymaps: expected table")
  end)
end)
