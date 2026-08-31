# Task 4 Report

Completed the canonical-position navigation and version-2 progress refactor.

What changed:
- Replaced `lua/ghost-reader/reader/navigate.lua` with immutable canonical position helpers.
- Added `normalize`, `next_content`, `prev_content`, `next_page`, `prev_page`, `next_chapter`, `prev_chapter`, `go_to_chapter`, and `peek`.
- Kept a narrow `get_page_lines` compatibility shim so the existing reader flow still passes.
- Reworked `lua/ghost-reader/reader/progress.lua` to save and load version-2 progress records with a nested `position` object.
- Made progress loading reject malformed or unversioned JSON instead of translating old records.
- Updated progress notifications to report chapter and line progress without leaking book paths or filenames.
- Added focused tests for navigation and progress behavior.
- Added the H2-only Markdown fixture content needed by the existing parser suite.

Verification:
- `make test FILE=test_navigate.lua`
- `make test FILE=test_progress.lua`
- `make test-all`

Result:
- All tests passed.

Fix note:
- Corrected `next_page` and `prev_page` to apply exactly `step` content movements, and added a `step=1` navigation test alongside the sample `step=3` case.
