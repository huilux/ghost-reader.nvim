local M = {}

function M.new(book_id, data_path)
  local bm = {
    book_id = book_id,
    data_path = data_path,
    bookmarks = {},
  }

  function bm:add(line, note)
    table.insert(self.bookmarks, { line = line, note = note or "" })
  end

  function bm:remove(line)
    for i, b in ipairs(self.bookmarks) do
      if b.line == line then
        table.remove(self.bookmarks, i)
        return true
      end
    end
    return false
  end

  function bm:list()
    return self.bookmarks
  end

  function bm:save()
    if not self.data_path then return end
    local f = io.open(self.data_path, "w")
    if not f then return end
    f:write(vim.json.encode({ bookmarks = self.bookmarks }))
    f:close()
  end

  function bm:load()
    if not self.data_path then return end
    local f = io.open(self.data_path, "r")
    if not f then return end
    local data = f:read("*a")
    f:close()
    local ok, decoded = pcall(vim.json.decode, data)
    if ok and decoded.bookmarks then
      self.bookmarks = decoded.bookmarks
    end
  end

  return bm
end

return M
