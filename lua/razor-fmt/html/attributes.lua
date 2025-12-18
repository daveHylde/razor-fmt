-- razor-fmt/html/attributes.lua
-- HTML attribute parsing with Razor expression support

local M = {}

--- Skip over a Razor expression inside a quoted attribute value
--- Returns the new position after the Razor expression
---@param attr_string string
---@param pos number Current position (after the @)
---@param len number Total string length
---@return number New position
local function skip_razor_expression(attr_string, pos, len)
  if pos > len then
    return pos
  end

  local next_c = attr_string:sub(pos, pos)

  if next_c == "(" then
    -- @(...) - skip to matching paren
    pos = pos + 1
    local depth = 1
    local in_string = nil
    while pos <= len and depth > 0 do
      local pc = attr_string:sub(pos, pos)
      if in_string then
        if pc == in_string and attr_string:sub(pos - 1, pos - 1) ~= "\\" then
          in_string = nil
        end
      else
        if pc == '"' or pc == "'" then
          in_string = pc
        elseif pc == "(" then
          depth = depth + 1
        elseif pc == ")" then
          depth = depth - 1
        end
      end
      pos = pos + 1
    end
    return pos

  elseif next_c == "[" then
    -- @[...] - indexer at start, skip to matching bracket
    pos = pos + 1
    local depth = 1
    local in_string = nil
    while pos <= len and depth > 0 do
      local bc = attr_string:sub(pos, pos)
      if in_string then
        if bc == in_string and attr_string:sub(pos - 1, pos - 1) ~= "\\" then
          in_string = nil
        end
      else
        if bc == '"' or bc == "'" then
          in_string = bc
        elseif bc == "[" then
          depth = depth + 1
        elseif bc == "]" then
          depth = depth - 1
        end
      end
      pos = pos + 1
    end
    return pos

  elseif next_c:match("[%a_]") then
    -- @Identifier - consume identifier then check for indexer/call
    while pos <= len and attr_string:sub(pos, pos):match("[%w_]") do
      pos = pos + 1
    end
    -- Check for chained member access, indexers, or method calls
    while pos <= len do
      local chain_c = attr_string:sub(pos, pos)
      if chain_c == "." then
        -- Member access - consume next identifier
        pos = pos + 1
        while pos <= len and attr_string:sub(pos, pos):match("[%w_]") do
          pos = pos + 1
        end
      elseif chain_c == "[" then
        -- Indexer - skip to matching bracket
        pos = pos + 1
        local depth = 1
        local in_string = nil
        while pos <= len and depth > 0 do
          local bc = attr_string:sub(pos, pos)
          if in_string then
            if bc == in_string and attr_string:sub(pos - 1, pos - 1) ~= "\\" then
              in_string = nil
            end
          else
            if bc == '"' or bc == "'" then
              in_string = bc
            elseif bc == "[" then
              depth = depth + 1
            elseif bc == "]" then
              depth = depth - 1
            end
          end
          pos = pos + 1
        end
      elseif chain_c == "(" then
        -- Method call - skip to matching paren
        pos = pos + 1
        local depth = 1
        local in_string = nil
        while pos <= len and depth > 0 do
          local pc = attr_string:sub(pos, pos)
          if in_string then
            if pc == in_string and attr_string:sub(pos - 1, pos - 1) ~= "\\" then
              in_string = nil
            end
          else
            if pc == '"' or pc == "'" then
              in_string = pc
            elseif pc == "(" then
              depth = depth + 1
            elseif pc == ")" then
              depth = depth - 1
            end
          end
          pos = pos + 1
        end
      else
        break
      end
    end
    return pos
  end

  -- Just @ followed by something else
  return pos
end

