local M = {}

local function dispatch(name)
  return require("ghost-reader.session").dispatch(name)
end

function M.open()
  return require("ghost-reader").open()
end

function M.statusline()
  return require("ghost-reader").open_statusline()
end

function M.control()
  return require("ghost-reader").toggle_controls()
end

function M.hide()
  return require("ghost-reader").toggle_hide()
end

function M.toc()
  return require("ghost-reader.session").toc()
end

function M.close()
  return require("ghost-reader.session").stop()
end

function M.next_content() return dispatch("next_content") end
function M.prev_content() return dispatch("prev_content") end
function M.next_page() return dispatch("next_page") end
function M.prev_page() return dispatch("prev_page") end
function M.next_chapter() return dispatch("next_chapter") end
function M.prev_chapter() return dispatch("prev_chapter") end
function M.progress() return dispatch("progress") end
function M.help() return dispatch("help") end
function M.exit_controls() return dispatch("exit_controls") end
function M.toggle_auto() return dispatch("toggle_auto") end
function M.faster() return dispatch("faster") end
function M.slower() return dispatch("slower") end

return M
