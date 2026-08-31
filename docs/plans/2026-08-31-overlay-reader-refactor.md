# Overlay Reader Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the copied-code Buffer reader with a real-Buffer extmark overlay, unify controls across overlay and statusline modes, and centralize all reading lifecycle state in one session.

**Architecture:** `session.lua` owns the only active book, canonical position, visibility, controls, resources, and view adapter. `actions.lua` and `keymaps.lua` expose stable actions and reversible control mappings; overlay, mirror, and statusline implement a small view interface without owning reading position. The refactor is intentionally breaking and removes all old sparse-notes, boss-key, and flat-keymap interfaces.

**Tech Stack:** LuaJIT, Neovim 0.10+ Lua API, extmarks with `virt_lines`, Plenary Busted, Make.

**Spec:** `docs/design/2026-08-31-overlay-reader-refactor-design.md`

## Global Constraints

- Support Neovim 0.10 and newer without adding a runtime dependency.
- Do not preserve or translate `sparse_notes`, `boss_key`, old flat `keymaps`, `statusline.mode`, `GhostReaderBoss`, or `GhostReaderRestore`.
- Overlay mode must never change real Buffer lines, name, filetype, modified state, undo history, or statusline.
- Only one active reading session may exist.
- Shared actions must have identical keys and user-level meaning in overlay, mirror, and statusline controls.
- Hard hide must restore captured mappings and must never restore automatically.
- With `stealth.silent = true`, routine operations must not put book names or paths in notifications.
- Preserve unrelated worktree changes and untracked architecture artifacts.

## Target File Structure

- `lua/ghost-reader/session.lua`: active-session lifecycle, canonical position, action dispatch, autocmds, view ownership, and cleanup.
- `lua/ghost-reader/actions.lua`: named callbacks that lazily dispatch to `session.lua`.
- `lua/ghost-reader/keymaps.lua`: `<Plug>` mappings, global mappings, reversible control-layer mappings.
- `lua/ghost-reader/renderer/overlay.lua`: extmark virtual-line view for real Buffers.
- `lua/ghost-reader/renderer/mirror.lua`: stable anonymous scratch-buffer fallback.
- `lua/ghost-reader/renderer/presets.lua`: fallback code skeleton data currently under `stealth/`.
- `lua/ghost-reader/renderer/statusline.lua`: one-line float view and autoplay timer, without session ownership.
- `lua/ghost-reader/reader/navigate.lua`: pure canonical-position navigation.
- `lua/ghost-reader/config.lua`: the new strict configuration schema.
- `lua/ghost-reader/bookshelf/init.lua`: stateless parser dispatch and book validation.
- `lua/ghost-reader/init.lua`: small public facade and book-selection UI.
- `plugin/ghost-reader.lua`: new command set only.
- `tests/helpers.lua`: module reset, temporary path, Buffer, and mapping helpers.
- `tests/minimal_init.lua`: deterministic headless test runtime.

---

### Task 1: Make the test runner trustworthy

**Files:**
- Create: `tests/minimal_init.lua`
- Create: `tests/fixtures/failing_test.lua`
- Create: `tests/helpers.lua`
- Modify: `Makefile:1-6`

**Interfaces:**
- Consumes: Neovim and the existing local Plenary installation.
- Produces: `make test-all`, `make test FILE=test_config.lua`, and `make test-runner-check`; `require("tests.helpers")` utilities used by later tasks.

- [ ] **Step 1: Add a permanent failing runner fixture**

```lua
-- tests/fixtures/failing_test.lua
describe("test runner sentinel", function()
  it("fails intentionally", function()
    assert.is_true(false)
  end)
end)
```

- [ ] **Step 2: Add a minimal test runtime and shared reset helper**

```lua
-- tests/minimal_init.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = vim.fn.getcwd() .. "/?.lua;" .. package.path
local plenary = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(plenary) ~= 1 then
  error("plenary.nvim not found at " .. plenary)
end
vim.opt.runtimepath:prepend(plenary)
```

```lua
-- tests/helpers.lua
local M = {}

function M.reset_modules()
  for name in pairs(package.loaded) do
    if name:match("^ghost%-reader") then package.loaded[name] = nil end
  end
end

function M.new_normal_buffer(lines, filetype)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = filetype or "lua"
  vim.bo[buf].modified = false
  return buf, vim.api.nvim_get_current_win()
end

return M
```

- [ ] **Step 3: Replace asynchronous directory scheduling with per-file execution**

```make
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
```

- [ ] **Step 4: Verify failure propagation and the real suite**

Run: `make test-runner-check`

Expected: exit 0 and output ending with `runner correctly propagated a failing test`.

Run: `make test-all`

Expected: non-zero because `tests/test_config.lua` still exposes the old `restore_keys` contract. This is the known red test fixed by Task 2.

- [ ] **Step 5: Commit the runner**

```bash
git add Makefile tests/minimal_init.lua tests/helpers.lua tests/fixtures/failing_test.lua
git commit -m "test: make headless suite propagate failures"
```

### Task 2: Replace configuration with the strict breaking schema

**Files:**
- Modify: `lua/ghost-reader/config.lua:1-84`
- Replace: `tests/test_config.lua`

**Interfaces:**
- Consumes: `vim.fn.stdpath`, user configuration table or `nil`.
- Produces: `config.setup(user_config) -> config_table`; final paths at `config.paths.cache_dir` and `config.paths.data_dir`.

- [ ] **Step 1: Replace the old tests with schema and validation tests**

