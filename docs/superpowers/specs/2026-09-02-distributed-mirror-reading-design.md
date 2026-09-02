# Distributed Mirror Reading Design

Date: 2026-09-02

## Context

The real-buffer mirror renderer fixed buffer identity and hide/restore confusion, but its current viewport-centered layout is too concentrated. It also moves the real cursor onto the active virtual-text row while using priority `90`. The user's gitsigns configuration enables current-line blame at priority `100`, so blame text is drawn after Ghost Reader and can cover the active reading line.

The configuration migration also removed `buffer.preset` as a hard error. Existing user configurations that still contain `preset = "random"` therefore fail during `setup()` even though the setting no longer affects rendering.

## Goals

- Make book content look like sparse code comments distributed throughout the real buffer.
- Let `j` and `k` move the real cursor directly between content blocks.
- Keep block positions stable while navigating within one rendered batch.
- Reuse the same slots for the next or previous batch at batch boundaries.
- Prevent gitsigns blame and ordinary diagnostic virtual text from covering reading blocks.
- Make hard hide, stop, buffer migration, and window migration remove the presentation immediately and restore the user's code view.
- Add explicit density and block-size configuration with conservative defaults.
- Accept the obsolete `buffer.preset` option as a no-op compatibility key instead of failing setup.

## Non-goals

- Writing book text into real buffer lines.
- Disabling, reconfiguring, or calling APIs from gitsigns or another decoration plugin.
- Making virtual text searchable, yankable, or persistent on disk.
- Treating the visual disguise as a security boundary.
- Supporting multiple simultaneous Ghost Reader sessions.
- Changing statusline mode, book parsing, or progress-file formats.

## Decision

Mirror will use a window-scoped decoration provider that emits ephemeral `virt_text` extmarks over precomputed buffer rows. The renderer will keep the real buffer and window active, but its presentation will exist only in the target window's redraw cycle. This prevents the same book text from appearing in another window that happens to display the same buffer and eliminates persistent extmarks that could survive a lifecycle mistake.

The renderer will precompute all layout, wrapped strings, and navigation metadata outside redraw callbacks. The provider will only look up visible rows and emit prepared virtual text. It will not parse, wrap, navigate, mutate options, or report errors during redraw.

## Content block model

A content block is the unit of mirror navigation. One logical book line is wrapped to the target window's usable text width, then split into slices of at most `max_lines_per_block` display lines. A long paragraph can therefore produce multiple consecutive content blocks. A short paragraph produces one block.

For mirror mode:

- `segment_count(ctx, text)` returns the number of content blocks produced by the wrapped logical line.
- `segment_text(ctx, text, index)` returns the display-line slice for one block as a list of strings.
- The session continues to store a canonical `{ chapter_index, line_index, segment_index }` position. Here `segment_index` identifies a content block rather than a single screen line.
- `frame.blocks` remains the batch interface. In mirror mode, each block's `text` may be a list of display lines; statusline mode continues to use a string.

This keeps the existing navigation and progress model while changing mirror navigation from screen-line steps to content-block steps.

## Distributed layout

The buffer is divided into fixed regions of `region_lines` real lines. Eligible content-block slots are generated across the whole buffer, subject to the following rules:

1. At most `max_blocks_per_region` block anchors are selected in each region.
2. A block uses one consecutive real row per display line, up to `max_lines_per_block`.
3. Adjacent blocks are separated by at least `min_gap_lines` real rows.
4. The first and last `edge_padding` rows are avoided when the buffer is large enough.
5. Rows hidden inside closed folds are not selected.
6. No batch exceeds `max_total_blocks`, even in a very large file.
7. When the total cap is smaller than the available regional capacity, regions are sampled evenly across the full buffer rather than filled from the top.

Slot generation is deterministic for a given buffer shape and configuration. Moving between blocks does not move or reshuffle content. Crossing a batch boundary reuses the same slots with the next or previous sequence of book blocks.

Very small buffers degrade safely: edge padding and gaps are relaxed before reducing a block below one line. If at least one real row is eligible, mirror renders at least one block. Unsupported and zero-capacity targets remain hard-hidden.

## Default configuration

```lua
buffer = {
  layout = {
    region_lines = 50,
    max_blocks_per_region = 3,
    max_lines_per_block = 2,
    min_gap_lines = 6,
    max_total_blocks = 12,
    edge_padding = 2,
  },
  virt_text_priority = 1000,
}
```

The defaults allow at most six overlaid reading lines per 50 real lines and cap a batch at 12 blocks. This provides useful reading density without filling long files with implausible comments.

All layout values and `virt_text_priority` must be positive integers, except `edge_padding`, which may be zero. `max_lines_per_block` must fit within a region after padding. Impossible combinations fail configuration validation with the full option path.

The existing `buffer.style`, `buffer.light`, and `buffer.strong` keys remain accepted for compatibility during this change. When an explicit `buffer.layout` is absent, explicitly supplied legacy style values are normalized to an equivalent approximate density: `max_consecutive_lines` becomes the block line limit and `visible_lines` determines the regional block count. New documentation uses only `buffer.layout`.

`buffer.preset` is recognized, removed before strict unknown-key validation, and ignored without notification. Other unknown keys remain errors. Silent handling is intentional because emitting a warning during plugin setup would undermine the plugin's discreet behavior.

## Rendering and decoration isolation

The renderer installs one decoration provider for its named namespace. Its `on_win` callback returns immediately unless all of these conditions hold:

- a mirror session is visible;
- the callback window and buffer match the active mirror target;
- the target remains valid and loaded.

For matching redraws, the callback emits only the prepared rows intersecting the requested visible range. Each ephemeral mark uses:

- `virt_text_pos = "overlay"`;
- `virt_text_hide = true`;
- `hl_mode = "replace"`;
- the configured priority, defaulting to `1000`;
- comment-like text padded through the usable text width.

Neovim draws higher-priority virtual text last. The default therefore places Ghost Reader above gitsigns current-line blame priority `100` without altering gitsigns state. Padding prevents lower-priority end-of-line annotations or underlying code from leaking through the block. Only reading rows are covered.

Usable width subtracts the window's text offset for number, sign, and fold columns. Each rendered line follows the target filetype's comment syntax and borrows the target row's leading indentation when it fits, making the overlay resemble an ordinary local comment. All reading text uses the normal comment highlight; the real cursor and the user's native cursorline provide the active indication.

## Navigation and batching

The renderer records an ordered list of block anchors and their canonical book positions. `j` and `k` continue to dispatch `next_content` and `prev_content` through the session:

- If the next position exists in the current batch, rendering keeps the same slot assignment and moves the real cursor to that block's first row.
- At the last block, `j` builds the next batch, reuses the slot rows, and activates its first block.
- At the first block, `k` builds the preceding batch, reuses the slots, and activates its last block.
- Page and chapter commands build a new batch and activate its first block.

Forward batches use the existing forward peek behavior. Reverse boundary navigation uses a matching backward peek operation that collects at most the renderer capacity and returns the blocks in reading order, ending at the requested position. This prevents `k` at a batch boundary from producing a mostly overlapping forward batch or activating the wrong slot.

The cursor column is clamped to the first display cell of the virtual comment. Cursor movement uses the target window directly and never makes another window current.

Window resize and layout-affecting changes schedule one guarded reflow. Reflow recalculates usable width and block slots while preserving the canonical book position. Scheduled work validates the session generation, visibility, buffer, and window before changing state.

## View preservation and hiding

Each visible mirror target owns a saved code view captured before the renderer first moves its cursor. The saved value includes the cursor, topline, left column, desired column, and related `winsaveview()` fields.

- Hard hide captures the active reading position, disables provider output, requests a redraw, detaches reader mappings, and restores the saved code view when the original target still exists.
- Restore adopts the currently active eligible buffer and window, captures their current code view as the new restoration point, rebuilds the same batch around the canonical book position, enables provider output, and jumps to the active block.
- Visible target migration restores the old target's saved view before adopting and capturing the new target.
- Insert enter disables provider output and restores the saved code view before the user can edit an underlying overlaid row. Insert leave captures the resulting code view as the new restoration point, then reflows and returns to the active reading block only if the session was visible before insertion.
- Stop disables provider output, redraws affected windows, restores the saved view, removes mappings and autocmds, and saves progress.

Provider state is disabled before any redraw or target transition. Cleanup is idempotent and skips deleted buffers or windows. The namespace may remain allocated for the lifetime of Neovim, but it holds no persistent extmarks after redraw.

## Error handling

- Configuration is validated before session or renderer state changes.
- Unsupported special buffers cause a hard hide without changing the current buffer.
- Layout and wrapping failures are caught outside redraw callbacks. The session detaches reader mappings, disables provider output, restores the saved code view when possible, and becomes hard-hidden.
- Decoration callbacks operate only on validated precomputed data and never notify, allocate session state, or invoke user/plugin APIs.
- A failed restore leaves the current buffer and window untouched and keeps the session hard-hidden.
- A stale scheduled callback or provider redraw cannot act on a replacement generation.

## Testing strategy

Implementation follows red-green-refactor. Tests are written and observed failing before production changes.

Pure layout tests will verify:

- regional density, total cap, minimum gaps, edge padding, and full-buffer distribution;
- deterministic slot reuse across navigation and batch replacement;
- safe degradation for short buffers and large blocks;
- exclusion of folded rows where window state permits it.

Renderer tests will verify:

- paragraphs wrap into blocks of at most the configured line count;
- prepared virtual text uses comment syntax, indentation, usable width, replacement highlighting, and configured priority;
- provider output is restricted to the active target window;
- the real buffer text, modified state, undo history, filetype, and tab identity do not change;
- navigation moves the cursor to block anchors without reshuffling them;
- hide and stop disable all output and are idempotent.

Session integration tests will verify:

- next/previous movement within a batch and across both batch boundaries;
- page and chapter navigation reuse slots;
- hide restores the original code cursor and view;
- restore uses the current buffer and returns to the same book position;
- visible buffer/window migration restores the old view and captures the new one;
- insert suspension and resize reflow preserve visibility and position correctly;
- gitsigns-like priority `100` virtual text cannot outrank default mirror marks;
- statusline mode remains unchanged.

Configuration tests will verify the new defaults and validation, legacy style normalization, ignored `buffer.preset`, and continued rejection of unrelated unknown keys. README and help documentation will describe the new layout controls and the fact that visual disguise is not a security boundary.

## Expected file changes

- Refactor `lua/ghost-reader/renderer/mirror.lua` around precomputed blocks, distributed slots, saved views, and window-scoped ephemeral virtual text.
- Update `lua/ghost-reader/session.lua` for block-oriented navigation boundaries, guarded mirror reflow, and view restoration during target migration.
- Extend `lua/ghost-reader/reader/navigate.lua` with bounded backward peeking for previous-batch construction.
- Update `lua/ghost-reader/config.lua` with layout defaults, validation, legacy normalization, and `buffer.preset` compatibility.
- Add a focused pure layout module if extracting slot generation keeps redraw code small and testable.
- Update mirror renderer, session integration, configuration, and regression tests.
- Update `README.md` and Neovim help documentation.
