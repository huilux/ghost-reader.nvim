# Task 1 Report

Date: 2026-08-31

## Completed

- Added a permanent failing sentinel fixture at `tests/fixtures/failing_test.lua`.
- Added a minimal headless test init at `tests/minimal_init.lua` that prepends the repo and Plenary to runtimepath.
- Added shared helpers in `tests/helpers.lua` for module reset and buffer setup.
- Reworked `Makefile` so `test-all` runs each `tests/test_*.lua` file individually and added `test-runner-check`.

## Commit

- `e7a3d13`

## Commands Run

- `make test FILE=fixtures/failing_test.lua`
  - Summary: the sentinel test failed intentionally and the failure was propagated by the runner.
- `make test-runner-check`
  - Summary: exited 0 and printed `runner correctly propagated a failing test`.
- `make test-all`
  - Summary: exited non-zero on `tests/test_config.lua` because `boss_key.restore_keys` is still missing, which matches the known red state expected for Task 2.

## Unresolved Issues

- `make test-all` still fails on the pre-existing `restore_keys` contract gap in `tests/test_config.lua`.
- The helper module is added for later tasks, but it is not yet exercised by the current suite.

## Fix Note

- Tightened `test-runner-check` so it now requires both a non-zero exit and the `RUNNER_SENTINEL` marker in captured output. This prevents startup failures, missing dependencies, and syntax errors from being misreported as a passing sentinel check.
- Updated the sentinel fixture to emit a unique `RUNNER_SENTINEL` message in the assertion failure.

## Fix Verification

- `make test-runner-check`
  - Summary: passed and printed `runner correctly propagated the sentinel failure`.
- `make test FILE=fixtures/failing_test.lua`
  - Summary: failed as expected, with the sentinel marker present in the failure output.