```lua
local config = require("ghost-reader.config")

describe("config", function()
  it("returns the new defaults", function()
    local cfg = config.setup()
    assert.equal("overlay", cfg.reader.renderer)
    assert.equal(3, cfg.reader.visible_blocks)
    assert.equal("j", cfg.keymaps.controls.next_content)
    assert.equal("gh", cfg.keymaps.controls.hide)
    assert.equal("<Esc>", cfg.keymaps.controls.exit_controls)
    assert.is_truthy(cfg.paths.cache_dir:match("ghost%-reader/$"))
  end)

  it("rejects legacy keys", function()
    assert.has_error(function() config.setup({ boss_key = {} }) end, "unknown config key: boss_key")
    assert.has_error(function() config.setup({ statusline = { mode = "manual" } }) end,
      "unknown config key: statusline.mode")
  end)

  it("accepts false to disable a mapping", function()
    local cfg = config.setup({ keymaps = { controls = { help = false } } })
    assert.is_false(cfg.keymaps.controls.help)
  end)

  it("rejects invalid values", function()
    assert.has_error(function() config.setup({ reader = { visible_blocks = 0 } }) end)
    assert.has_error(function() config.setup({ statusline = { interval = "fast" } }) end)
    assert.has_error(function() config.setup({ paths = { cache_dir = 42 } }) end)
  end)
end)
```

- [ ] **Step 2: Run the config test and verify it fails on old defaults**

Run: `make test FILE=test_config.lua`

Expected: FAIL because `reader`, `stealth`, and nested keymap defaults do not exist.

- [ ] **Step 3: Implement defaults, known-key validation, and value validation**

```lua
local defaults = {
  reader = { renderer = "overlay", visible_blocks = 3, mirror_fallback = true },
  statusline = { interval = 3000, autoplay = true, page_step = 5 },
  stealth = {
    hide_on_focus_lost = true,
    silent = true,
    overlay = { hide_on_insert = true, hide_on_buf_leave = true, hide_on_win_leave = true },
  },
  paths = {},
  keymaps = {
    global = {
      open = "<leader>rr", statusline = "<leader>rs", control = "<leader>rm",
      hide = "<leader>rh", toc = "<leader>rt", close = "<leader>rq",
    },
    controls = {
      next_content = "j", prev_content = "k", next_page = "<C-f>", prev_page = "<C-b>",
      next_chapter = "]]", prev_chapter = "[[", toc = "t", progress = "g%",
      hide = "gh", close = "q", help = "?", exit_controls = "<Esc>",
    },
    statusline = { toggle_auto = "a", faster = "+", slower = "-" },
  },
}
```

Implement `validate_known_keys(user_config, defaults, prefix)` before merging. Treat `paths.cache_dir` and `paths.data_dir` as the only allowed keys missing from the literal defaults table. Validate positive integers, booleans, renderer enum `overlay|mirror`, strings for path overrides, and `string|false` for every mapping.

After validation and deep merge, assign missing paths:

```lua
cfg.paths.cache_dir = cfg.paths.cache_dir or (vim.fn.stdpath("cache") .. "/ghost-reader/")
cfg.paths.data_dir = cfg.paths.data_dir or (vim.fn.stdpath("data") .. "/ghost-reader/")
```

- [ ] **Step 4: Run the focused and complete suites**

Run: `make test FILE=test_config.lua`

Expected: PASS.

Run: `make test-all`

Expected: all current tests PASS.

- [ ] **Step 5: Commit the schema**

```bash
git add lua/ghost-reader/config.lua tests/test_config.lua
git commit -m "refactor: replace ghost reader configuration schema"
```

### Task 3: Make the bookshelf stateless and enforce parser contracts

**Files:**
- Modify: `lua/ghost-reader/bookshelf/init.lua:1-66`
- Modify: `lua/ghost-reader/bookshelf/parser_txt.lua:66-142`
- Modify: `lua/ghost-reader/bookshelf/parser_md.lua:17-99`
- Modify: `lua/ghost-reader/bookshelf/parser_epub.lua:71-176`
- Modify: `tests/test_parser_txt.lua`
- Modify: `tests/test_parser_md.lua`
- Modify: `tests/test_parser_epub.lua`
- Create: `tests/test_bookshelf.lua`
- Create: `tests/fixtures/heading_only_h2.md`

**Interfaces:**
- Consumes: `bookshelf.open(path, parser_opts)`.
- Produces: `book, nil` only for a readable non-empty book; `nil, error_string` for missing, unreadable, unsupported, or empty input. The module has no `current_book`, `get_current`, or `close` state.

- [ ] **Step 1: Add failing contract and TOC tests**

```lua
-- tests/test_bookshelf.lua
local bookshelf = require("ghost-reader.bookshelf")

describe("bookshelf", function()
  it("rejects a missing txt file", function()
    local book, err = bookshelf.open("/nonexistent/ghost-reader.txt")
    assert.is_nil(book)
    assert.matches("file not found", err)
  end)

  it("rejects an empty parsed book", function()
    local path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({}, path)
    local book, err = bookshelf.open(path)
    assert.is_nil(book)
    assert.matches("no readable content", err)
    vim.fn.delete(path)
  end)
end)
```

```markdown
<!-- tests/fixtures/heading_only_h2.md -->
## Opening

Content under a level-two heading.
```

In `tests/test_parser_md.lua`, define `creates an implicit chapter for H2-only input` and assert one chapter containing the content line. Define `keeps every TOC index in chapter bounds` and assert every entry satisfies `entry.index >= 1 and entry.index <= #book.chapters`. Define `points a subsection at its containing chapter` and assert the sample fixture's `Section 1.1` entry has `index == 1`.

- [ ] **Step 2: Run parser tests and verify the failures**

Run: `make test FILE=test_bookshelf.lua`

Expected: FAIL because missing TXT currently returns an empty book.

Run: `make test FILE=test_parser_md.lua`

Expected: FAIL because `Section 1.1` currently points to chapter 2 and H2-only input has no chapters.

- [ ] **Step 3: Normalize parser failures and remove dispatcher state**

Each parser must start with a readable-file check and return `nil, "file not found: " .. path` when it cannot open the path. `bookshelf.open` must validate the final structure:

