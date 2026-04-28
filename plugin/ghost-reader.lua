if vim.g.loaded_ghost_reader then
  return
end
vim.g.loaded_ghost_reader = true

vim.api.nvim_create_user_command("GhostReader", function(opts)
  local path = opts.args
  if path == "" then
    vim.ui.input({ prompt = "Book path: " }, function(input)
      if input then require("ghost-reader").open(input) end
    end)
  else
    require("ghost-reader").open(vim.fn.expand(path))
  end
end, { nargs = "?", complete = "file" })

vim.api.nvim_create_user_command("GhostReaderClose", function()
  require("ghost-reader").close()
end, {})

vim.api.nvim_create_user_command("GhostReaderBoss", function()
  local stealth = require("ghost-reader.stealth")
  stealth.activate_boss_key()
end, {})

vim.api.nvim_create_user_command("GhostReaderRestore", function()
  local stealth = require("ghost-reader.stealth")
  stealth.deactivate_boss_key()
end, {})
