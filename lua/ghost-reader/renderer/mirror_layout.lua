local M = {}

local function row_available(row, height, line_count, is_folded, reservations, gap)
  if row < 1 or row + height - 1 > line_count then
    return false
  end
  for current = row, row + height - 1 do
    if is_folded and is_folded(current) then
      return false
    end
  end
  for _, reservation in ipairs(reservations) do
    local before = row + height - 1 < reservation.row - gap
    local after = reservation.row + reservation.height - 1 < row - gap
    if not before and not after then
      return false
    end
  end
  return true
end

local function requested_region_counts(region_count, total)
  local counts = {}
  for index = 1, total do
    local region = math.floor((index - 1) * region_count / total) + 1
    counts[region] = (counts[region] or 0) + 1
  end
  return counts
end

local function nearest_available(candidate, first, last, height, line_count, is_folded, reservations, gap)
  for distance = 0, math.max(candidate - first, last - candidate) do
    local left = candidate - distance
    if left >= first and row_available(left, height, line_count, is_folded, reservations, gap) then
      return left
    end
    if distance > 0 then
      local right = candidate + distance
      if right <= last and row_available(right, height, line_count, is_folded, reservations, gap) then
        return right
      end
    end
  end
  return nil
end

local function attempt(line_count, opts, is_folded, padding, gap, requested_total)
  local region_count = math.ceil(line_count / opts.region_lines)
  local counts = requested_region_counts(region_count, requested_total)
  local reservations = {}

  for region = 1, region_count do
    local count = counts[region] or 0
    if count > 0 then
      local region_start = (region - 1) * opts.region_lines + 1
      local region_end = math.min(region * opts.region_lines, line_count)
      local first = region_start + padding
      local last = region_end - padding - opts.max_lines_per_block + 1
      if first <= last then
        for index = 1, count do
          local candidate = first + math.floor(index * (last - first + 1) / (count + 1))
          local row = nearest_available(candidate, first, last, opts.max_lines_per_block,
            line_count, is_folded, reservations, gap)
          if row then
            reservations[#reservations + 1] = { row = row, height = opts.max_lines_per_block }
          end
        end
      end
    end
  end
  return reservations
end

function M.slots(line_count, opts, is_folded)
  if line_count <= 0 then
    return {}
  end
  local region_count = math.ceil(line_count / opts.region_lines)
  local regional_capacity = region_count * opts.max_blocks_per_region
  local requested_total = math.min(regional_capacity, opts.max_total_blocks)
  if requested_total <= 0 then
    return {}
  end

  local slots = attempt(line_count, opts, is_folded, opts.edge_padding, opts.min_gap_lines, requested_total)
  if #slots == 0 then
    slots = attempt(line_count, opts, is_folded, 0, 0, requested_total)
  end

  table.sort(slots, function(left, right)
    return left.row < right.row
  end)
  while #slots > opts.max_total_blocks do
    table.remove(slots)
  end
  return slots
end

return M