```lua
local function validate_book(book, path)
  local readable_lines = 0
  if type(book) == "table" and type(book.chapters) == "table" then
    for _, chapter in ipairs(book.chapters) do
      readable_lines = readable_lines + (type(chapter.lines) == "table" and #chapter.lines or 0)
    end
  end
  if type(book) ~= "table" or type(book.chapters) ~= "table"
      or #book.chapters == 0 or readable_lines == 0 then
    return nil, "book has no readable content: " .. path
  end
  return book
end
```

Delete `current_book`, `get_current()`, and `close()` from the dispatcher. Preserve the `parser_opts` argument and pass it to the selected parser.

For Markdown, create an implicit chapter named with `fnamemodify(path, ":t")` when content or a lower-level heading appears before the first H1. Every lower-level TOC entry uses the current chapter index, never `#chapters + 1`.

- [ ] **Step 4: Run all parser and bookshelf tests**

Run: `make test FILE=test_bookshelf.lua`

Run: `make test FILE=test_parser_txt.lua`

Run: `make test FILE=test_parser_md.lua`

Run: `make test FILE=test_parser_epub.lua`

Expected: all PASS.

- [ ] **Step 5: Commit the parser contract**

```bash
git add lua/ghost-reader/bookshelf tests/test_bookshelf.lua tests/test_parser_txt.lua tests/test_parser_md.lua tests/test_parser_epub.lua tests/fixtures/heading_only_h2.md
git commit -m "refactor: enforce stateless book parsing contract"
```

### Task 4: Introduce canonical position navigation and versioned progress

**Files:**
- Replace: `lua/ghost-reader/reader/navigate.lua`
- Modify: `lua/ghost-reader/reader/progress.lua:1-68`
- Create: `tests/test_navigate.lua`
- Create: `tests/test_progress.lua`

**Interfaces:**
- Consumes: `book`, position `{ chapter_index, line_index, segment_index }`, and `segment_count(chapter_index, line_index) -> positive_integer`.
- Produces: `navigate.normalize`, `next_content`, `prev_content`, `next_page`, `prev_page`, `next_chapter`, `prev_chapter`, `go_to_chapter`, and `peek`; every movement returns `new_position, moved_boolean` without mutating its input.
- Produces: progress JSON version 2 with `position` object; version 1 data is ignored.

- [ ] **Step 1: Write boundary, segment, batch, and immutability tests**

```lua
local navigate = require("ghost-reader.reader.navigate")

local book = { chapters = {
  { title = "One", lines = { "one", "two" } },
  { title = "Two", lines = { "three" } },
} }

local function segments(chapter, line)
  return chapter == 1 and line == 1 and 2 or 1
end

it("moves through segments before the next logical line", function()
  local original = { chapter_index = 1, line_index = 1, segment_index = 1 }
  local next_pos = navigate.next_content(book, original, segments)
  assert.same({ chapter_index = 1, line_index = 1, segment_index = 2 }, next_pos)
  assert.same({ chapter_index = 1, line_index = 1, segment_index = 1 }, original)
end)

it("crosses chapter boundaries", function()
  local pos = { chapter_index = 1, line_index = 2, segment_index = 1 }
  local next_pos, moved = navigate.next_content(book, pos, segments)
  assert.is_true(moved)
  assert.same({ chapter_index = 2, line_index = 1, segment_index = 1 }, next_pos)
end)
```

In the same file, define these cases with exact outcomes:

- `moves to the previous segment before the previous line`: segment 2 becomes segment 1 on the same line.
- `does not move before the first unit`: returns an equal position and `false`.
- `does not move after the last unit`: returns an equal position and `false`.
- `moves three units as one page batch`: starting at chapter 1 line 1 segment 1 reaches chapter 1 line 2 segment 1 with the sample segment callback.
- `resets line and segment on chapter jump`: next chapter produces `{ chapter_index = 2, line_index = 1, segment_index = 1 }`.
- `normalizes invalid saved indices`: zero, negative, and oversized indices clamp to existing chapter, line, and segment bounds.
- `peeks without mutation`: requesting three units returns three copied positions and leaves the source table unchanged.

In `tests/test_progress.lua`, define `round trips version 2 position` and assert all three indices. Define `ignores unversioned progress` and assert `load` returns nil for JSON without `version = 2`. Define `shows progress without book identity` by stubbing `vim.notify`, calling `progress.show`, and asserting the message contains chapter/line percentage but contains neither `book.path` nor `fnamemodify(book.path, ":t")`.

- [ ] **Step 2: Run the new tests and verify missing interfaces**

Run: `make test FILE=test_navigate.lua`

Expected: FAIL because the current module uses `line_offset` page mutation.

Run: `make test FILE=test_progress.lua`

Expected: FAIL because progress does not store a versioned `position`.

- [ ] **Step 3: Implement immutable navigation**

Use a private copier:

```lua
local function copy(pos)
  return {
    chapter_index = pos.chapter_index,
    line_index = pos.line_index,
    segment_index = pos.segment_index,
  }
end
```

`next_page` and `prev_page` repeat content movement exactly `step` times and stop at the boundary. `peek(book, position, count, segment_count)` returns a list beginning with a copy of the current position followed by up to `count - 1` subsequent positions.

- [ ] **Step 4: Write version 2 progress records**

```lua
f:write(vim.json.encode({
  version = 2,
  book_path = book.path,
  position = position,
  last_read = os.time(),
}))
```

Use `config.paths.data_dir`. Validate decoded types and positive integer indices before returning `decoded.position`; do not translate old `chapter_index` or `line_offset` records.

Update `progress.show` to accept canonical position and calculate progress from completed chapter lines plus `line_index`. Its notification text contains only position and percentage.

- [ ] **Step 5: Run focused and complete tests**

Run: `make test FILE=test_navigate.lua`

Run: `make test FILE=test_progress.lua`

Run: `make test-all`

Expected: all PASS.

- [ ] **Step 6: Commit canonical navigation**

