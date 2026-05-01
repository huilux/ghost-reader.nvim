--[[
  renderer/sparse_notes.lua - "稀疏注释"渲染器

  角色：将书籍文字伪装成代码中的 TODO/FIXME/NOTE 注释。
  策略：从用户当前打开的真实代码文件中取"骨架"，每隔 5-8 行插入一条伪装注释。
  这样屏幕上看起来就像一个正常的代码文件，只是注释比较多。

  本文件涉及的关键概念：
  - [Neovim API] nvim_list_bufs / nvim_buf_is_loaded / vim.bo[buf].buflisted
  - [Lua概念] table.sort 自定义比较器
  - [Lua概念] UTF-8 字节解码（手动实现）
  - [Neovim API] vim.fn.strwidth 获取字符显示宽度

  关联模块：被 renderer/init.lua 调用。
]]

local M = {}

-- 不同文件类型的注释语法
local comment_prefixes = {
  python = "# ",
  lua = "-- ",
  javascript = "// ",
  typescript = "// ",
  typescriptreact = "// ",
  go = "// ",
  rust = "// ",
  java = "// ",
  c = "// ",
  cpp = "// ",
  css = "/* ",
  html = "<!-- ",
  sh = "# ",
  zsh = "# ",
  bash = "# ",
  yaml = "# ",
  toml = "# ",
  json = "// ",
  markdown = "<!-- ",
}

-- 注释中使用的标签（让伪装更逼真）
local tags = { "TODO", "FIXME", "NOTE", "HACK", "XXX", "REFACTOR", "OPTIMIZE", "REVIEW" }

-- UTF-8 字符解码：获取字符串中指定位置的一个完整字符
-- [Lua概念] UTF-8 是变长编码，每个字符占 1-4 字节。
-- 通过第一个字节判断该字符占几个字节：
--   < 0x80 (128)     → 1 字节（ASCII 字符）
--   < 0xE0 (224)     → 2 字节
--   < 0xF0 (240)     → 3 字节（大部分中文字符）
--   >= 0xF0          → 4 字节（emoji 等）
-- [Lua概念] s:byte(i) 获取字符串第 i 个字节的数值（0-255）。
-- [Lua概念] s:sub(i, j) 截取子串（1-based，包含两端）。
local function utf8_next(s, i)
  if i > #s then return nil end
  local b = s:byte(i)
  local len
  if b < 0x80 then len = 1
  elseif b < 0xE0 then len = 2
  elseif b < 0xF0 then len = 3
  else len = 4
  end
  -- 返回：当前字符, 下一个字符的起始位置
  return s:sub(i, i + len - 1), i + len
end

-- 将一行书籍文字包装为注释
local function wrap_comment(text, prefix, tag, indent, max_width)
  -- 构建注释头：缩进 + 注释前缀 + 标签 + ": "
  local header = indent .. prefix .. tag .. ": "
  -- [Neovim API] vim.fn.strwidth(str) 返回字符串的显示宽度。
  -- 对于 ASCII 字符宽度为 1，对于 CJK 字符（中文、日文等）宽度为 2。
  -- 不能用 #str 因为 # 返回字节数（一个中文字 3 字节但显示宽度为 2）。
  local header_w = vim.fn.strwidth(header)
  local body_w = max_width - header_w
  if body_w < 20 then body_w = 20 end

  local text_w = vim.fn.strwidth(text)
  -- 如果一行放得下，直接返回
  if text_w <= body_w then
    return { header .. text }
  end

  -- 需要折行：逐字符检查宽度，超出 max_width 时换行
  local lines = {}
  local cur = header
  local cur_w = header_w
  local i = 1
  local first = true

  while i <= #text do
    local ch, next_i = utf8_next(text, i)
    local cw = vim.fn.strwidth(ch)
    if cur_w + cw > max_width then
      table.insert(lines, cur)
      -- 后续行不重复标签，只带缩进和注释前缀
      cur = indent .. prefix .. (first and "" or "  ")
      cur_w = vim.fn.strwidth(cur)
      first = false
    end
    cur = cur .. ch
    cur_w = cur_w + cw
    i = next_i
  end
  -- 添加最后一行（如果非空）
  if cur ~= indent .. prefix then
    table.insert(lines, cur)
  end

  return lines
end

