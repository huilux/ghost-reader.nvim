# Task 5 Report

Completed the stable actions and reversible control-layer refactor.

What changed:
- Added `lua/ghost-reader/actions.lua` with lazy wrappers for every shared action.
- Added `lua/ghost-reader/keymaps.lua` with one-time `<Plug>` mappings, global mappings, and reversible control mappings.
- Made control mappings snapshot existing buffer-local bindings with `maparg()` and restore them with `mapset()` in the original buffer context.
- Added focused tests for lazy dispatch, pre-existing mapping restoration, statusline-only extras, disabled bindings, buffer-safe cleanup, and idempotent global setup.
- Updated `tests/helpers.lua` so headless tests can create stable scratch-backed normal-editing fixtures without swap-file failures.

Verification:
- `make test FILE=test_actions.lua`
- `make test FILE=test_keymaps.lua`
- `make test-all`

Result:
- All tests passed.