```bash
git add lua/ghost-reader/reader/navigate.lua lua/ghost-reader/reader/progress.lua tests/test_navigate.lua tests/test_progress.lua
git commit -m "refactor: add canonical reading position"
```

### Task 5: Add stable actions and reversible controls

**Files:**
- Create: `lua/ghost-reader/actions.lua`
- Create: `lua/ghost-reader/keymaps.lua`
- Create: `tests/test_actions.lua`
- Create: `tests/test_keymaps.lua`

**Interfaces:**
- Consumes: `session.dispatch(action_name)` for active-session actions and public `select_book(preferred_mode)` for open actions, all through lazy `require` calls.
- Produces: functions on `actions` for every action name; `<Plug>(GhostReaderOpen)`, `Statusline`, `Control`, `Hide`, `Toc`, and `Close`; `keymaps.setup(config)`, `enter_controls(session, config)`, and `leave_controls(session)`.

- [ ] **Step 1: Test lazy dispatch and exact mapping restoration**

```lua
it("dispatches a named action lazily", function()
  package.loaded["ghost-reader.session"] = { dispatch = function(name) _G.dispatched = name end }
  require("ghost-reader.actions").next_content()
  assert.equal("next_content", _G.dispatched)
end)
```

```lua
it("restores a pre-existing buffer mapping", function()
  local buf = vim.api.nvim_get_current_buf()
  vim.keymap.set("n", "j", "gj", { buffer = buf, desc = "user j" })
  local session = { mode = "overlay", control_buf = buf, controls_active = false }
  keymaps.enter_controls(session, config.setup())
  assert.equal("Ghost Reader: next content", vim.fn.maparg("j", "n", false, true).desc)
  keymaps.leave_controls(session)
  local restored = vim.fn.maparg("j", "n", false, true)
  assert.equal("gj", restored.rhs)
  assert.equal("user j", restored.desc)
end)
```

In `tests/test_keymaps.lua`, define these named cases:

- `deletes only plugin mappings when no previous map exists`: `maparg` is empty after leaving controls.
- `installs statusline extras only in statusline mode`: `a`, `+`, and `-` exist for statusline and remain unchanged for overlay.
- `skips false bindings`: a disabled `help` mapping is absent.
- `cleans the captured buffer after current buffer changes`: switch to a second Buffer before cleanup and assert the first Buffer is restored while the second is untouched.
- `sets global mappings idempotently`: call `setup` twice and assert one mapping with the expected `<Plug>` rhs for every configured global lhs.

- [ ] **Step 2: Run tests and verify modules are missing**

Run: `make test FILE=test_actions.lua`

Run: `make test FILE=test_keymaps.lua`

Expected: FAIL with missing modules.

- [ ] **Step 3: Implement action wrappers and `<Plug>` mappings**

Each action wrapper performs a lazy require to avoid a session/actions/keymaps cycle:

```lua
function M.next_content()
  return require("ghost-reader.session").dispatch("next_content")
end
```

The two actions that must work without an active session call the public facade instead:

```lua
function M.open()
  return require("ghost-reader").select_book()
end

function M.statusline()
  return require("ghost-reader").select_book("statusline")
end
```

Global lifecycle actions call explicit session methods, while control-layer movement and statusline extras use `dispatch`:

```lua
function M.control() return require("ghost-reader.session").toggle_controls() end
function M.hide() return require("ghost-reader.session").toggle_hide() end
function M.toc() return require("ghost-reader.session").toc() end
function M.close() return require("ghost-reader.session").stop() end
```

Create named `<Plug>` mappings once. Global configured mappings point to those `<Plug>` keys and carry `Ghost Reader:` descriptions.

- [ ] **Step 4: Implement reversible control mappings**

Capture mappings inside the target Buffer context:

```lua
local previous = vim.api.nvim_buf_call(buf, function()
  return vim.fn.maparg(lhs, "n", false, true)
end)
```

On cleanup, delete the plugin map from the captured Buffer. If `next(previous) ~= nil`, restore it inside `nvim_buf_call` with:

```lua
vim.fn.mapset("n", false, previous)
```

Store captures in `session.control_maps`; never infer the Buffer from `0` during cleanup.

- [ ] **Step 5: Run focused and complete tests**

Run: `make test FILE=test_actions.lua`

Run: `make test FILE=test_keymaps.lua`

Run: `make test-all`

Expected: all PASS.

- [ ] **Step 6: Commit the action layer**

```bash
git add lua/ghost-reader/actions.lua lua/ghost-reader/keymaps.lua tests/test_actions.lua tests/test_keymaps.lua
git commit -m "feat: add unified reversible reader controls"
```

### Task 6: Build the real-Buffer overlay renderer

**Files:**
- Create: `lua/ghost-reader/renderer/overlay.lua`
- Modify: `lua/ghost-reader/utils.lua:89-112`
- Create: `tests/test_renderer_overlay.lua`
- Create: `tests/test_utils.lua`

**Interfaces:**
- Consumes: context with `target_buf`, `target_win`, `config`, and `view_state`; frame `{ blocks = { { text, active }... } }`.
- Produces: `supports(buf, win)`, `start(ctx)`, `render(ctx, frame)`, `hide(ctx)`, `restore(ctx, frame)`, `stop(ctx)`, `page_size(ctx)`, `segment_count(ctx, text)`, and `segment_text(ctx, text, index)`.
- Produces: `utils.wrap_display(text, width) -> string[]` for UTF-8 display-width wrapping.

- [ ] **Step 1: Write non-mutation and rendering tests**

```lua
it("renders virtual lines without changing the real buffer", function()
  local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local name = vim.api.nvim_buf_get_name(buf)
  local ft = vim.bo[buf].filetype
  local statusline = vim.wo[win].statusline

  assert.is_true(overlay.start(ctx))
  assert.is_true(overlay.render(ctx, { blocks = {
    { text = "first paragraph", active = true },
    { text = "second paragraph", active = false },
  } }))

  assert.same(before, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  assert.equal(name, vim.api.nvim_buf_get_name(buf))
  assert.equal(ft, vim.bo[buf].filetype)
  assert.equal(statusline, vim.wo[win].statusline)
  assert.is_false(vim.bo[buf].modified)
end)
```

