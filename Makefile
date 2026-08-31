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
	@if $(NVIM) --headless -u $(TEST_INIT) -c "PlenaryBustedFile tests/fixtures/failing_test.lua"; then \
		echo "runner failed to propagate a failing test"; exit 1; \
	else \
		echo "runner correctly propagated a failing test"; \
	fi
