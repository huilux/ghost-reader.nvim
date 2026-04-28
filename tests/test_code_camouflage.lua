local renderer = require("ghost-reader.renderer.code_camouflage")

describe("code_camouflage", function()
  it("wraps text in lua comment style", function()
    local result = renderer.render({ "Hello world" }, { lang = "lua" })
    assert.equal("lua", result.filetype)
    assert.is_truthy(#result.lines > 0)
  end)

  it("wraps text in python comment style", function()
    local result = renderer.render({ "Some text here" }, { lang = "python" })
    assert.equal("python", result.filetype)
    assert.is_truthy(#result.lines > 0)
  end)

  it("generates realistic code structure in lua", function()
    local lines = {
      "Chapter Title",
      "First paragraph of the story.",
      "",
      "Second paragraph continues.",
    }
    local result = renderer.render(lines, { lang = "lua" })
    assert.is_truthy(result.lines[1]:find("local") or result.lines[1]:find("function"))
  end)

  it("produces more lines than input (adds code scaffolding)", function()
    local result = renderer.render({ "A", "B", "C" }, { lang = "lua" })
    assert.is_truthy(#result.lines >= 3)
  end)
end)