In `tests/test_renderer_overlay.lua`, define `limits one frame to visible_blocks` and assert exactly three extmarks for four supplied blocks. Define `uses filetype comment prefixes` and inspect `virt_lines` for `-- ` in Lua. Define `hide clears and restore recreates marks`, `stop is idempotent`, `rejects a terminal buftype`, and `resize recomputes anchors inside the new visible range` with direct extmark assertions. In `tests/test_utils.lua`, define `wraps Chinese text by display width` and assert `vim.fn.strwidth(segment) <= width` for every returned segment and concatenation reproduces the input.

- [ ] **Step 2: Run tests and verify missing renderer behavior**

Run: `make test FILE=test_utils.lua`

Run: `make test FILE=test_renderer_overlay.lua`

Expected: FAIL with missing `wrap_display` and overlay module.

- [ ] **Step 3: Implement UTF-8 display wrapping**

Build `utils.wrap_display` on `utils.utf8_next` and `vim.fn.strwidth`. Return `{ "" }` for an empty string, never split a UTF-8 codepoint, and never return a segment wider than `width` unless one codepoint itself is wider.

- [ ] **Step 4: Implement overlay support and stable anchors**

`supports` requires valid loaded Buffer and Window, `vim.bo[buf].buftype == ""`, and the Window displaying that Buffer. `start` creates `GhostReaderComment` with `{ link = "Comment", default = true }`, stores the namespace in `ctx.view_state.overlay`, and computes visible anchors near 25%, 50%, and 75% while skipping closed folds and edge rows.

Render each wrapped segment with:

```lua
vim.api.nvim_buf_set_extmark(ctx.target_buf, namespace, anchor - 1, 0, {
  virt_lines = virtual_lines,
  virt_lines_above = false,
  priority = 90,
})
```

Use filetype-specific prefixes but no random labels. Clear only the Ghost Reader namespace during rerender and hide.

- [ ] **Step 5: Run focused and complete tests**

Run: `make test FILE=test_utils.lua`

Run: `make test FILE=test_renderer_overlay.lua`

Run: `make test-all`

Expected: all PASS.

- [ ] **Step 6: Commit the overlay renderer**

```bash
git add lua/ghost-reader/utils.lua lua/ghost-reader/renderer/overlay.lua tests/test_utils.lua tests/test_renderer_overlay.lua
git commit -m "feat: render books as real buffer overlays"
```

### Task 7: Add a stable mirror fallback beside the legacy renderer

**Files:**
- Create: `lua/ghost-reader/renderer/mirror.lua`
- Create: `lua/ghost-reader/renderer/presets.lua`
- Create: `tests/test_renderer_mirror.lua`

**Interfaces:**
- Consumes: the same context and frame shape as overlay.
- Produces: the same view methods as overlay, except `supports` always succeeds when Neovim can create a scratch Buffer.

- [ ] **Step 1: Write stable-skeleton, anonymity, and restore tests**

```lua
it("keeps one skeleton and an unnamed scratch buffer", function()
  assert.is_true(mirror.start(ctx))
  local mirror_buf = ctx.view_state.mirror.buf
  local skeleton = vim.deepcopy(ctx.view_state.mirror.skeleton)
  assert.equal("", vim.api.nvim_buf_get_name(mirror_buf))

  mirror.render(ctx, { blocks = { { text = "page one", active = true } } })
  mirror.render(ctx, { blocks = { { text = "page two", active = true } } })
  assert.same(skeleton, ctx.view_state.mirror.skeleton)
end)
```

In the same file, define `hide restores the real buffer and view` and compare Buffer, Window, cursor, topline, and leftcol. Define `restore reuses the mirror buffer` and assert the Buffer handle is unchanged. Define `stop deletes the scratch buffer` and assert `nvim_buf_is_valid` is false. Define `hide and stop are idempotent` and call each twice without errors.

- [ ] **Step 2: Run the mirror tests and verify the module is missing**

Run: `make test FILE=test_renderer_mirror.lua`

Expected: FAIL with missing mirror module.

- [ ] **Step 3: Move presets and implement one-time skeleton selection**

Copy the existing preset data into `renderer/presets.lua` without the educational comments. Leave the old preset and sparse-notes files untouched until the atomic public cutover in Task 10. On `start`, collect eligible real Buffer candidates once, choose the largest candidate deterministically, and fall back to the configured preset only when no candidate has at least 20 lines.

Save `{ buf, win, view }` before opening an unnamed `nofile` scratch Buffer. Store the chosen skeleton in `ctx.view_state.mirror.skeleton`.

- [ ] **Step 4: Implement deterministic mirror rendering and lifecycle**

Place frame blocks at evenly spaced skeleton positions. Use the skeleton filetype for syntax highlighting, but do not assign a Buffer name or alter global/window statusline settings. Hide switches back to the saved Window and Buffer when valid; restore shows the retained scratch Buffer; stop restores the real view and deletes the scratch Buffer.

- [ ] **Step 5: Point preset tests at the new module and run tests**

Update `tests/test_presets.lua` to require `ghost-reader.renderer.presets`.

Run: `make test FILE=test_renderer_mirror.lua`

Run: `make test FILE=test_presets.lua`

Run: `make test-all`

Expected: all PASS. Legacy files remain reachable only through the old public controller until Task 10.

- [ ] **Step 6: Commit mirror fallback**

```bash
git add lua/ghost-reader/renderer tests/test_renderer_mirror.lua tests/test_presets.lua
git commit -m "feat: add stable mirror fallback"
```

### Task 8: Rebuild statusline as a session-owned view

