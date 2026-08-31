vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = vim.fn.getcwd() .. "/?.lua;" .. package.path

local plenary = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(plenary) ~= 1 then
  error("plenary.nvim not found at " .. plenary)
end

vim.opt.runtimepath:prepend(plenary)
