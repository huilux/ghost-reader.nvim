local M = {}

local defaults = {
  reader = {
    renderer = "mirror",
  },
  buffer = {
    style = "light",
    light = {
      visible_lines = 6,
      max_consecutive_lines = 2,
    },
    strong = {
      visible_lines = 3,
      max_consecutive_lines = 1,
    },
    layout = {
      region_lines = 50,
      max_blocks_per_region = 3,
      max_lines_per_block = 2,
      min_gap_lines = 6,
      max_total_blocks = 12,
      edge_padding = 2,
    },
    virt_text_priority = 1000,
  },
  statusline = {
    interval = 3000,
    autoplay = true,
    page_step = 5,
  },
  stealth = {
    hide_on_focus_lost = true,
    silent = true,
  },
  paths = {},
  keymaps = {
    global = {
      open = "<leader>rr",
      hide = "<Esc><Esc>",
      toc = "<leader>rt",
      close = "<leader>rq",
    },
    reader = {
      next_content = "j",
      prev_content = "k",
      next_page = "<C-f>",
      prev_page = "<C-b>",
      next_chapter = "]]",
      prev_chapter = "[[",
      toc = "t",
      progress = "g%",
      hide = false,
      close = "q",
      help = "?",
    },
    statusline = {
      toggle_auto = "a",
      faster = "+",
      slower = "-",
    },
  },
}

local function is_positive_integer(value)
  return type(value) == "number" and value > 0 and value % 1 == 0
end

local function is_non_negative_integer(value)
  return type(value) == "number" and value >= 0 and value % 1 == 0
end

local function validate_value(value, expected, path)
  if expected == "string" then
    if type(value) ~= "string" then
      error("invalid config value at " .. path .. ": expected string")
    end
    return
  end

  if expected == "boolean" then
    if type(value) ~= "boolean" then
      error("invalid config value at " .. path .. ": expected boolean")
    end
    return
  end

  if expected == "positive_integer" then
    if not is_positive_integer(value) then
      error("invalid config value at " .. path .. ": expected positive integer")
    end
    return
  end

  if expected == "non_negative_integer" then
    if not is_non_negative_integer(value) then
      error("invalid config value at " .. path .. ": expected non-negative integer")
    end
    return
  end

  if expected == "renderer" then
    if value ~= "mirror" and value ~= "statusline" then
      error("invalid config value at " .. path .. ": expected mirror or statusline")
    end
    return
  end

  if expected == "buffer_style" then
    if value ~= "light" and value ~= "strong" then
      error("invalid config value at " .. path .. ": expected light or strong")
    end
    return
  end

  if expected == "mapping" then
    if not (type(value) == "string" or value == false) then
      error("invalid config value at " .. path .. ": expected string or false")
    end
    return
  end

  error("unknown validator for " .. path)
end

local function validate_known_keys(user_config, default_config, prefix)
  if type(user_config) ~= "table" then
    return
  end

  for key, value in pairs(user_config) do
    local current_path = prefix and (prefix .. "." .. key) or key
    local default_value = default_config[key]
    if default_value == nil and not (prefix == "paths" and (key == "cache_dir" or key == "data_dir")) then
      error("unknown config key: " .. current_path)
    end
    if type(value) == "table" and type(default_value) == "table" then
      validate_known_keys(value, default_value, current_path)
    end
  end
end

