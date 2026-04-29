local M = {}

local defaults = {
  boss_key = {
    keys = "<Esc><Esc>",
    use_current_buffer = true,
    preset = "random",
  },
  keymaps = {
    next_page = "J",
    prev_page = "K",
    next_chapter = "]c",
    prev_chapter = "[c",
    bookmark_add = "mb",
    bookmark_list = "gb",
    toc = "gt",
    progress = "gp",
    boss_key = "<Esc><Esc>",
  },
  statusline = {
    interval = 3000,
    mode = "auto",
  },
  cache_dir = nil,
  data_dir = nil,
}

local function deep_merge(base, override)
  local result = vim.deepcopy(base)
  for k, v in pairs(override or {}) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

function M.setup(user_config)
  local cfg = deep_merge(defaults, user_config)
  if not cfg.cache_dir then
    cfg.cache_dir = vim.fn.stdpath("cache") .. "/ghost-reader/"
  end
  if not cfg.data_dir then
    cfg.data_dir = vim.fn.stdpath("data") .. "/ghost-reader/"
  end
  return cfg
end

return M