**Files:**
- Create: `lua/ghost-reader/renderer/statusline.lua`
- Create: `tests/test_renderer_statusline.lua`

**Interfaces:**
- Consumes: session context, one-block frame, and action callbacks.
- Produces: `start`, `render`, `hide`, `restore`, `stop`, `resize`, `page_size`, `segment_count`, `segment_text`, `toggle_auto`, `faster`, and `slower`; it does not parse books, save progress, record history, or install keymaps.

- [ ] **Step 1: Write view ownership and timer tests**

```lua
it("creates and cleans only statusline view resources", function()
  assert.is_true(statusline.start(ctx))
  statusline.render(ctx, { blocks = { { text = "segment", active = true } } })
  assert.is_true(vim.api.nvim_win_is_valid(ctx.view_state.statusline.win))
  statusline.stop(ctx)
  assert.is_nil(ctx.view_state.statusline.win)
  assert.is_nil(ctx.view_state.statusline.buf)
  assert.is_nil(ctx.view_state.statusline.timer)
end)
```

In the same file, define these cases and assertions:

- `segments by display width`: every segment width fits `vim.o.columns - 4` and concatenation reproduces the input.
- `resizes the float`: after changing `vim.o.columns`, `resize` updates float width and row.
- `hide and restore recreate view resources`: hidden handles are nil and restored handles are valid.
- `autoplay dispatches without controls`: `controls_active = false` still advances while visible.
- `clamps speed`: repeated faster stops at 500 ms and repeated slower stops at 15000 ms.
- `ignores stale generation callbacks`: replace the active session generation before firing the callback and assert no dispatch.
- `does not rearm at end of book`: make `actions.next_content()` return false and assert timer remains nil after the callback.

- [ ] **Step 2: Run the statusline test and verify old ownership fails**

Run: `make test FILE=test_renderer_statusline.lua`

Expected: FAIL because `ghost-reader.renderer.statusline` does not exist.

- [ ] **Step 3: Implement a context-only float adapter**

Store all handles under `ctx.view_state.statusline`. Create the float at editor bottom without focus. `render` writes only the supplied frame segment and a subtle auto/manual icon. `segment_count` and `segment_text` use `utils.wrap_display(text, vim.o.columns - 4)`.

- [ ] **Step 4: Implement generation-safe autoplay**

Before arming a one-shot timer, capture `ctx.generation`. The callback dispatches only when the active session still has that generation, remains visible, and autoplay is enabled. Rearm only when `actions.next_content()` returns true.

`hide` stops the timer and deletes float resources; `restore` recreates them and resumes autoplay; `stop` is idempotent and clears every handle.

- [ ] **Step 5: Run focused and complete tests**

Run: `make test FILE=test_renderer_statusline.lua`

Run: `make test-all`

Expected: all PASS.

- [ ] **Step 6: Commit the view adapter**

```bash
git add lua/ghost-reader/renderer/statusline.lua tests/test_renderer_statusline.lua
git commit -m "refactor: make statusline a session owned view"
```

### Task 9: Centralize lifecycle and action dispatch in one session

**Files:**
- Create: `lua/ghost-reader/session.lua`
- Modify: `lua/ghost-reader/renderer/init.lua:1-22`
- Modify: `lua/ghost-reader/history.lua:21-89`
- Create: `tests/test_session.lua`
- Create: `tests/test_session_integration.lua`

**Interfaces:**
- Consumes: `session.configure(config)`, `start(path, mode)`, `dispatch(action)`, `toggle_controls`, `hide`, `restore`, `toggle_hide`, `stop`, `toc`, `get`, and `_reset_for_tests`.
- Produces: the only active session context and renderer selection for `overlay`, `mirror`, and `statusline`. `dispatch(action) -> boolean` returns whether a movement or mode operation took effect so autoplay can stop at a boundary.

- [ ] **Step 1: Write lifecycle and transactional-start tests**

In `before_each`, call `session._reset_for_tests()` and `session.configure(config.setup({ paths = temporary_paths }))`; create `valid_path` inside the temporary data directory so tests never write user state.

```lua
it("keeps the valid session when a replacement book fails", function()
  assert.is_true(session.start(valid_path, "overlay"))
  local generation = session.get().generation
  local ok = session.start("/nonexistent/book.txt", "overlay")
  assert.is_false(ok)
  assert.equal(generation, session.get().generation)
end)

it("closes either user-facing mode", function()
  assert.is_true(session.start(valid_path, "statusline"))
  session.stop()
  assert.is_nil(session.get())
end)
```

In `tests/test_session.lua`, define these named cases with direct state assertions:

- `replaces one active session only after parse success`.
- `falls back from unsupported overlay to mirror once` and asserts `mode == "overlay"`, `view_name == "mirror"`.
- `tracks visibility independently from controls` and asserts visible/inactive is valid.
- `hard hide exits controls and restores mappings`.
- `restores controls for overlay but not statusline`.
- `cleans resources idempotently` by calling stop twice.
- `uses the selected TOC entry index` by selecting the second item whose `entry.index` is 1 and asserting chapter 1.
- `keeps routine silent notifications anonymous` by capturing `vim.notify` and rejecting path/title substrings.
- `records history and progress only after successful start` by stubbing both modules and counting calls.

- [ ] **Step 2: Write event-policy integration tests**

Exercise autocmds with `vim.api.nvim_exec_autocmds`:

```lua
vim.api.nvim_exec_autocmds("InsertEnter", { buffer = target_buf })
assert.equal("SOFT_HIDDEN", session.get().visibility)
vim.api.nvim_exec_autocmds("InsertLeave", { buffer = target_buf })
assert.equal("VISIBLE", session.get().visibility)
```

In `tests/test_session_integration.lua`, define `overlay hard hides on BufLeave`, `overlay hard hides on WinLeave`, `statusline BufLeave exits controls but remains visible`, `FocusLost hard hides every mode`, and `QuitPre saves position without switching buffer`. Trigger each named event with `nvim_exec_autocmds` and assert visibility, controls, save call count, and current Buffer exactly.

