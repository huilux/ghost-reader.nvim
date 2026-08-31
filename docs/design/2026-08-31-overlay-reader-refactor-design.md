# Ghost Reader Overlay Refactor Design

Date: 2026-08-31

## Summary

Ghost Reader will be rebuilt around one reading session, one action vocabulary, and two user-facing reading modes:

- `overlay`: the default Buffer reading mode. It stays in the user's real code Buffer and displays book content with extmark virtual lines.
- `statusline`: the existing one-line floating reader, rebuilt as another view of the same session.

An internal `mirror` renderer remains only as an automatic fallback for Buffers where an overlay is unsuitable. This refactor is intentionally breaking. It will not preserve the old `sparse_notes` mode, old configuration keys, old boss-key commands, or old key bindings.

## Goals

1. Make Buffer reading substantially harder to distinguish from normal editing.
2. Give shared actions the same keys and meaning in overlay and statusline modes.
3. Prevent temporary reading controls from destroying or leaking user mappings.
4. Make hide and restore operations immediate, quiet, and visually stable.
5. Replace the current distributed module state with one explicit session lifecycle.
6. Make all rendering and cleanup operations idempotent and testable.

## Non-goals

- Backward compatibility with the current configuration or commands.
- EPUB parser improvements, storage format changes, or history encryption.
- Transforming prose into plausible source-code semantics.
- Hiding content from screen recording or an observer who is already reading the displayed text.

## User-facing modes

### Overlay mode

Overlay mode remains in the current real code Buffer and Window. It never copies the Buffer, changes its name or filetype, writes book text into its lines, or replaces the statusline.

The renderer places at most three book-content blocks in the visible range with an extmark namespace and `virt_lines`. Each block uses the current filetype's comment prefix and a highlight linked to `Comment`. The default style does not add repeated `TODO`, `FIXME`, diagnostic icons, or bright active-state colors.

The three anchors are selected near 25%, 50%, and 75% of the visible range. Closed folds, invalid rows, and the first and last two visible rows are avoided. Anchor positions stay stable until the reader changes page, the Window is resized, or the visible range no longer contains them.

Long source lines are irrelevant because the book content is virtual. Book content is wrapped to the available Window width after accounting for indentation and the filetype comment prefix. One logical book line can therefore occupy multiple virtual screen lines while remaining one content block.

### Statusline mode

Statusline mode continues to show one content segment in a non-focusable floating Window. It uses the same session position and actions as overlay mode. Long logical book lines may be divided into display segments because the Window is one line high.

Statusline mode supports automatic advance independently of the reading control layer. Leaving controls restores ordinary editing keys but does not pause playback. Automatic advance pauses only while the session is hidden or stopped.

### Mirror fallback

Mirror is an internal fallback, not a third selection in the normal mode picker. It is used when:

- the current Buffer has a non-empty `buftype`, such as terminal, help, prompt, or quickfix;
- there is no valid normal Window or loaded source Buffer;
- overlay setup raises an unrecoverable error; or
- the user explicitly configures `reader.renderer = "mirror"`.

Mirror chooses a source skeleton once per session and reuses it. It does not rescan all loaded Buffers on every page. It keeps its scratch Buffer unnamed instead of impersonating an existing real path or exposing a plugin-specific URI, and it shares the same action and control mappings as the other modes.

## Reading actions and keys

Shared actions use the same keys whenever the reading control layer is active:

| Action | Default key | Meaning |
|---|---|---|
| `next_content` | `j` | Move to the next visible content unit |
| `prev_content` | `k` | Move to the previous visible content unit |
| `next_page` | `<C-f>` | Advance by the current mode's page batch |
| `prev_page` | `<C-b>` | Move back by the current mode's page batch |
| `next_chapter` | `]]` | Go to the next chapter |
| `prev_chapter` | `[[` | Go to the previous chapter |
| `toc` | `t` | Open the table of contents |
| `progress` | `g%` | Show reading progress without including the book title |
| `hide` | `gh` | Hard-hide the active session |
| `close` | `q` | Close the active session and save progress |
| `help` | `?` | Show the active control bindings |
| `exit_controls` | `<Esc>` | Leave controls and restore ordinary mappings |

