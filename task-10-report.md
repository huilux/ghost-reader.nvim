# Task 10 Report

Cutover completed for the public API and compatibility surface.

What changed:

- Removed the legacy runtime compatibility modules:
  - `lua/ghost-reader/renderer/sparse_notes.lua`
  - `lua/ghost-reader/stealth/boss_key.lua`
  - `lua/ghost-reader/stealth/init.lua`
  - `lua/ghost-reader/reader/init.lua`
  - `lua/ghost-reader/reader/statusline.lua`
- Simplified the public module to the final API:
  - `open()`
  - `open_statusline()`
  - `close()`
  - `toc()`
  - `setup()`
- Updated `plugin/ghost-reader.lua` to expose only the final commands:
  - `:GhostReader`
  - `:GhostReaderClose`
  - `:GhostReaderControl`
  - `:GhostReaderHide`
  - `:GhostReaderStatusline`
  - `:GhostReaderToc`
- Updated `lua/ghost-reader/actions.lua` and `lua/ghost-reader/keymaps.lua` to use the final entrypoints and `<Plug>` mappings only.
- Updated the user docs in `README.md` and `docs/ghost-reader.txt` to match the final names.
- Updated tests so they enforce the cutover instead of the removed compatibility helpers.

Verification:

- `make test-all`
- `rg -n 'GhostReaderBoss|GhostReaderRestore|stealth\\.boss_key|reader\\.state|reader_statusline\\.state|sparse_notes|boss_key|restore_keys|statusline\\.mode|<leader>go|<leader>gq|<leader>gt|<Esc><Esc>|\\]c|\\[c' lua plugin tests README.md docs/ghost-reader.txt`

Notes:

- The scan still reports the legacy key names inside `tests/test_config.lua`, but only as negative assertions that confirm the old configuration keys are rejected.
