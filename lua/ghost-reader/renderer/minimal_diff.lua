local M = {}

local fake_extensions = {
  python = { "py", dir = "src/api/" },
  lua = { "lua", dir = "lua/config/" },
  javascript = { "js", dir = "src/utils/" },
  go = { "go", dir = "internal/handler/" },
  typescript = { "ts", dir = "src/services/" },
}

function M.render(lines, opts)
  opts = opts or {}
  local lang = opts.lang or "python"
  local fake = fake_extensions[lang] or fake_extensions.python

  local ext = fake[1]
  local dir = fake.dir
  local filename = opts.custom_path or (dir .. "module_" .. os.date("%m%d") .. "." .. ext)

  return {
    lines = lines,
    filetype = lang,
    fake_path = filename,
  }
end

return M