Statusline adds three actions while the same control layer is active:

| Action | Default key |
|---|---|
| `toggle_auto` | `a` |
| `faster` | `+` |
| `slower` | `-` |

`next_content` always means the next unit the current view can display completely. In overlay and mirror modes, that is one wrapped logical book line. In statusline mode, it may be the next segment of the same logical line. The session position therefore contains `chapter_index`, `line_index`, and `segment_index`.

Page size is view-specific but the action remains a batch movement. Overlay and mirror use `reader.visible_blocks`; statusline uses `statusline.page_step`.

## Global keys and commands

Default global mappings are:

| Action | Default key |
|---|---|
| Open or restore | `<leader>rr` |
| Start statusline mode | `<leader>rs` |
| Enter or exit reading controls | `<leader>rm` |
| Hide or restore | `<leader>rh` |
| Table of contents | `<leader>rt` |
| Close the active session | `<leader>rq` |

Every operation also has a `<Plug>` mapping so users can replace global mappings without depending on Lua callbacks.

The command set becomes:

- `:GhostReader [path]`
- `:GhostReaderStatusline [path]`
- `:GhostReaderControl`
- `:GhostReaderHide`
- `:GhostReaderToc`
- `:GhostReaderClose`

`:GhostReaderBoss` and `:GhostReaderRestore` are removed. `:GhostReaderHide` is a toggle with session-aware hide and restore behavior.

## Control-layer behavior

Overlay and mirror enter the reading control layer when started. Statusline does not take over ordinary editing keys until the user runs `GhostReaderControl` or presses `<leader>rm`.

Pressing `<Esc>` exits the control layer without closing the session. The overlay can remain visible while normal mappings are restored. Entering the control layer again installs the same shared bindings. Hard hide uses `gh`; it deliberately does not share an `<Esc>` prefix, so exit and hide never depend on mapping timeout behavior.

The keymap manager snapshots every Buffer-local mapping it replaces with `maparg()` and restores the complete mapping dictionary with `mapset()`. Leaving controls, hard-hiding, closing, or encountering an error restores those exact mappings in the Buffer where they were captured. When no prior mapping existed, cleanup deletes only the plugin mapping. Cleanup never uses `buffer = 0` to guess the target Buffer.

Each control mapping also targets a named `<Plug>` action. Configuration values may be set to `false` to disable individual defaults.

## Session lifecycle

One `session.lua` module owns the active session. The bookshelf becomes stateless and only returns parsed books.

Session state has three orthogonal parts instead of one ambiguous enum:

```text
lifecycle:  IDLE -> ACTIVE -> STOPPING -> IDLE
visibility: VISIBLE | SOFT_HIDDEN | HARD_HIDDEN
controls:   INACTIVE | ACTIVE
```

Starting a session sets `lifecycle = ACTIVE` and `visibility = VISIBLE`. Overlay and mirror also start with `controls = ACTIVE`; statusline starts with `controls = INACTIVE`. Soft hide remembers whether controls were active and returns to that state. Hard hide always makes controls inactive and requires an explicit restore.

Explicit restore returns overlay and mirror to active controls because they are dedicated reading views. Statusline restore makes the float visible again but leaves controls inactive so ordinary editing keys are not captured unexpectedly.

The session owns:

- book and source path;
- mode and active renderer;
- `chapter_index`, `line_index`, and `segment_index`;
- control-layer state and captured mappings;
- hidden state and hide reason;
- timers, autocmd group, extmark namespace, Buffer, and Window handles;
- the original Window, Buffer, cursor, and view needed by mirror fallback;
- configuration used for this session.

