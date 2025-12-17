-- razor-fmt/parser.lua
-- Razor file parsing utilities

local M = {}

--- Find all @code{} blocks in the buffer using pattern matching
--- Returns a list of { start_line, end_line, content } tables (1-indexed)
---@param lines string[]
---@return table[]
function M.find_code_blocks(lines)
  local blocks = {}
  local in_code_block = false
  local brace_count = 0
  local block_start = nil
  local block_content = {}

  for i, line in ipairs(lines) do
    if not in_code_block then
      local code_start = line:match("@code%s*{")
      if code_start then
        in_code_block = true
        block_start = i
        for _ in line:gmatch("{") do
          brace_count = brace_count + 1
        end
        for _ in line:gmatch("}") do
          brace_count = brace_count - 1
        end
        table.insert(block_content, line)
      end
    else
      for _ in line:gmatch("{") do
        brace_count = brace_count + 1
      end
      for _ in line:gmatch("}") do
        brace_count = brace_count - 1
      end
      table.insert(block_content, line)

      if brace_count == 0 then
        table.insert(blocks, {
          start_line = block_start,
          end_line = i,
          content = table.concat(block_content, "\n"),
        })
        in_code_block = false
        block_content = {}
        block_start = nil
      end
    end
  end

  return blocks
end

--- Find all HTML/template regions (lines not inside @code{} blocks)
--- Returns a list of { start_line, end_line } tables (1-indexed, inclusive)
---@param lines string[]
---@param code_blocks table[]
---@return table[]
function M.find_html_regions(lines, code_blocks)
  local regions = {}
  local total_lines = #lines

  if total_lines == 0 then
    return regions
  end

  -- Sort code blocks by start line
  local sorted_blocks = vim.deepcopy(code_blocks)
  table.sort(sorted_blocks, function(a, b)
    return a.start_line < b.start_line
  end)

  local current_line = 1

  for _, block in ipairs(sorted_blocks) do
    -- Add HTML region before this code block
    if current_line < block.start_line then
      table.insert(regions, {
        start_line = current_line,
        end_line = block.start_line - 1,
      })
    end
    current_line = block.end_line + 1
  end

  -- Add HTML region after the last code block
  if current_line <= total_lines then
    table.insert(regions, {
      start_line = current_line,
      end_line = total_lines,
    })
  end

  return regions
end

return M
