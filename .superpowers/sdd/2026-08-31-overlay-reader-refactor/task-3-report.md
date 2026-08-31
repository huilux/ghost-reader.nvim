# Task 3 Report

Implemented the bookshelf stateless/contract refactor from the Task 3 brief.

What changed:

- `bookshelf.open(path, parser_opts)` now behaves as a stateless entry point.
- Removed dispatcher module state (`current_book`, `get_current()`, `close()`).
- Added final-book validation so missing/empty content returns `nil, "book has no readable content: ..."` instead of a bogus book.
- Parsers now return `nil, "file not found: ..."` when the source file cannot be opened.
- Markdown parsing now creates an implicit chapter for H2-only or content-first input and keeps TOC indices within chapter bounds.
- EPUB now honors configured `paths.cache_dir` when provided.

Tests added/updated:

- Added `tests/test_bookshelf.lua` for missing-file and empty-book contracts.
- Added `tests/fixtures/heading_only_h2.md`.
- Updated parser tests to cover the new Markdown TOC and missing-file behavior.

Verification:

- `make test FILE=test_bookshelf.lua`
- `make test FILE=test_parser_txt.lua`
- `make test FILE=test_parser_md.lua`
- `make test FILE=test_parser_epub.lua`

All of the above passed on the final run.

Fix note:

- Threaded the active config object through `reader.open()` and `reader.statusline.start()` so EPUB can honor `paths.cache_dir`.
- Replaced startup notifications with generic messages that do not expose book title or path.
- Split missing vs unreadable file errors using `vim.uv.fs_stat()` before open attempts.
- Added a compatibility alias for `config.cache_dir` / `config.data_dir` so the existing progress/history code keeps working while the config surface stays normalized under `paths`.

Round 2 note:

- Removed the temporary top-level config aliases and updated `init.lua`, `history.lua`, and `reader/progress.lua` to read `config.paths.cache_dir` and `config.paths.data_dir` directly.
- Added a config test asserting the top-level aliases are absent.
