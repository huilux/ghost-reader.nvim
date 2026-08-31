# Task 8 Report

Date: 2026-08-31

Implemented a new `ghost-reader.renderer.statusline` module for the float-only statusline view.

What changed:

- Added a reusable single floating window and timer lifecycle.
- Implemented `start`, `render`, `update`, `hide`, `restore`, and `stop`.
- Added timer-expiry cleanup so the renderer tears itself down when autoplay times out.
- Kept the renderer free of session/book state and routine title/path notifications.
- Left `lua/ghost-reader/reader/statusline.lua` untouched as the transitional legacy path.
- Added focused coverage for reuse, timer cleanup, and notification silence.

Verification:

- `make test FILE=test_renderer_statusline.lua` passed.
- `make test FILE=test_config.lua` still fails in the existing legacy config suite on `boss_key` expectations.

Notes:

- `make test-all` in this checkout does not currently surface a useful suite summary, so I verified the new renderer with the focused file and then checked the broader suite until the existing unrelated config failure appeared.