Only one reading session may exist. Starting a new book first parses and validates the new book. The existing session is stopped only after parsing succeeds, so an invalid path cannot destroy a valid reading session.

All stop, hide, and cleanup operations are idempotent.

## Hide policy

Hide behavior has two levels and is mode-aware.

### Soft hide

In overlay mode, `InsertEnter` clears extmarks and pauses visible reading without marking the session manually hidden. `InsertLeave` restores the overlay when the same Buffer and Window remain valid.

Soft hide does not restore or remove the control layer merely because Insert mode temporarily ignores Normal-mode mappings.

Statusline mode does not soft-hide on InsertEnter because its purpose is to remain readable while the user edits. Mirror fallback does not enter Insert mode in its scratch Buffer.

### Hard hide

The following events hard-hide every mode:

- the boss-key action;
- `FocusLost`.

Overlay additionally hard-hides on `BufLeave` and `WinLeave` because its extmarks belong to one source context. Restoring from another eligible normal Buffer attaches the overlay to that current Buffer; it does not force the user back to the old Window.

Statusline does not hide on `BufLeave` or `WinLeave`. If its control layer was active, Buffer leave exits controls and restores mappings in the old Buffer while the float and automatic playback continue. Controls can then be entered again in the new Buffer.

Hard hide clears extmarks or closes the statusline Window, stops automatic advance, exits the control layer, and restores captured mappings. It never restores automatically. The user must invoke open/restore or hide/restore explicitly.

Overlay hard hide is a namespace clear and does not switch Buffers. Mirror hard hide returns to the saved real Buffer and view. Statusline hard hide closes only its float and Buffer.

`QuitPre` saves progress and performs best-effort cleanup without changing the visible Buffer during shutdown.

## Privacy-oriented behavior

With `stealth.silent = true`, which is the default:

- automatic notifications do not contain book names or paths;
- start, hide, restore, speed, and mode changes do not write ordinary messages;
- progress output includes only chapter, position, and percentage;
- no fake file path or book title is assigned to a Buffer;
- overlay text never enters Buffer lines, undo history, search results, registers, yank operations, or Git diffs.

Errors that prevent an operation still produce a concise error notification because silent failure would leave the user unable to diagnose the plugin.

## Configuration

The new configuration is the only supported schema:

```lua
{
  reader = {
    renderer = "overlay",
    visible_blocks = 3,
    mirror_fallback = true,
  },
  statusline = {
    interval = 3000,
    autoplay = true,
    page_step = 5,
  },
  stealth = {
    hide_on_focus_lost = true,
    silent = true,
    overlay = {
      hide_on_insert = true,
      hide_on_buf_leave = true,
      hide_on_win_leave = true,
    },
  },
  paths = {
    cache_dir = nil, -- defaults to stdpath("cache") .. "/ghost-reader/"
    data_dir = nil,  -- defaults to stdpath("data") .. "/ghost-reader/"
  },
  keymaps = {
    global = {
      open = "<leader>rr",
      statusline = "<leader>rs",
      control = "<leader>rm",
      hide = "<leader>rh",
      toc = "<leader>rt",
      close = "<leader>rq",
    },
    controls = {
      next_content = "j",
      prev_content = "k",
      next_page = "<C-f>",
      prev_page = "<C-b>",
      next_chapter = "]]",
      prev_chapter = "[[",
      toc = "t",
      progress = "g%",
      hide = "gh",
      close = "q",
      help = "?",
      exit_controls = "<Esc>",
    },
    statusline = {
      toggle_auto = "a",
      faster = "+",
      slower = "-",
    },
  },
}
```

Configuration validation rejects unknown renderer values, invalid mode values, non-positive intervals, invalid page sizes, non-string/non-false key bindings, and non-string path overrides during `setup()`.

There is no translation for `boss_key`, the old flat `keymaps` table, `statusline.mode`, or `sparse_notes` options.

## Module boundaries

The target modules are:

- `session.lua`: state machine, ownership, orchestration, cleanup.
- `actions.lua`: stable action names and dispatch into the active session.
- `keymaps.lua`: global `<Plug>` mappings and reversible control-layer mappings.
- `renderer/overlay.lua`: extmark virtual-line rendering.
- `renderer/mirror.lua`: stable scratch-buffer fallback.
- `renderer/statusline.lua`: statusline view adapter and timer behavior.
- `reader/navigate.lua`: pure movement of canonical reading position.
- `bookshelf/init.lua`: stateless parser selection and result validation.
- `config.lua`: defaults and strict validation.

The legacy `reader/statusline.lua`, `stealth/boss_key.lua`, `stealth/statusline.lua`, and facade state in `stealth/init.lua` are removed. Presets remain available only to `renderer/mirror.lua` under `renderer/`.

The public `init.lua` becomes a small facade over session actions and selection UI. It does not inspect renderer or reader internal fields.

## Data flow

Opening a book follows this order:

1. Validate configuration and requested mode.
2. Resolve and parse the book without changing the current session.
3. Validate that at least one readable chapter exists.
4. Stop the previous session, if any.
5. Create the new canonical session position from saved progress.
6. Select overlay or mirror for Buffer reading, or statusline when requested.
7. Register one session autocmd group.
8. Render the initial view.
9. Enter controls automatically only for overlay and mirror.

Movement dispatches an action to the session, updates canonical position through `navigate.lua`, and asks the active view to render. Views do not own book position.

## Error handling

- Parsing failures leave the current valid session untouched.
- An overlay setup failure attempts mirror fallback once when enabled.
- A renderer failure hard-hides and cleans renderer-owned resources before notifying the user.
- Cleanup uses protected calls only around resources that may already be invalid; errors are not silently ignored during normal setup or rendering.
- Timer callbacks check the session generation so callbacks from a stopped session cannot mutate a replacement session.
- Reaching the end of a book stops automatic advance instead of rearming an idle timer indefinitely.

## Tests

The test runner must wait for all Plenary tests and return a non-zero exit code when any test fails. Tests will cover:

### Unit tests

- strict configuration validation;
- canonical navigation, page batches, chapter boundaries, and segments;
- action dispatch with no session, hidden session, and active session;
- parser errors for missing files and empty books;
- TOC selection using `entry.index` rather than selection position.

### Headless integration tests

- overlay rendering does not change `nvim_buf_get_lines`, `modified`, undo history, filetype, Buffer name, or statusline;
- hide clears all Ghost Reader extmarks and restore recreates only the active session's extmarks;
- overlay InsertEnter/InsertLeave soft-hide behavior;
- overlay BufLeave/WinLeave and all-mode FocusLost/boss-key hard-hide behavior;
- statusline Buffer switching exits controls without hiding or stopping playback;
- exact restoration of pre-existing Buffer-local mappings;
- cleanup targets the original Buffer after the user changes Buffer;
- statusline stop removes its timer, float, Buffer, autocmds, and controls;
- `close()` closes either user-facing mode;
- starting an invalid book preserves the active valid session;
- mirror fallback uses a stable skeleton and restores the original view;
- automatic advance stops at end-of-book;
- repeated hide, restore, and stop calls are safe.

### Acceptance criteria

1. A byte-for-byte comparison of real Buffer lines before and after overlay reading is identical.
2. Overlay hide does not switch Buffer, Window, cursor, or view.
3. No user mapping is lost after any normal or error cleanup path.
4. Shared control keys perform the same user-level action in overlay and statusline modes.
5. No legacy boss-key or sparse-notes state remains reachable.
6. The complete test command reliably fails when a test is intentionally made to fail.

## Documentation changes

README and help documentation will be rewritten around overlay and statusline modes. They will document the breaking configuration schema, the control layer, automatic hide events, mirror fallback, and the fact that overlay content is visual concealment rather than a security boundary.

No migration section or compatibility example will be provided because the refactor deliberately replaces the old interface.
