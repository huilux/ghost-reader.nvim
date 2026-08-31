# Task 9 Report

Implemented the production integration layer for the overlay reader refactor.

What changed:

- Added `lua/ghost-reader/session.lua` with explicit lifecycle, visibility, and control-state tracking.
- Added `lua/ghost-reader/renderer/init.lua` as the renderer factory and adapter registry.
- Wired the public entry points in `lua/ghost-reader/init.lua` to the new session API.
- Replaced the plugin command surface in `plugin/ghost-reader.lua` with the new commands.
- Added `tests/test_session.lua` and `tests/test_renderer_init.lua`.

Behavior verified:

- Session opens an overlay reader and tracks `ACTIVE` / `VISIBLE` / `ACTIVE`.
- Hard hide and restore transitions work.
- Renderer factory exposes `overlay`, `mirror`, and `statusline`.
- The full suite passes with `make test-all`.

Notes:

- Legacy `reader/init.lua` still remains in place for now, but the new renderer facade keeps it working until Task 10 removes the old path.
- Fix pass: session API now exposes `configure`, `start`, `get`, `hide`, `stop`, `dispatch`, and `_reset_for_tests`, and the integration coverage now exercises mirror fallback plus controlled navigation fixtures.
- Fix pass 2: public callers now use the string `path + mode` start contract, renderer errors say `unknown reader view: ...`, and transactional start leaves the active session untouched if replacement parsing fails.
- Fix pass 3: hard hide now leaves controls before hiding, overlay restore re-enters controls, statusline BufLeave exits controls without hiding, and the session/integration tests now cover autocmd-triggered transitions plus statusline renderer actions.
- Fix pass 4: renderer creation now propagates start failures, overlay fallback initializes mirror exactly once, TOC navigation uses the selected entry index, frame building exercises segment callbacks, and the full test suite passes with `make test-all`.
- Fix pass 5: BufLeave and WinLeave now have separate overlay policies, `QuitPre` relies on a single save path through `stop()`, the public facade no longer double-records history, and the tests assert the exact open/history/save/TOC behavior requested by review.
- Fix pass 6: the public facade restored its history dependency, and session startup is now transactional through the initial render so a failed replacement render leaves the previous active session and generation untouched.
