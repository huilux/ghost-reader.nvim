# Real-Buffer Virtual-Text Reader Design

Date: 2026-09-02

## Context

The current `mirror` renderer opens an anonymous scratch buffer containing a copied code skeleton. That keeps book text out of the real file, but it also makes the scratch buffer the active Neovim buffer. Buffer tabs therefore stop representing the file the user considers active, and switching buffers leaves the session with a stale saved-buffer snapshot. Repeated hide and restore operations can then alternate between the scratch buffer and an older real buffer.

An earlier `overlay` renderer attached `virt_lines` to a real buffer. The new design keeps the important property of that approach—rendering on the real active buffer—but uses line-level `virt_text` overlays instead of adding virtual screen lines.

## Goals

- Keep the user's real file buffer active so buffer tabs, file names, and window state remain truthful.
- Display book content as comment-like lines without changing buffer text, modified state, undo history, diagnostics, or LSP input.
- Move a visible reading session cleanly when the user changes buffers or windows.
- Make hide and restore purely visual operations with no buffer replacement.
- Preserve the existing `mirror` and `statusline` user-facing mode names.
- Preserve the existing `light` and `strong` layout choices and reading navigation semantics.

## Non-goals

- Rendering inside terminal, help, prompt, quickfix, or other special buffers.
- Persisting virtual text in session files or on disk.
- Supporting multiple simultaneous reading sessions.
- Changing the statusline renderer or book parsing and progress formats.
- Modifying real buffer lines and later attempting to roll those edits back.

## Decision

`mirror` will become a real-buffer virtual-text renderer. Its implementation will attach extmarks with `virt_text_pos = "overlay"` to selected lines in the active normal file buffer. It will no longer create, display, or restore a scratch buffer.

The `mirror` name remains stable so existing mode selection and `reader.renderer = "mirror"` configurations continue to work. `statusline` remains the other selectable mode.

The old code-skeleton presets no longer participate in rendering. The `buffer.preset` setting and the unused preset renderer module will be removed because retaining a silently ignored option would make configuration misleading. The layout settings under `buffer.light` and `buffer.strong` remain supported.

## User-visible behavior

### Starting a session

Starting `mirror` mode in a loaded normal file buffer renders the current reading page over selected visible code lines. Neovim's current buffer, buffer tab, buffer name, filetype, cursor history, and window identity do not change.

Starting `mirror` mode directly from an unsupported special buffer fails without creating a partial session. The plugin reports that mirror reading requires a normal file buffer.

### Layout

Each rendered book segment is prefixed with the comment syntax for the current filetype. The renderer pads the virtual text through the visible window width so the underlying code on that screen line does not leak through the reading text.

- `light` places reading segments in centered groups of consecutive visible lines. `max_consecutive_lines` limits each group, with a one-line gap between groups.
- `strong` distributes the groups across the visible range, producing more code between reading segments.

Only unique, currently visible buffer rows are used as anchors. A short buffer or small window may therefore show fewer segments than the configured `visible_lines`; navigation advances by the number of segments the renderer can actually display.

Long book lines continue to be split by display width before rendering. Prefix and padding calculations use display width rather than Lua byte length so Chinese and other wide characters remain aligned.

### Navigation

`j` and `k` continue to move between reading segments. The cursor moves to the real buffer row carrying the active virtual-text segment. Page and chapter navigation update the extmarks in place and never replace the real buffer.

### Buffer and window changes

While mirror reading is visible:

1. Leaving the current target clears Ghost Reader extmarks and restores the buffer-local mappings captured on that target.
2. Entering another eligible normal file buffer updates both the session target and renderer context to the new buffer and window.
3. The current reading page is rendered on the new target and the reading mappings are attached there.

The canonical book position does not change during this migration. No saved “original buffer” is involved, so subsequent hide and restore operations cannot jump back to an older buffer.

Entering an unsupported special buffer clears the old decorations, detaches reading mappings, and changes the session to hard-hidden. Returning to an eligible file does not reveal the book automatically; the user restores it explicitly with `<Esc><Esc>`.

### Hiding, restoring, and editing

Hard hide clears Ghost Reader's namespace from the current target and detaches reading mappings. It does not call `nvim_win_set_buf` or otherwise navigate.

Restore first adopts the current buffer and window. If they are eligible, it redraws the current page and reattaches mappings. If they are unsupported, restore returns false and the session remains hard-hidden.

To prevent invisible edits beneath an overlay, `InsertEnter` temporarily clears mirror decorations without leaving the reading session or changing its hard-hidden state. `InsertLeave` redraws only when the session was visible before insertion. A session that was already hard-hidden remains hidden across the insert cycle.

Stopping clears decorations from every buffer touched by the session, removes autocmds and mappings, saves reading progress, and leaves the current buffer and window unchanged.

## Architecture

### Session ownership

`session.lua` remains the owner of lifecycle, visibility, canonical reading position, the current target buffer/window, mappings, and autocmds.

It gains one internal target-adoption operation that:

