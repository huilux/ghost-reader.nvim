local M = {}
local utils = require("ghost-reader.utils")

function M._strip_html(html)
  if not html then return "" end
  local text = html
  text = text:gsub("<br%s*/?>", " ")
  text = text:gsub("</p>", "\n")
  text = text:gsub("</div>", "\n")
  text = text:gsub("</h%d>", "\n")
  text = text:gsub("<[^>]+>", "")
  text = text:gsub("&nbsp;", " ")
  text = text:gsub("&amp;", "&")
  text = text:gsub("&lt;", "<")
  text = text:gsub("&gt;", ">")
  text = text:gsub("&quot;", '"')
  text = text:gsub("&#%d+;", "")
  text = text:gsub("&%w+;", "")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

function M._html_to_lines(html)
  local stripped = M._strip_html(html)
  local lines = {}
  for line in stripped:gmatch("[^\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      table.insert(lines, line)
    end
  end
  return lines
end

function M.parse(path, opts)
  opts = opts or {}
  local cache_dir = opts.cache_dir or vim.fn.stdpath("cache") .. "/ghost-reader/"

  if not utils.command_exists("unzip") then
    return nil, "unzip command not found"
  end

  if not utils.file_exists(path) then
    return nil, "file not found: " .. path
  end

  local book_id = path:gsub("/", "_"):gsub("%.", "_")
  local extract_dir = cache_dir .. book_id .. "/"

  if vim.fn.isdirectory(extract_dir) == 0 then
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

  local container_path = extract_dir .. "META-INF/container.xml"
  local container_f = io.open(container_path, "r")
  if not container_f then
    return nil, "invalid epub: no container.xml"
  end
  local container = container_f:read("*a")
  container_f:close()

  local opf_path = container:match('full%-path="([^"]+)"')
    or container:match('full%-path=\'([^\']+)\'')
    or container:match('href="([^"]+)"')
  if not opf_path then
    return nil, "invalid epub: no opf reference"
  end

  local opf_full = extract_dir .. opf_path
  local opf_dir = opf_full:match("(.*/)")
  local opf_f = io.open(opf_full, "r")
  if not opf_f then
    return nil, "invalid epub: cannot read opf"
  end
  local opf = opf_f:read("*a")
  opf_f:close()

  local spine_ids = {}
  for idref in opf:gmatch('<itemref%s+idref="([^"]+)"') do
    table.insert(spine_ids, idref)
  end

  local items = {}
  for item_tag in opf:gmatch('<item[^>]+/?>') do
    local id = item_tag:match('id="([^"]+)"') or item_tag:match("id='([^']+)'")
    local href = item_tag:match('href="([^"]+)"') or item_tag:match("href='([^']+)'")
    local mt = item_tag:match('media%-type="([^"]+)"') or item_tag:match("media%-type='([^']+)'")
    if id and href and mt then
      items[id] = { href = href, media_type = mt }
    end
  end

  for _, idref in ipairs(spine_ids) do
    local item = items[idref]
    if item and item.media_type:find("html") then
      local chapter_path = opf_dir .. item.href
      local ch_f = io.open(chapter_path, "r")
      if ch_f then
        local html = ch_f:read("*a")
        ch_f:close()
        local lines = M._html_to_lines(html)
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