- [ ] **Step 3: Run session tests and verify the module is missing**

Run: `make test FILE=test_session.lua`

Run: `make test FILE=test_session_integration.lua`

Expected: FAIL with missing session module.

- [ ] **Step 4: Implement context creation and transactional start**

Create context fields exactly as specified:

```lua
local ctx = {
  generation = next_generation,
  lifecycle = "ACTIVE",
  visibility = "VISIBLE",
  controls_active = mode ~= "statusline",
  mode = mode,
  view_name = mode,
  book = book,
  path = path,
  position = saved_position or { chapter_index = 1, line_index = 1, segment_index = 1 },
  config = configured,
  view_state = {},
  control_maps = {},
  target_buf = vim.api.nvim_get_current_buf(),
  target_win = vim.api.nvim_get_current_win(),
}
```

Parse and validate the new book before stopping the old session. Pass `{ cache_dir = config.paths.cache_dir }` into `bookshelf.open`. Select overlay only when `overlay.supports` succeeds; otherwise try mirror exactly once when enabled and set `ctx.view_name = "mirror"` while retaining `ctx.mode = "overlay"`. Statusline uses `mode = view_name = "statusline"`.

- [ ] **Step 5: Implement frame building and common dispatch**

Ask the active view for segment counts and text. Build a frame from `navigate.peek`, with `reader.visible_blocks` blocks for overlay/mirror and one block for statusline. Common movement replaces `ctx.position` only when navigation returns `moved = true`, then renders.

Dispatch `toc`, `progress`, `hide`, `close`, `help`, and `exit_controls` through session functions. Dispatch statusline-only actions to the view and return `false` in other modes.

- [ ] **Step 6: Implement mode-aware events, hide, restore, and cleanup**

Create one augroup named with the generation. Overlay registers InsertEnter/Leave and configured Buffer/Window leave handlers. Statusline Buffer leave only calls `keymaps.leave_controls`. FocusLost hard-hides every mode when enabled.

Hard hide calls the active view's `hide`, exits controls, and sets `HARD_HIDDEN`. Restore uses the current eligible Buffer for overlay, falls back to mirror if required, makes overlay/mirror controls active, and leaves statusline controls inactive.

Stop sets `STOPPING`, deletes the augroup, exits controls, stops the view, saves progress, and clears the active context even if one cleanup resource is already invalid.

- [ ] **Step 7: Make renderer selection explicit and history path-aware**

`renderer/init.lua` must expose:

```lua
function M.get(name)
  if name == "overlay" then return require("ghost-reader.renderer.overlay") end
  if name == "mirror" then return require("ghost-reader.renderer.mirror") end
  if name == "statusline" then return require("ghost-reader.renderer.statusline") end
  error("unknown reader view: " .. tostring(name))
end
```

Keep the existing `renderer.render(lines, opts)` entry only for the still-active legacy public controller. Task 10 removes it in the same commit that switches the public API, so no final compatibility interface remains.

Update history to use `config.paths.data_dir`; remove all remaining reads of top-level `config.data_dir` and `config.cache_dir`.

- [ ] **Step 8: Run session and complete tests**

Run: `make test FILE=test_session.lua`

Run: `make test FILE=test_session_integration.lua`

Run: `make test-all`

Expected: all PASS.

- [ ] **Step 9: Commit the session architecture**

```bash
git add lua/ghost-reader/session.lua lua/ghost-reader/renderer/init.lua lua/ghost-reader/history.lua tests/test_session.lua tests/test_session_integration.lua
git commit -m "refactor: centralize ghost reader session lifecycle"
```

### Task 10: Replace the public API and remove legacy controllers

**Files:**
- Replace: `lua/ghost-reader/init.lua`
- Replace: `plugin/ghost-reader.lua`
- Delete: `lua/ghost-reader/reader/init.lua`
- Delete: `lua/ghost-reader/reader/statusline.lua`
- Delete: `lua/ghost-reader/renderer/sparse_notes.lua`
- Delete: `lua/ghost-reader/stealth/init.lua`
- Delete: `lua/ghost-reader/stealth/boss_key.lua`
- Delete: `lua/ghost-reader/stealth/presets.lua`
- Delete: `lua/ghost-reader/stealth/statusline.lua`
- Create: `tests/test_public_api.lua`
- Create: `tests/test_commands.lua`

**Interfaces:**
- Consumes: `config`, `session`, `keymaps`, `history`.
- Produces: public `setup`, `open`, `open_statusline`, `select_book(preferred_mode)`, `toggle_controls`, `toggle_hide`, `toc`, and `close`; new command set from the design.

- [ ] **Step 1: Write public facade and command tests**

```lua
it("registers only the new command set", function()
  vim.cmd("runtime plugin/ghost-reader.lua")
  for _, name in ipairs({
    "GhostReader", "GhostReaderStatusline", "GhostReaderControl",
    "GhostReaderHide", "GhostReaderToc", "GhostReaderClose",
  }) do
    assert.equal(2, vim.fn.exists(":" .. name))
  end
  assert.equal(0, vim.fn.exists(":GhostReaderBoss"))
  assert.equal(0, vim.fn.exists(":GhostReaderRestore"))
end)
```

In `tests/test_public_api.lua`, define these named cases:

- `setup installs globals idempotently`: call setup twice and assert every configured lhs still has exactly the expected single `<Plug>` mapping.
- `open_statusline starts statusline mode`: assert `session.start(path, "statusline")`.
- `select_book resumes a visible inactive session`: assert controls become active without opening a picker.
- `select_book restores a hidden session`: stub `vim.ui.select` to fail if called and assert session restore.
- `preferred statusline mode skips the mode picker`: call `select_book("statusline")`, select a path, and assert one `session.start(path, "statusline")` call.
- `mode picker cancellation does nothing`: invoke the selection callback with nil and assert no session start.
- `toc delegates to session`: assert one `session.toc()` call.