--- Parse attributes from an attribute string
---@param attr_string string
---@return table[] List of { name, value, quote } tables
function M.parse(attr_string)
  local attrs = {}
  local pos = 1
  local len = #attr_string

  while pos <= len do
    -- Skip whitespace
    local ws_start, ws_end = attr_string:find("^%s+", pos)
    if ws_start then
      pos = ws_end + 1
    end

    if pos > len then
      break
    end

    -- Match attribute name (including Blazor @ prefixed attributes)
    local name_pattern = "^[@]?[%w_:%-]+"
    local name_start, name_end = attr_string:find(name_pattern, pos)
    if not name_start then
      break
    end

    local name = attr_string:sub(name_start, name_end)
    pos = name_end + 1

    -- Check for = and value
    local eq_start, eq_end = attr_string:find("^%s*=%s*", pos)
    if eq_start then
      pos = eq_end + 1

      -- Check for quoted value
      local quote = attr_string:sub(pos, pos)
      if quote == '"' or quote == "'" then
        pos = pos + 1
        -- Find the closing quote, but handle Razor expressions with nested quotes
        local value_start = pos
        local value_end = nil

        while pos <= len do
          local c = attr_string:sub(pos, pos)

          if c == quote then
            -- Found potential closing quote
            value_end = pos - 1
            pos = pos + 1
            break
          elseif c == "@" then
            -- Razor expression - need to handle nested constructs
            pos = pos + 1
            pos = skip_razor_expression(attr_string, pos, len)
          else
            pos = pos + 1
          end
        end

        if value_end then
          local value = attr_string:sub(value_start, value_end)
          table.insert(attrs, { name = name, value = value, quote = quote })
        else
          -- Unclosed quote, take rest
          local value = attr_string:sub(value_start)
          table.insert(attrs, { name = name, value = value, quote = quote })
          break
        end
      else
        -- Unquoted value (until whitespace or end)
        local value_end = attr_string:find("%s", pos)
        local value
        if value_end then
          value = attr_string:sub(pos, value_end - 1)
          pos = value_end
        else
          value = attr_string:sub(pos)
          pos = len + 1
        end
        table.insert(attrs, { name = name, value = value, quote = '"' })
      end
    else
      -- Boolean attribute (no value)
      table.insert(attrs, { name = name, value = nil, quote = nil })
    end
  end

  return attrs
end

--- Format attributes with stacking
---@param attrs table[]
---@param tag_name string
---@param is_self_closing boolean
---@param config table
---@param force_inline boolean|nil If true, don't stack even if many attributes
---@return string
function M.format_stacked(attrs, tag_name, is_self_closing, config, force_inline)
  if not tag_name then
    return ""
  end

  if #attrs == 0 then
    if is_self_closing then
      return "<" .. tag_name .. " />"
    else
      return "<" .. tag_name .. ">"
    end
  end

  local max_attrs = config.max_attributes_per_line
  local should_stack = #attrs > max_attrs and not force_inline

  if not should_stack then
    -- All attributes on one line
    local parts = { "<" .. tag_name }
    for _, attr in ipairs(attrs) do
      if attr.value then
        table.insert(parts, " " .. attr.name .. "=" .. attr.quote .. attr.value .. attr.quote)
      else
        table.insert(parts, " " .. attr.name)
      end
    end
    if is_self_closing then
      return table.concat(parts) .. " />"
    else
      return table.concat(parts) .. ">"
    end
  end

  -- Stack attributes: tag name on first line, each attribute on its own line, closing aligned with tag
  -- NOTE: This function returns lines WITHOUT the base indent - caller must add it
  local lines = {}
  local attr_indent = string.rep(" ", config.indent_size)

  -- Tag name on its own line
  table.insert(lines, "<" .. tag_name)

  -- Each attribute on its own line (indented one level from tag)
  for _, attr in ipairs(attrs) do
    local attr_str
    if attr.value then
      attr_str = attr.name .. "=" .. attr.quote .. attr.value .. attr.quote
    else
      attr_str = attr.name
    end
    table.insert(lines, attr_indent .. attr_str)
  end

  -- Closing bracket on its own line, aligned with tag name (no extra indent)
  if is_self_closing then
    table.insert(lines, "/>")
  else
    table.insert(lines, ">")
  end

  return table.concat(lines, "\n")
end

return M
