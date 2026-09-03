--[[
  bookshelf/parser_epub.lua - EPUB 电子书解析器

  角色：解析 EPUB 文件（本质是 ZIP 压缩包，内含 HTML/XHTML 文件）。
  解压后解析 XML 元数据（container.xml → content.opf），按阅读顺序提取章节文本。

  本文件涉及的关键概念：
  - [Neovim API] vim.system() 运行外部命令
  - [Neovim API] vim.fn.isdirectory 检查目录
  - [Lua概念] string.gsub 全局替换
  - [Lua概念] string.gmatch 迭代匹配
  - [Lua概念] 字符串方法链（连续调用 gsub）

  关联模块：被 bookshelf/init.lua 调用。
]]

local M = {}
local utils = require("ghost-reader.utils")

local function file_status(path)
  return vim.uv.fs_stat(path)
end

-- 将 HTML 转换为纯文本：移除所有 HTML 标签和实体
function M._strip_html(html)
  if not html then return "" end
  local text = html
  -- [Lua概念] text:gsub(pattern, replacement) 全局替换。
  -- 返回两个值：替换后的字符串和替换次数（这里只取第一个返回值）。
  --
  -- "<br%s*/?>" 解读：
  --   %s* = 零个或多个空白
  --   /?  = 可选的斜杠
  --   匹配 <br>、<br/>、<br /> 等变体
  text = text:gsub("<br%s*/?>", " ")
  -- 将 </p>、</div>、</h1> 等闭合标签替换为换行符
  text = text:gsub("</p>", "\n")
  text = text:gsub("</div>", "\n")
  -- [Lua概念] "%d" 在模式中匹配数字。"h%d" 匹配 h1、h2、h3 等。
  text = text:gsub("</h%d>", "\n")
  -- 移除所有剩余的 HTML 标签：<任意内容>
  text = text:gsub("<[^>]+>", "")
  -- 替换 HTML 实体为对应字符
  text = text:gsub("&nbsp;", " ")
  text = text:gsub("&amp;", "&")
  text = text:gsub("&lt;", "<")
  text = text:gsub("&gt;", ">")
  text = text:gsub("&quot;", '"')
  -- [Lua概念] "&#%d+;" 匹配数字实体引用（如 &#123;）
  text = text:gsub("&#%d+;", "")
  -- [Lua概念] "&%w+;" 匹配命名字体引用（如 &mdash;）
  text = text:gsub("&%w+;", "")
  -- 去除首尾空白：^%s+ 匹配开头空白，%s+$ 匹配末尾空白
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

-- 将 HTML 转为行数组
function M._html_to_lines(html)
  local body = html and html:match("<[Bb][Oo][Dd][Yy][^>]*>(.-)</[Bb][Oo][Dd][Yy]%s*>")
  local stripped = M._strip_html(body or html)
  local lines = {}
  -- [Lua概念] str:gmatch(pattern) 返回一个迭代器，每次产生一个匹配。
  -- "[^\n]+" 匹配"不是换行符的连续字符"，即按换行分割。
  for raw_line in stripped:gmatch("[^\n]+") do
    -- 链式调用 :gsub 去除每行首尾空白
    local line = raw_line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      table.insert(lines, line)
    end
  end
  return lines
end

function M.parse(path, opts)
  opts = opts or {}
  local cache_dir = opts.cache_dir or (opts.paths and opts.paths.cache_dir) or (vim.fn.stdpath("cache") .. "/ghost-reader/")

  -- 检查系统是否安装了 unzip 命令
  if not utils.command_exists("unzip") then
    return nil, "unzip command not found"
  end

  local stat = file_status(path)
  if not stat then
    return nil, "file not found: " .. path
  end
  if stat.type ~= "file" then
    return nil, "file unreadable: " .. path
  end

  -- 将文件路径转为安全的目录名（替换 / 和 . 为 _）
  local book_id = path:gsub("/", "_"):gsub("%.", "_")
  local extract_dir = cache_dir .. book_id .. "/"

  -- 如果还没解压过，就解压 EPUB 文件
  if vim.fn.isdirectory(extract_dir) == 0 then
    -- [Neovim API] vim.system({ cmd, args }) 是 Neovim 0.10+ 提供的运行外部命令的 API。
    -- :wait() 同步等待命令完成，返回 { code, stdout, stderr }。
    -- code = 0 表示成功，非 0 表示失败。
    local result = vim.system({ "unzip", "-o", path, "-d", extract_dir }):wait()
    if result.code ~= 0 then
      return nil, "unzip failed: " .. (result.stderr or "")
    end
  end

  local book = {
    format = "epub",
    path = path,
    chapters = {},
    toc = {},
  }

  -- EPUB 的目录结构是标准的：
  --   META-INF/container.xml → 指向 content.opf 文件
  --   content.opf → 定义章节列表（spine）和文件路径（manifest）
  local container_path = extract_dir .. "META-INF/container.xml"
  local container_f = io.open(container_path, "r")
  if not container_f then
    return nil, "invalid epub: no container.xml"
  end
  local container = container_f:read("*a")
  container_f:close()

  -- 从 container.xml 中找到 OPF 文件路径
  -- [Lua概念] pattern 中的 %- 转义连字符（- 在模式中是特殊字符"最短匹配"，需转义）。
  -- 'full%-path="([^"]+)"' 匹配 full-path="xxx" 并捕获 xxx 的内容。
  local opf_path = container:match('full%-path="([^"]+)"')
    or container:match('full%-path=\'([^\']+)\'')
    or container:match('href="([^"]+)"')
  if not opf_path then
    return nil, "invalid epub: no opf reference"
  end

  local opf_full = extract_dir .. opf_path
  -- [Lua概念] "(.*/)" 匹配路径中的目录部分（最后一个 / 之前的内容，含 /）。
  local opf_dir = opf_full:match("(.*/)")
  local opf_f = io.open(opf_full, "r")
  if not opf_f then
    return nil, "invalid epub: cannot read opf"
  end
  local opf = opf_f:read("*a")
  opf_f:close()

  -- 提取 spine（阅读顺序）：按 idref 列出章节的阅读顺序
  local spine_ids = {}
  for idref in opf:gmatch('<itemref%s+idref="([^"]+)"') do
    table.insert(spine_ids, idref)
  end

  -- 提取 manifest（文件清单）：id → { href, media_type }
  local items = {}
  for item_tag in opf:gmatch('<item[^>]+/?>') do
    local id = item_tag:match('id="([^"]+)"') or item_tag:match("id='([^']+)'")
    local href = item_tag:match('href="([^"]+)"') or item_tag:match("href='([^']+)'")
    local mt = item_tag:match('media%-type="([^"]+)"') or item_tag:match("media%-type='([^']+)'")
    if id and href and mt then
      items[id] = { href = href, media_type = mt }
    end
  end

  -- 按 spine 顺序读取每个章节
  for _, idref in ipairs(spine_ids) do
    local item = items[idref]
    if item and item.media_type:find("html") then
      local chapter_path = opf_dir .. item.href
      local ch_f = io.open(chapter_path, "r")
      if ch_f then
        local html = ch_f:read("*a")
        ch_f:close()
        local lines = M._html_to_lines(html)
        -- 从文件路径中提取章节标题：去掉目录和扩展名，将 - 和 _ 替换为空格
        local title = item.href:match("([^/]+)%."):gsub("[%-%_]", " ")
        table.insert(book.chapters, {
          title = title,
          lines = lines,
        })
        table.insert(book.toc, { title = title, level = 1, index = #book.chapters })
      end
    end
  end

  return book
end

return M