- [ ] **Step 2: Run tests and verify old API failures**

Run: `make test FILE=test_public_api.lua`

Run: `make test FILE=test_commands.lua`

Expected: FAIL because the old facade directly inspects reader/statusline state and registers boss/restore commands.

- [ ] **Step 3: Implement the small public facade**

`setup` calls `config.setup`, ensures configured directories, calls `session.configure`, and calls `keymaps.setup`. Every public operation lazily calls setup when needed and delegates to session.

`select_book(preferred_mode)` follows this order:

1. Restore a hard-hidden session.
2. Enter controls for a visible session that has controls inactive.
3. Otherwise show history plus `+ 输入新路径...`.
4. After a path is selected, start `preferred_mode` immediately when it is non-nil; otherwise show `Buffer overlay` and `Statusline`.
5. Cancellation at either picker performs no action.

- [ ] **Step 4: Register the new commands and delete legacy modules**

Register the six commands from the design. `GhostReaderHide` toggles hide/restore. Remove the legacy `renderer.render` entry, old controllers, sparse-notes renderer, and stealth modules after `rg` confirms no new module requires them.

- [ ] **Step 5: Run focused tests and scan for legacy code**

Run: `make test FILE=test_public_api.lua`

Run: `make test FILE=test_commands.lua`

Run: `rg -n "GhostReaderBoss|GhostReaderRestore|stealth%.boss_key|reader%.state|reader_statusline%.state|sparse_notes" lua plugin`

Expected: tests PASS and ripgrep returns no matches.

Run: `make test-all`

Expected: all PASS.

- [ ] **Step 6: Commit the breaking public API**

```bash
git add lua/ghost-reader/init.lua plugin/ghost-reader.lua tests/test_public_api.lua tests/test_commands.lua
git add -u lua/ghost-reader/reader lua/ghost-reader/renderer/sparse_notes.lua lua/ghost-reader/stealth
git commit -m "refactor: replace ghost reader public lifecycle"
```

### Task 11: Rewrite documentation and perform final verification

**Files:**
- Modify: `README.md`
- Replace: `docs/ghost-reader.txt`
- Modify: `docs/neovim-basics.md` only where it names removed modules or keys
- Modify: `docs/lua-concepts.md` only where it names removed modules or keys

**Interfaces:**
- Consumes: final public API, commands, configuration, controls, and hide behavior.
- Produces: install example and help documentation with no legacy compatibility guidance.

- [ ] **Step 1: Rewrite the README around the two user-facing modes**

Document:

- overlay as the default real-Buffer extmark mode;
- statusline as the one-line float;
- mirror as automatic fallback;
- global mappings and shared control mappings;
- `gh` hard hide and `<Esc>` control exit;
- mode-aware automatic hide behavior;
- the exact new `opts` schema from the design;
- the six supported commands;
- Neovim 0.10+, Plenary only for tests, and unzip only for EPUB;
- visual concealment is not a security boundary.

- [ ] **Step 2: Rewrite help tags and remove stale tutorial references**

Use sections for setup, commands, overlay, statusline, controls, stealth events, configuration, and troubleshooting. Remove all examples using `<leader>go`, `J/K`, `]c/[c`, `<Esc><Esc>`, boss/restore commands, and sparse notes.

- [ ] **Step 3: Verify documentation and source agree**

Run:

```bash
rg -n "sparse_notes|GhostReaderBoss|GhostReaderRestore|<leader>go|<leader>gq|<leader>gt|<Esc><Esc>|\]c|\[c" \
  README.md docs/ghost-reader.txt docs/neovim-basics.md docs/lua-concepts.md lua plugin
```

Expected: no legacy matches outside the historical design document that explicitly states they are removed.

Run:

```bash
rg -n "GhostReaderControl|GhostReaderHide|<leader>rr|<leader>rm|next_content|renderer = \"overlay\"" README.md docs/ghost-reader.txt lua plugin
```

Expected: the new names appear in both documentation and implementation.

- [ ] **Step 4: Run the full verification matrix**

Run: `make test-runner-check`

Expected: PASS and confirms a deliberate failing test returns non-zero.

Run: `make test-all`

Expected: every test PASS.

Run: `git diff --check`

Expected: no whitespace errors.

Run a clean headless smoke test:

```bash
env XDG_CACHE_HOME=/tmp/ghost-reader-final/cache \
    XDG_DATA_HOME=/tmp/ghost-reader-final/data \
    XDG_STATE_HOME=/tmp/ghost-reader-final/state \
    nvim --clean --headless \
    --cmd "set rtp^=/home/ming/workspace/Tools/hidden-reading" \
    -c "runtime plugin/ghost-reader.lua" \
    -c "lua require('ghost-reader').setup({ stealth = { silent = true } })" \
    -c "lua assert(vim.fn.exists(':GhostReaderHide') == 2)" \
    -c "qa!"
```

Expected: exit 0 with no Lua errors.

- [ ] **Step 5: Review the final diff without touching unrelated artifacts**

Run: `git status --short --branch`

Expected: only intended tracked refactor changes plus the user's pre-existing untracked architecture files and log.

Run: `git diff --stat de6d67e`

Expected: changes are limited to Ghost Reader source, tests, Makefile, and documentation described by this plan.

- [ ] **Step 6: Commit documentation**

```bash
git add README.md docs/ghost-reader.txt docs/neovim-basics.md docs/lua-concepts.md
git commit -m "docs: document overlay reader controls"
```

## Final Review Gate

After Task 11, run `superpowers:requesting-code-review` against the complete branch diff. Address all correctness findings, rerun `make test-runner-check`, `make test-all`, the clean headless smoke test, and `git diff --check`, then use `superpowers:verification-before-completion` before reporting completion.
