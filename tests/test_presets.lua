local presets = require("ghost-reader.stealth.presets")

describe("presets", function()
  it("returns a preset by name", function()
    local p = presets.get("go_api")
    assert.equal("go", p.filetype)
    assert.is_truthy(#p.lines > 10)
    assert.is_truthy(p.path:find("%.go$"))
  end)

  it("returns random preset when name is 'random'", function()
    local p = presets.get("random")
    assert.is_truthy(p.filetype)
    assert.is_truthy(#p.lines > 0)
  end)

  it("lists all available presets", function()
    local names = presets.list()
    assert.is_truthy(#names >= 5)
  end)

  it("allows user to add custom preset", function()
    presets.add("my_preset", {
      lines = { "-- my code" },
      filetype = "lua",
      path = "my.lua",
    })
    local p = presets.get("my_preset")
    assert.equal("my_preset", p.name)
  end)
end)
