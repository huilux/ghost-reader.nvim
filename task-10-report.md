# Task 10 Report

Cutover completed for the public API and compatibility surface, plus the follow-up fixes requested in rounds 1 and 2.

What changed:

- Removed the legacy runtime compatibility modules:
  - `lua/ghost-reader/renderer/sparse_notes.lua`
  - `lua/ghost-reader/stealth/boss_key.lua`
  - `lua/ghost-reader/stealth/init.lua`
  - `lua/ghost-reader/stealth/statusline.lua`
  - `lua/ghost-reader/reader/init.lua`
  - `lua/ghost-reader/reader/statusline.lua`
- Simplified the public module to the final API:
  - `open()`
  - `open_statusline()`
  - `close()`
  - `toc()`
  - `setup()`
- `setup()` now installs the final global `<Plug>` mappings via `keymaps.setup()`.
- `open()` now restores a hidden session when called without a path instead of always opening the picker.
- README control tables now use lowercase `j/k` everywhere the control layer is documented.
- Updated `plugin/ghost-reader.lua` to expose only the final commands:
  - `:GhostReader`
  - `:GhostReaderClose`
  - `:GhostReaderControl`
  - `:GhostReaderHide`
  - `:GhostReaderStatusline`
  - `:GhostReaderToc`
- Updated `lua/ghost-reader/actions.lua` and `lua/ghost-reader/keymaps.lua` to use the final entrypoints and `<Plug>` mappings only.
- Updated the user docs in `README.md`, `docs/ghost-reader.txt`, and `docs/lua-concepts.md` to match the final names.
- Updated tests so they enforce the cutover instead of the removed compatibility helpers.

Verification:

- `make test-all`
- `rg -n 'GhostReaderBoss|GhostReaderRestore|stealth\\.boss_key|reader\\.state|reader_statusline\\.state|sparse_notes|boss_key|restore_keys|statusline\\.mode|<leader>go|<leader>gq|<leader>gt|<Esc><Esc>|\\]c|\\[c' lua plugin tests README.md docs/ghost-reader.txt docs/lua-concepts.md`

Notes:

- The scan still reports the legacy key names inside `tests/test_config.lua`, but only as negative assertions that confirm the old configuration keys are rejected.
- The scan no longer reports stale shipped control examples; the remaining hits are intentional references in tests and internal readers/navigate helpers.
