# Task 11 Report

Documentation has been rewritten to match the final overlay-reader public surface.

What changed:

- Reworked `README.md` around the two user-facing modes:
  - overlay as the default real-buffer extmark mode
  - statusline as the one-line float
  - mirror as the automatic fallback
  - the final global mappings and shared control-layer mappings
  - `gh` hard hide and `<Esc>` control exit
  - the full `opts` schema
  - the six supported commands
  - Neovim 0.10+, Plenary for tests only, and `unzip` for EPUB support
  - the note that visual concealment is not a security boundary
- Replaced `docs/ghost-reader.txt` with help text that uses the final command names, controls, stealth behavior, configuration, and troubleshooting sections.
- Trimmed `docs/neovim-basics.md` and `docs/lua-concepts.md` so they no longer point at removed names or old tutorial examples.

Verification:

- `make test-runner-check`
- `make test-all`
- `git diff --check`
- Clean headless smoke test:
  - `env XDG_CACHE_HOME=/tmp/ghost-reader-final/cache XDG_DATA_HOME=/tmp/ghost-reader-final/data XDG_STATE_HOME=/tmp/ghost-reader-final/state nvim --clean --headless --cmd "set rtp^=/home/ming/workspace/Tools/hidden-reading/.worktrees/overlay-reader-refactor" -c "runtime plugin/ghost-reader.lua" -c "lua require('ghost-reader').setup({ stealth = { silent = true } })" -c "lua assert(vim.fn.exists(':GhostReaderHide') == 2)" -c "qa!"`

Follow-up fixes applied in this pass:

- Soft hide now calls the active renderer hide path so overlay extmarks are cleared without ending the session.
- Statusline autoplay now keys off the live session generation and uses the stored interval when it re-arms.
- The public facade now exposes the final helpers expected by the plan, including `select_book`, `toggle_controls`, and `toggle_hide`.
- Buffer-local keymap capture now ignores inherited global mappings, so user globals survive control-layer enter/leave.
- The obsolete `renderer.render` registry helper and `lua/ghost-reader/stealth/presets.lua` compatibility file were removed.

Final scan result:

- The stale-name scan from the brief is clean for shipped docs and plugin files.
- The remaining matches are in implementation files such as `lua/ghost-reader/session.lua`, `lua/ghost-reader/reader/progress.lua`, and `lua/ghost-reader/reader/navigate.lua`, which is expected because those are the current runtime symbols.

Notes:

- I preserved the pre-existing untracked generated artifacts and the `nvim.log` file.
