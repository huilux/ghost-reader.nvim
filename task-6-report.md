# Task 6 Report

Implemented the real-buffer overlay renderer in `lua/ghost-reader/renderer/overlay.lua` and added focused coverage for the new behavior.

What changed:

- Added `utils.wrap_display(text, width)` in `lua/ghost-reader/utils.lua` for UTF-8 wrapping by display width.
- Created the overlay renderer with:
  - real-buffer support checks,
  - extmark + `virt_lines` rendering only,
  - comment-prefix selection by filetype,
  - a `GhostReaderComment` highlight linked to `Comment`,
  - max 3 visible blocks,
  - hide/restore/stop paths that clear only the overlay namespace,
  - resize-aware anchor recomputation.
- Added tests for:
  - UTF-8 wrapping,
  - non-mutation of the real buffer,
  - max visible blocks,
  - filetype prefixes,
  - hide/restore idempotence,
  - terminal-buffer rejection,
  - resize anchor recomputation.

Verification:

- `make test FILE=test_utils.lua` passed.
- `make test FILE=test_renderer_overlay.lua` passed.
- A broader per-file sweep of `tests/test_*.lua` exposed an unrelated pre-existing failure in `tests/test_config.lua` around the old `boss_key.restore_keys` expectation.

Notes:

- I left the legacy renderer paths in place as transitional code, per the task brief.
- I did not change the unrelated config failure because it is outside Task 6 and appears to belong to the later schema refactor work.
