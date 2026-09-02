local helpers = require("tests.helpers")
helpers.reset_modules()

local mirror = require("ghost-reader.renderer.mirror")
local buffer_seq = 0

local layout = {
  region_lines = 50,
  max_blocks_per_region = 3,
  max_lines_per_block = 2,
  min_gap_lines = 6,
  max_total_blocks = 12,
  edge_padding = 2,
}

local function make_context(line_count)
  vim.o.swapfile = false
  buffer_seq = buffer_seq + 1
  local target_buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(target_buf, "mirror-test-" .. buffer_seq .. ".lua")
  local lines = {}
  for i = 1, line_count or 100 do
    lines[i] = i == 1 and "  local line_" .. i .. " = " .. i or "local line_" .. i .. " = " .. i
  end
  vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, lines)
  vim.bo[target_buf].filetype = "lua"
  vim.bo[target_buf].modified = false

  local target_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(target_win, target_buf)
  vim.api.nvim_win_set_height(target_win, 12)
  vim.api.nvim_win_set_width(target_win, 80)
  vim.api.nvim_win_set_cursor(target_win, { math.min(18, #lines), 0 })

  return {
    target_buf = target_buf,
    target_win = target_win,
    config = { buffer = { layout = vim.deepcopy(layout), virt_text_priority = 1000 } },
    view_state = {},
    mode = "mirror",
    view_name = "mirror",
  }
end

local function block(line, text, active)
  return {
    chapter_index = 1,
    line_index = line,
    segment_index = 1,
    text = text,
    active = active,
  }
end

local function frame(position_line, blocks)
  return {
    position = { chapter_index = 1, line_index = position_line, segment_index = 1 },
    blocks = blocks,
  }
end

describe("renderer.mirror", function()
  it("wraps a paragraph into block-sized segments", function()
    local ctx = make_context(100)
    ctx.config.buffer.layout.max_lines_per_block = 2
    vim.api.nvim_win_set_width(ctx.target_win, 24)

    local count = mirror.segment_count(ctx, string.rep("word ", 30))
    assert.is_true(count > 1)
    local content = mirror.segment_text(ctx, string.rep("word ", 30), 1)
    assert.is_table(content)
    assert.is_true(#content >= 1 and #content <= 2)
  end)

  it("uses distributed slot count as page size", function()
    assert.equal(12, mirror.page_size(make_context(500)))
  end)

  it("draws prepared ephemeral virtual text only in its target window", function()
    local ctx = make_context(100)
    local peer_win = vim.api.nvim_open_win(ctx.target_buf, false, {
      relative = "editor",
      width = 40,
      height = 10,
      row = 1,
      col = 1,
      style = "minimal",
    })
    local captured_provider
    local marks = {}
    local original_provider = vim.api.nvim_set_decoration_provider
    local original_extmark = vim.api.nvim_buf_set_extmark
    vim.api.nvim_set_decoration_provider = function(namespace, provider)
      captured_provider = { namespace = namespace, callback = provider.on_win }
    end
    vim.api.nvim_buf_set_extmark = function(_, namespace, row, _, opts)
      if namespace == captured_provider.namespace and opts and opts.ephemeral then
        marks[#marks + 1] = { row = row, opts = opts }
      end
      return #marks
    end

    local ok, err = xpcall(function()
      assert.is_true(mirror.start(ctx))
      assert.is_true(mirror.render(ctx, frame(1, { block(1, { "first", "line" }, true) })))
      captured_provider.callback(captured_provider.namespace, ctx.target_win, ctx.target_buf, 0, 100)
      assert.is_true(#marks > 0)
      local mark = marks[1]
      assert.equal("overlay", mark.opts.virt_text_pos)
      assert.is_true(mark.opts.virt_text_hide)
      assert.equal("replace", mark.opts.hl_mode)
      assert.equal(1000, mark.opts.priority)
      assert.is_true(mark.opts.ephemeral)
      assert.equal("GhostReaderMirror", mark.opts.virt_text[1][2])

      marks = {}
      captured_provider.callback(captured_provider.namespace, peer_win, ctx.target_buf, 0, 100)
      assert.equal(0, #marks)
    end, debug.traceback)
    vim.api.nvim_set_decoration_provider = original_provider
    vim.api.nvim_buf_set_extmark = original_extmark
    if captured_provider then
      vim.api.nvim_set_decoration_provider(captured_provider.namespace, { on_win = captured_provider.callback })
    end
    vim.api.nvim_win_close(peer_win, true)
    if not ok then error(err) end
  end)

  it("keeps slot rows stable, moves to the active anchor, and restores the view", function()
    local ctx = make_context(100)
    vim.api.nvim_win_set_cursor(ctx.target_win, { 18, 7 })
    local before_lines = vim.api.nvim_buf_get_lines(ctx.target_buf, 0, -1, false)
    local before_name = vim.api.nvim_buf_get_name(ctx.target_buf)
    local before_filetype = vim.bo[ctx.target_buf].filetype
    local saved_view = vim.api.nvim_win_call(ctx.target_win, vim.fn.winsaveview)
    local saved_buf = vim.api.nvim_win_get_buf(ctx.target_win)
    local blocks = {
      block(1, { "one" }, true),
      block(2, { "two" }),
      block(3, { "three" }),
    }

    assert.is_true(mirror.render(ctx, frame(1, blocks)))
    local rows = vim.deepcopy(ctx.view_state.mirror.reader_rows)
    assert.equal(rows[1], vim.api.nvim_win_get_cursor(ctx.target_win)[1])
    assert.equal(0, vim.api.nvim_win_get_cursor(ctx.target_win)[2])

    assert.is_true(mirror.render(ctx, frame(2, {
      block(1, { "one" }),
      block(2, { "two" }, true),
      block(3, { "three" }),
    })))
    assert.same(rows, ctx.view_state.mirror.reader_rows)
    assert.equal(rows[2], vim.api.nvim_win_get_cursor(ctx.target_win)[1])
    assert.equal(0, vim.api.nvim_win_get_cursor(ctx.target_win)[2])
    assert.same(before_lines, vim.api.nvim_buf_get_lines(ctx.target_buf, 0, -1, false))
    assert.equal(before_name, vim.api.nvim_buf_get_name(ctx.target_buf))
    assert.equal(before_filetype, vim.bo[ctx.target_buf].filetype)
    assert.is_false(vim.bo[ctx.target_buf].modified)
    assert.equal(saved_buf, vim.api.nvim_win_get_buf(ctx.target_win))

    assert.is_true(mirror.hide(ctx))
    assert.same(saved_view, vim.api.nvim_win_call(ctx.target_win, vim.fn.winsaveview))
    assert.is_false(ctx.view_state.mirror.visible)
  end)

  it("does not prepare virtual text for unused rows in a short block", function()
    local ctx = make_context(100)
    assert.is_true(mirror.render(ctx, frame(1, { block(1, { "only one line" }, true) })))
    local state = ctx.view_state.mirror
    assert.is_truthy(state.prepared_by_row[state.reader_rows[1]])
    assert.is_nil(state.prepared_by_row[state.reader_rows[1] + 1])
  end)

  it("reflows slots after fold invalidation and avoids folded anchors", function()
    local ctx = make_context(100)
    ctx.config.buffer.layout.region_lines = 10
    ctx.config.buffer.layout.max_blocks_per_region = 1
    ctx.config.buffer.layout.max_total_blocks = 10
    ctx.config.buffer.layout.edge_padding = 0
    assert.is_true(mirror.render(ctx, frame(1, { block(1, { "one" }, true) })))
    vim.api.nvim_buf_call(ctx.target_buf, function()
      vim.wo[ctx.target_win].foldmethod = "manual"
      vim.cmd("1,3fold")
    end)
    mirror.invalidate_layout(ctx)
    assert.is_true(mirror.render(ctx, frame(1, { block(1, { "one" }, true) })))
    for _, row in ipairs(ctx.view_state.mirror.reader_rows) do
      assert.is_false(vim.api.nvim_win_call(ctx.target_win, function() return vim.fn.foldclosed(row) ~= -1 end))
    end
    for _ = 1, 20 do
      mirror.invalidate_layout(ctx)
      assert.is_true(mirror.render(ctx, frame(1, { block(1, { "one" }, true) })))
    end
    assert.is_true(vim.tbl_count(ctx.view_state.mirror.observed_fold_rows) <= ctx.config.buffer.layout.max_total_blocks)
  end)

  it("bounds distinct folded slot history while retaining current slots", function()
    local ctx = make_context(100)
    ctx.config.buffer.layout.region_lines = 10
    ctx.config.buffer.layout.max_blocks_per_region = 1
    ctx.config.buffer.layout.max_total_blocks = 2
    ctx.config.buffer.layout.max_lines_per_block = 1
    ctx.config.buffer.layout.edge_padding = 0
    assert.is_true(mirror.render(ctx, frame(1, { block(1, { "one" }, true) })))
    vim.wo[ctx.target_win].foldmethod = "manual"
    local folded_history = {}
    for _ = 1, 8 do
      local candidate
      for _, slot in ipairs(ctx.view_state.mirror.slots or {}) do
        if not folded_history[slot.row]
          and vim.fn.foldclosed(slot.row) == -1
          and slot.row < vim.api.nvim_buf_line_count(ctx.target_buf) then
          candidate = slot.row
          break
        end
      end
      if not candidate then break end
      folded_history[candidate] = true
      vim.cmd(("%d,%dfold"):format(candidate, candidate + 1))
      mirror.invalidate_layout(ctx)
      assert.is_true(mirror.render(ctx, frame(1, { block(1, { "one" }, true) })))
    end
    assert.is_true(vim.tbl_count(folded_history) > ctx.config.buffer.layout.max_total_blocks)
    local current_slots = {}
    for _, slot in ipairs(ctx.view_state.mirror.slots or {}) do
      current_slots[slot.row] = true
      assert.is_true(ctx.view_state.mirror.observed_fold_rows[slot.row])
    end
    local historical_count = 0
    for row in pairs(ctx.view_state.mirror.observed_fold_rows or {}) do
      if not current_slots[row] then
        historical_count = historical_count + 1
        assert.is_true(vim.fn.foldclosed(row) ~= -1)
      end
    end
    assert.is_true(historical_count <= ctx.config.buffer.layout.max_total_blocks)
  end)

  it("retains cached blocks across hide and clears them on stop", function()
    local ctx = make_context(100)
    assert.is_true(mirror.render(ctx, frame(1, { block(1, { "one" }, true) })))
    local rows = vim.deepcopy(ctx.view_state.mirror.reader_rows)
    assert.is_true(mirror.hide(ctx))
    assert.same(rows, ctx.view_state.mirror.reader_rows)
    assert.is_true(mirror.restore(ctx, frame(1, { block(1, { "one" }, true) })))
    assert.is_true(mirror.stop(ctx))
    assert.is_nil(ctx.view_state.mirror.prepared_by_row)
    assert.is_nil(ctx.view_state.mirror.rendered_by_key)
    assert.is_nil(ctx.view_state.mirror.reader_rows)
  end)
end)
