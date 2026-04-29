if vim.g.loaded_ghost_reader then
  return
end
vim.g.loaded_ghost_reader = true

vim.api.nvim_create_user_command("GhostReader", function(opts)
  local gr = require("ghost-reader")
  local path = opts.args
  if path ~= "" then
    gr.open(vim.fn.expand(path))
  else
    gr.select_book()
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

vim.api.nvim_create_user_command("GhostReaderStatusline", function(opts)
  local gr = require("ghost-reader")
  if not gr.config then gr.setup() end
  local path = opts.args
  if path ~= "" then
    require("ghost-reader.reader.statusline").start(vim.fn.expand(path), gr.config)
  else
    gr.select_book()
  end
end, { nargs = "?", complete = "file" })
