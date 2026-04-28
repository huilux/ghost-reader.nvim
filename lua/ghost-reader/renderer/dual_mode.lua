local M = {}

local function wrap_in_multiline_comment(lines, lang)
  local result = {}
  if lang == "python" then
    table.insert(result, '"""')
    for _, line in ipairs(lines) do
      table.insert(result, line)
    end
    table.insert(result, '"""')
  elseif lang == "lua" then
    table.insert(result, "--[[")
    for _, line in ipairs(lines) do
      table.insert(result, line)
    end
    table.insert(result, "]]")
  else
    table.insert(result, "/*")
    for _, line in ipairs(lines) do
      table.insert(result, " * " .. line)
    end
    table.insert(result, " */")
  end
  return result
end

local function wrap_in_string(lines, lang)
  local result = {}
  if lang == "python" then
    table.insert(result, 'payload = """')
    for _, line in ipairs(lines) do
      table.insert(result, line)
    end
    table.insert(result, '"""')
  elseif lang == "lua" then
    table.insert(result, "local payload = [[")
    for _, line in ipairs(lines) do
      table.insert(result, line)
    end
    table.insert(result, "]]")
  else
    table.insert(result, "const payload = `")
    for _, line in ipairs(lines) do
      table.insert(result, line)
    end
    table.insert(result, "`;")
  end
  return result
end

local code_skeletons = {
  python = {
    "import logging",
    "from dataclasses import dataclass",
    "",
    "logger = logging.getLogger(__name__)",
    "",
    "@dataclass",
    "class Config:",
    "    name: str = 'default'",
    "    timeout: int = 30",
    "",
  },
  lua = {
    'local M = {}',
    'local config = require("config")',
    "",
    "M._state = {}",
    "",
  },
  javascript = {
    'const { validate } = require("./validators");',
    'const config = require("../config");',
    "",
    "const defaults = { timeout: 30000, retries: 3 };",
    "",
  },
  go = {
    'package handler',
    "",
    'import "log"',
    'import "time"',
    "",
    "type Config struct {",
    "    Name    string",
    "    Timeout time.Duration",
    "}",
    "",
  },
}

function M.render(lines, opts)
  opts = opts or {}
  local lang = opts.lang or "lua"
  local skeleton = code_skeletons[lang] or code_skeletons.lua
  local use_comment = not opts.use_string

  local result = vim.deepcopy(skeleton)
  local wrapped
  if use_comment then
    wrapped = wrap_in_multiline_comment(lines, lang)
  else
    wrapped = wrap_in_string(lines, lang)
  end

  for _, line in ipairs(wrapped) do
    table.insert(result, line)
  end

  table.insert(result, "")

  return {
    lines = result,
    filetype = lang,
    fake_path = opts.custom_path or ("src/handler." .. (lang == "javascript" and "js" or lang)),
    hidden_in_comment = true,
  }
end

return M
