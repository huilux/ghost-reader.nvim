NVIM ?= nvim
TEST_INIT := tests/minimal_init.lua
TEST_FILES := $(sort $(wildcard tests/test_*.lua))

test:
	$(NVIM) --headless -u $(TEST_INIT) -c "PlenaryBustedFile tests/$(FILE)"

test-all:
	@set -e; for file in $(TEST_FILES); do \
		$(NVIM) --headless -u $(TEST_INIT) -c "PlenaryBustedFile $$file"; \
	done

test-runner-check:
	@output="$$(mktemp)"; \
	trap 'rm -f "$$output"' EXIT; \
	if $(NVIM) --headless -u $(TEST_INIT) -c "PlenaryBustedFile tests/fixtures/failing_test.lua" >"$$output" 2>&1; then \
		echo "runner failed to propagate a failing test"; cat "$$output"; exit 1; \
	fi; \
	if ! grep -q "RUNNER_SENTINEL" "$$output"; then \
		echo "runner did not report the sentinel failure"; cat "$$output"; exit 1; \
	fi; \
	echo "runner correctly propagated the sentinel failure"