-- 获取用户当前打开的所有真实代码 Buffer 的内容（作为骨架）
local function get_real_buffer_lines()
  -- [Neovim API] nvim_list_bufs() 返回所有 Buffer 编号的列表。
  local bufs = vim.api.nvim_list_bufs()
  local candidates = {}
  for _, buf in ipairs(bufs) do
    -- [Neovim API] nvim_buf_is_loaded(buf) 检查 Buffer 是否已加载（有内容在内存中）。
    -- vim.bo[buf].buflisted 检查 Buffer 是否在 Buffer 列表中可见（:ls 显示的）。
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
      local bt = vim.bo[buf].buftype
      -- 只选择普通 Buffer（buftype 为空或 nil），排除 nofile/scratch/terminal 等
      if bt == "" or bt == nil then
        local ft = vim.bo[buf].filetype
        -- 排除 git 相关的 Buffer（如 commit message、diff 等）
        if ft ~= "" and not ft:find("^git") then
          local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          -- 只选择内容足够多的 Buffer（至少 20 行）
          if #lines >= 20 then
            table.insert(candidates, {
              lines = lines,
              ft = ft,
              -- [Neovim API] nvim_buf_get_name(buf) 获取 Buffer 关联的文件路径
              path = vim.api.nvim_buf_get_name(buf),
            })
          end
        end
      end
    end
  end
  return candidates
end

-- 选择一个真实的 Buffer 作为代码骨架
local function pick_real_skeleton()
  local candidates = get_real_buffer_lines()
  if #candidates == 0 then return nil end
  -- [Lua概念] table.sort(t, comparator) 原地排序。
  -- comparator(a, b) 返回 true 表示 a 应该排在 b 前面。
  -- 这里按行数降序排列，优先选择大文件作为骨架。
  table.sort(candidates, function(a, b) return #a.lines > #b.lines end)
  -- 从前 3 个最大的文件中随机选一个
  local pick = candidates[math.random(math.min(3, #candidates))]
  return pick
end

-- 主渲染函数：将书籍行伪装为代码
function M.render(book_lines, opts)
  opts = opts or {}
  local lang = opts.lang or "python"

  -- 尝试用真实 Buffer 作为骨架，如果不行就用预设假代码
  local real = pick_real_skeleton()
  local skeleton, ft, path

  if real then
    skeleton = real.lines
    ft = real.ft
    path = real.path
  else
    local presets = require("ghost-reader.stealth.presets")
    local preset = presets.get(opts.preset or "random")
    skeleton = preset.lines
    ft = preset.filetype or lang
    path = preset.path
  end

  -- 获取该文件类型对应的注释前缀
  local prefix = comment_prefixes[ft] or comment_prefixes[lang] or "// "
  local skel_len = #skeleton

  -- 将骨架代码和书籍文字混合
  local result = {}
  local book_cursor = 1           -- 当前处理到第几行书籍文字
  local insert_interval = math.random(5, 8)  -- 每隔多少行骨架代码插入一条书籍注释
  local line_count = 0
  local tag_idx = math.random(1, #tags)
  local skel_idx = 1

  while book_cursor <= #book_lines do
    -- 从骨架代码中取一行
    local skel_line = skeleton[skel_idx]
    table.insert(result, skel_line)
    -- 骨架代码循环使用（如果书很长，骨架用完就从头开始）
    skel_idx = skel_idx % skel_len + 1
    line_count = line_count + 1

    if line_count >= insert_interval then
      -- 到了插入时机：取一行书籍文字，包装为注释
      local book_text = book_lines[book_cursor]
      local tag = tags[tag_idx]
      -- 轮换使用不同的标签
      tag_idx = tag_idx % #tags + 1
      -- 提取当前骨架行的缩进（让注释和骨架代码对齐）
      local indent = skel_line:match("^(%s+)") or ""
      local wrapped = wrap_comment(book_text, prefix, tag, indent, 80)
      for _, wl in ipairs(wrapped) do
        table.insert(result, wl)
      end
      book_cursor = book_cursor + 1
      line_count = 0
      -- 随机化下次插入的间隔
      insert_interval = math.random(5, 8)
    end
  end

  return {
    lines = result,        -- 渲染后的行数组
    filetype = ft,         -- 语法高亮用的文件类型
    fake_path = path or "source.py",  -- 假文件路径（显示在状态栏）
  }
end

return M