1. Reads the current Neovim buffer and window.
2. Checks renderer eligibility.
3. Detaches mappings and asks the renderer to clear the previous target when the target changed.
4. Updates `active.target_buf`, `active.target_win`, `active.ctx.target_buf`, and `active.ctx.target_win` together.
5. Renders and attaches mappings only after all four target fields agree.

This keeps target state atomic and prevents the session and renderer from addressing different buffers.

Autocmd callbacks retain the existing generation guard and `transitioning` guard so callbacks from replaced sessions or plugin-driven cleanup cannot mutate the active session.

### Mirror renderer

`renderer/mirror.lua` retains the existing renderer interface:

- `supports(buf, win)` accepts only a valid, loaded normal buffer displayed in the target window.
- `start(ctx)` creates the namespace and highlight groups but does not create a buffer.
- `render(ctx, frame)` calculates visible anchors, clears prior marks on the target, writes virtual-text extmarks, records anchor-to-book-position mappings, and activates the first segment.
- `hide(ctx)` clears marks from the current target.
- `restore(ctx, frame)` renders the frame on the already-adopted target.
- `stop(ctx)` clears marks from all touched valid buffers.
- `reader_buf(ctx)` returns `ctx.target_buf`.
- `page_size(ctx)`, `segment_count(ctx, text)`, and `segment_text(ctx, text, index)` derive capacity and wrapping from the current target window.

Renderer state records the namespace, touched buffers, rendered rows, rendered blocks, book-position-to-row lookup, and active row. It contains no saved buffer, saved view, skeleton, or scratch-buffer handle.

### Virtual-text rendering

Each anchor receives one extmark with:

- `virt_text` containing the filetype comment prefix, one wrapped book segment, any required comment suffix, and display-width padding;
- `virt_text_pos = "overlay"` so the real line is not shifted;
- `virt_text_hide = true` so selection and horizontal scrolling do not produce misleading mixed text;
- a priority below completion and message UI layers;
- `GhostReaderMirrorActive` for the active segment and `Comment` for the remaining segments.

The renderer clears only its own namespace. It never removes diagnostics, Git signs, semantic tokens, or another plugin's decorations.

### Keymaps

The existing reversible keymap capture remains in use. On target migration, mappings are detached from the previous buffer before they are attached to the new buffer. Hard hide and stop restore the most recently captured mappings exactly once.

Global mappings remain global, so `<Esc><Esc>` can restore a hidden session from a different eligible file buffer.

## Failure handling

- Invalid or unloaded targets are rejected before any renderer state or mapping changes are committed.
- If target migration cannot render, the new target remains the user's current buffer, Ghost Reader stays hard-hidden, and no reading mappings remain attached.
- Clearing an already-cleared namespace and stopping an already-stopped renderer are idempotent.
- Deleted touched buffers are skipped during cleanup.
- Scheduled autocmd work verifies the active generation, lifecycle, visibility, and target again before rendering.
- A rendering failure never changes real buffer contents or navigates to another buffer.

## Compatibility and documentation

The public mode name `mirror`, commands, global mappings, reader mappings, progress files, and statusline mode stay compatible.

Documentation will describe mirror as a real-buffer virtual-text reader rather than an anonymous scratch-buffer reader. Configuration examples will remove `buffer.preset`. The obsolete code-skeleton preset module and tests will be removed only after a reference scan proves no remaining consumer exists.

## Testing strategy

Implementation follows test-driven development. Regression tests will be written and observed failing before production changes.

Renderer tests will verify:

- virtual text is attached to the real target buffer;
- buffer lines, name, filetype, modified state, undo history, and window buffer do not change;
- no scratch buffer is created;
- light and strong anchor layouts use unique visible rows;
- comment prefixes, suffixes, wide-character wrapping, and padding are correct;
- navigation activates the expected real row;
- hide, restore, and stop clear only Ghost Reader decorations and are idempotent;
- special buffers are rejected;
- short buffers and narrow windows reduce page capacity safely.

Session integration tests will verify:

- switching from buffer A to buffer B removes A's marks and mappings and renders at the same book position on B;
- repeated hide and restore stays on B and never returns to A;
- switching windows updates both target fields consistently;
- entering a special buffer hard-hides without navigating;
- restore adopts the current eligible buffer;
- insert mode soft-clears and redraws only a previously visible session;
- stopping after multiple migrations clears all touched buffers;
- statusline behavior remains unchanged.

Configuration, public API, renderer registry, README, and help-file tests will be updated for the removed preset option and the new mirror behavior. Focused tests will run first, followed by the complete suite.

## Expected file changes

- Rewrite `lua/ghost-reader/renderer/mirror.lua` around real-buffer virtual text.
- Update `lua/ghost-reader/session.lua` for target adoption and mirror migration autocmds.
- Update `lua/ghost-reader/config.lua` to remove the obsolete preset setting.
- Remove `lua/ghost-reader/renderer/presets.lua` after confirming it has no consumer.
- Update mirror, session integration, config, renderer, and public API tests as required.
- Update `README.md`, `docs/ghost-reader.txt`, and relevant concept documentation.
