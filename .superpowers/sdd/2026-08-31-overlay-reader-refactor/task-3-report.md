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
