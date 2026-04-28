local M = {}

local templates = {
  lua = {
    comment = "-- %s",
    string = '  local v%d = "%s"',
    func_open = "function M.%s()",
    func_close = "end",
    assign = "  local %s = %s",
    require = 'local utils = require("utils")',
    return_stmt = "  return %s",
    log = '  logger.debug("%s")',
  },
  python = {
    comment = "# %s",
    string = '  v%d = "%s"',
    func_open = "def %s():",
    func_close = "",
    assign = "  %s = %s",
    require = "from utils import helpers",
    return_stmt = "  return %s",
    log = '  logger.debug("%s")',
  },
  javascript = {
    comment = "// %s",
    string = '  const v%d = "%s";',
    func_open = "function %s() {",
    func_close = "}",
    assign = "  const %s = %s;",
    require = 'import { helpers } from "./utils";',
    return_stmt = "  return %s;",
    log = '  console.debug("%s");',
  },
  go = {
    comment = "// %s",
    string = '  v%d := "%s"',
    func_open = "func (m *Module) %s() error {",
    func_close = "}",
    assign = "  %s := %s",
    require = '"github.com/pkg/utils"',
    return_stmt = "  return %s",
    log = '  log.Debug().Msg("%s")',
  },
}

local function slugify(text)
  return text:lower():gsub("[^%w]+", "_"):gsub("^_", ""):gsub("_$", "")
end

local function shorten(text, max_len)
  max_len = max_len or 60
  if #text <= max_len then return text end
  return text:sub(1, max_len - 3) .. "..."
end

function M.render(lines, opts)
  opts = opts or {}
  local lang = opts.lang or "lua"
  local tpl = templates[lang] or templates.lua
  local result = {}
  local var_counter = 1

  table.insert(result, tpl.require)
  table.insert(result, "")

  for _, line in ipairs(lines) do
    if line == "" then
      table.insert(result, "")
    elseif #line <= 4 then
      table.insert(result, tpl.comment:format(line))
    else
      local short = shorten(line, 55)
      local choice = var_counter % 3
      if choice == 0 then
        table.insert(result, tpl.string:format(var_counter, short))
      elseif choice == 1 then
        table.insert(result, tpl.log:format(short))
      else
        local slug = slugify(line:sub(1, 15))
        table.insert(result, tpl.assign:format(slug .. var_counter, '"' .. short .. '"'))
      end
      var_counter = var_counter + 1
    end
  end

  table.insert(result, "")
  local fname = slugify(lines[1] and lines[1]:sub(1, 20) or "handler")
  table.insert(result, tpl.func_open:format(fname))
  table.insert(result, tpl.return_stmt:format("nil"))
  if tpl.func_close ~= "" then
    table.insert(result, tpl.func_close)
  end

  return {
    lines = result,
    filetype = lang,
    fake_path = opts.custom_path or ("src/" .. fname .. "." .. (lang == "javascript" and "js" or lang)),
  }
end

return M