local function validate_schema(user_config)
  if type(user_config) ~= "table" then
    return
  end

  validate_known_keys(user_config, defaults, nil)

  if user_config.reader ~= nil and type(user_config.reader) ~= "table" then
    error("invalid config value at reader: expected table")
  end
  local reader = user_config.reader or {}
  if reader.renderer ~= nil then
    validate_value(reader.renderer, "renderer", "reader.renderer")
  end

  if user_config.buffer ~= nil and type(user_config.buffer) ~= "table" then
    error("invalid config value at buffer: expected table")
  end
  local buffer = user_config.buffer or {}
  if buffer.style ~= nil then
    validate_value(buffer.style, "buffer_style", "buffer.style")
  end
  for _, style in ipairs({ "light", "strong" }) do
    if buffer[style] ~= nil and type(buffer[style]) ~= "table" then
      error("invalid config value at buffer." .. style .. ": expected table")
    end
    local style_config = buffer[style] or {}
    if style_config.visible_lines ~= nil then
      validate_value(style_config.visible_lines, "positive_integer", "buffer." .. style .. ".visible_lines")
    end
    if style_config.max_consecutive_lines ~= nil then
      validate_value(style_config.max_consecutive_lines, "positive_integer", "buffer." .. style .. ".max_consecutive_lines")
    end
    if style_config.visible_lines ~= nil and style_config.max_consecutive_lines ~= nil
      and style_config.max_consecutive_lines > style_config.visible_lines then
      error("invalid config value at buffer." .. style .. ".max_consecutive_lines: cannot exceed visible_lines")
    end
  end

  if buffer.layout ~= nil and type(buffer.layout) ~= "table" then
    error("invalid config value at buffer.layout: expected table")
  end
  local layout = buffer.layout or {}
  for _, field in ipairs({ "region_lines", "max_blocks_per_region", "max_lines_per_block", "max_total_blocks" }) do
    if layout[field] ~= nil then
      validate_value(layout[field], "positive_integer", "buffer.layout." .. field)
    end
  end
  if layout.min_gap_lines ~= nil then
    validate_value(layout.min_gap_lines, "non_negative_integer", "buffer.layout.min_gap_lines")
  end
  if layout.edge_padding ~= nil then
    validate_value(layout.edge_padding, "non_negative_integer", "buffer.layout.edge_padding")
  end
  if layout.region_lines ~= nil and layout.max_lines_per_block ~= nil and layout.edge_padding ~= nil
    and layout.max_lines_per_block + (layout.edge_padding * 2) > layout.region_lines then
    error("invalid config value at buffer.layout.max_lines_per_block: does not fit region_lines after edge_padding")
  end
  if buffer.virt_text_priority ~= nil then
    validate_value(buffer.virt_text_priority, "positive_integer", "buffer.virt_text_priority")
  end

  local effective_layout = vim.tbl_deep_extend("force", vim.deepcopy(defaults.buffer.layout), layout)
  if effective_layout.max_lines_per_block + (effective_layout.edge_padding * 2) > effective_layout.region_lines then
    error("invalid config value at buffer.layout.max_lines_per_block: does not fit region_lines after edge_padding")
  end

  if user_config.statusline ~= nil and type(user_config.statusline) ~= "table" then
    error("invalid config value at statusline: expected table")
  end
  local statusline = user_config.statusline or {}
  if statusline.interval ~= nil then
    validate_value(statusline.interval, "positive_integer", "statusline.interval")
  end
  if statusline.autoplay ~= nil then
    validate_value(statusline.autoplay, "boolean", "statusline.autoplay")
  end
  if statusline.page_step ~= nil then
    validate_value(statusline.page_step, "positive_integer", "statusline.page_step")
  end

  if user_config.stealth ~= nil and type(user_config.stealth) ~= "table" then
    error("invalid config value at stealth: expected table")
  end
  local stealth = user_config.stealth or {}
  if stealth.hide_on_focus_lost ~= nil then
    validate_value(stealth.hide_on_focus_lost, "boolean", "stealth.hide_on_focus_lost")
  end
  if stealth.silent ~= nil then
    validate_value(stealth.silent, "boolean", "stealth.silent")
  end
  if user_config.paths ~= nil and type(user_config.paths) ~= "table" then
    error("invalid config value at paths: expected table")
  end
  local paths = user_config.paths or {}
  if paths.cache_dir ~= nil then
    validate_value(paths.cache_dir, "string", "paths.cache_dir")
  end
  if paths.data_dir ~= nil then
    validate_value(paths.data_dir, "string", "paths.data_dir")
  end

  if user_config.keymaps ~= nil and type(user_config.keymaps) ~= "table" then
    error("invalid config value at keymaps: expected table")
  end
  local keymaps = user_config.keymaps or {}
  for _, section in ipairs({ "global", "reader", "statusline" }) do
    if keymaps[section] ~= nil and type(keymaps[section]) ~= "table" then
      error("invalid config value at keymaps." .. section .. ": expected table")
    end
    local section_values = keymaps[section] or {}
    local defaults_values = defaults.keymaps[section] or {}
    for key, value in pairs(section_values) do
      if defaults_values[key] == nil then
        error("unknown config key: keymaps." .. section .. "." .. key)
      end
      validate_value(value, "mapping", "keymaps." .. section .. "." .. key)
    end
  end
end

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

local function normalize_user_config(user_config)
  local normalized = vim.deepcopy(user_config or {})
  local buffer = normalized.buffer
  if type(buffer) ~= "table" then
    return normalized
  end

  buffer.preset = nil
  if buffer.layout == nil and (buffer.style ~= nil or buffer.light ~= nil or buffer.strong ~= nil) then
    local style = buffer.style or defaults.buffer.style
    local legacy = vim.tbl_deep_extend(
      "force",
      vim.deepcopy(defaults.buffer[style] or defaults.buffer.light),
      type(buffer[style]) == "table" and buffer[style] or {}
    )
    buffer.layout = vim.deepcopy(defaults.buffer.layout)
    buffer.layout.max_lines_per_block = legacy.max_consecutive_lines
    buffer.layout.max_blocks_per_region = math.max(
      1,
      math.ceil(legacy.visible_lines / legacy.max_consecutive_lines)
    )
  end
  return normalized
end

function M.setup(user_config)
  local normalized = normalize_user_config(user_config)
  validate_schema(normalized)
  local cfg = deep_merge(defaults, normalized)
  cfg.paths.cache_dir = cfg.paths.cache_dir or (vim.fn.stdpath("cache") .. "/ghost-reader/")
  cfg.paths.data_dir = cfg.paths.data_dir or (vim.fn.stdpath("data") .. "/ghost-reader/")
  return cfg
end

return M
