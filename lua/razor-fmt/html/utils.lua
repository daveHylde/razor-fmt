-- razor-fmt/html/utils.lua
-- Utility functions for balanced construct parsing

local M = {}

--- Skip over a balanced construct (braces, parens, brackets, angle brackets)
---@param text string
---@param start_pos number Position after the opening char
---@param open_char string
---@param close_char string
---@return number|nil Position of the closing char, or nil if not found
function M.find_matching_close(text, start_pos, open_char, close_char)
  local len = #text
  local count = 1
  local pos = start_pos
  local in_string = nil

  while pos <= len and count > 0 do
    local c = text:sub(pos, pos)

    if in_string then
      if c == in_string and text:sub(pos - 1, pos - 1) ~= "\\" then
        in_string = nil
      end
    else
      if c == '"' or c == "'" then
        in_string = c
      elseif c == open_char then
        count = count + 1
      elseif c == close_char then
        count = count - 1
      end
    end
    pos = pos + 1
  end

  if count == 0 then
    return pos - 1
  end
  return nil
end

--- Extract content inside braces (returns content without surrounding braces)
---@param text string
---@param start_pos number Position of opening brace
---@return string|nil content
---@return number|nil end_pos Position of closing brace
function M.extract_brace_content(text, start_pos)
  local len = #text
  if start_pos > len or text:sub(start_pos, start_pos) ~= "{" then
    return nil, nil
  end

  local close_pos = M.find_matching_close(text, start_pos + 1, "{", "}")
  if not close_pos then
    return nil, nil
  end

  local content = text:sub(start_pos + 1, close_pos - 1)
  return content, close_pos
end

return M
