-- razor-fmt/html.lua
-- HTML tokenizer and formatter with JetBrains Rider-style defaults
-- Only formats pure HTML - preserves all Razor constructs (@...) as-is

local M = {}

-- HTML void elements (self-closing, no end tag)
M.VOID_ELEMENTS = {
  area = true,
  base = true,
  br = true,
  col = true,
  embed = true,
  hr = true,
  img = true,
  input = true,
  link = true,
  meta = true,
  param = true,
  source = true,
  track = true,
  wbr = true,
}

-- Elements that should preserve their content as-is
M.PRESERVE_CONTENT_ELEMENTS = {
  script = true,
  style = true,
  pre = true,
  textarea = true,
}

-- Token types
M.TOKEN_TYPES = {
  TAG_OPEN = "TAG_OPEN",
  TAG_CLOSE = "TAG_CLOSE",
  TAG_SELF_CLOSE = "TAG_SELF_CLOSE",
  TEXT = "TEXT",
  COMMENT = "COMMENT",
  DOCTYPE = "DOCTYPE",
  RAZOR = "RAZOR", -- Anything starting with @
}

--- Parse attributes from an attribute string
---@param attr_string string
---@return table[] List of { name, value, quote } tables
function M.parse_attributes(attr_string)
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
        local value_end = attr_string:find(quote, pos, true)
        if value_end then
          local value = attr_string:sub(pos, value_end - 1)
          table.insert(attrs, { name = name, value = value, quote = quote })
          pos = value_end + 1
        else
          -- Unclosed quote, take rest
          local value = attr_string:sub(pos)
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

--- Format attributes with stacking (JetBrains Rider style)
---@param attrs table[]
---@param tag_name string
---@param indent string
---@param is_self_closing boolean
---@param config table
---@return string
function M.format_attributes_stacked(attrs, tag_name, indent, is_self_closing, config)
  if #attrs == 0 then
    if is_self_closing then
      return "<" .. tag_name .. " />"
    else
      return "<" .. tag_name .. ">"
    end
  end

  local max_attrs = config.max_attributes_per_line
  local should_stack = #attrs > max_attrs

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

  -- Stack attributes (Rider style: first attr on same line, rest indented)
  local lines = {}
  local first_line = "<" .. tag_name

  -- Calculate alignment indent (align with first attribute)
  local attr_indent
  if config.align_attributes then
    attr_indent = indent .. string.rep(" ", #tag_name + 2) -- +2 for "< "
  else
    attr_indent = indent .. string.rep(" ", config.indent_size)
  end

  for i, attr in ipairs(attrs) do
    local attr_str
    if attr.value then
      attr_str = attr.name .. "=" .. attr.quote .. attr.value .. attr.quote
    else
      attr_str = attr.name
    end

    if i == 1 then
      first_line = first_line .. " " .. attr_str
      table.insert(lines, first_line)
    else
      table.insert(lines, attr_indent .. attr_str)
    end
  end

  -- Add closing bracket
  if is_self_closing then
    lines[#lines] = lines[#lines] .. " />"
  else
    lines[#lines] = lines[#lines] .. ">"
  end

  return table.concat(lines, "\n")
end

--- Skip over a balanced construct (braces, parens, brackets)
---@param text string
---@param start_pos number Position after the opening char
---@param open_char string
---@param close_char string
---@return number|nil Position of the closing char, or nil if not found
local function find_matching_close(text, start_pos, open_char, close_char)
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

--- Consume a Razor construct starting at @
--- Returns the end position (inclusive) of the Razor construct
---@param text string
---@param pos number Position of the @
---@return number end_pos
local function consume_razor(text, pos)
  local len = #text
  local start = pos
  pos = pos + 1 -- skip @

  if pos > len then
    return start
  end

  local c = text:sub(pos, pos)

  -- @@ escape
  if c == "@" then
    return pos
  end

  -- @* comment *@
  if c == "*" then
    local end_marker = text:find("%*@", pos + 1)
    if end_marker then
      return end_marker + 1
    end
    return len
  end

  -- @{ } code block
  if c == "{" then
    local close = find_matching_close(text, pos + 1, "{", "}")
    return close or len
  end

  -- @( ) explicit expression
  if c == "(" then
    local close = find_matching_close(text, pos + 1, "(", ")")
    return close or len
  end

  -- @identifier... (directive, keyword, or expression)
  if c:match("[%a_]") then
    -- Consume identifier
    while pos <= len and text:sub(pos, pos):match("[%w_]") do
      pos = pos + 1
    end

    -- Check what follows: could be generic <T>, method call (), indexer [], member access .
    while pos <= len do
      local next_c = text:sub(pos, pos)

      -- Skip whitespace only if followed by something that continues the expression
      local ws_end = pos
      while ws_end <= len and text:sub(ws_end, ws_end):match("%s") do
        ws_end = ws_end + 1
      end

      local after_ws = text:sub(ws_end, ws_end)

      -- Generic type parameter <T> - but not if it's an HTML tag
      if after_ws == "<" then
        -- Check if it looks like generic (has > before any space or <)
        local rest = text:sub(ws_end + 1)
        local generic_end = rest:find(">")
        local space_before = rest:find("%s")
        local lt_before = rest:find("<")

        if generic_end and (not space_before or generic_end < space_before) and (not lt_before or generic_end < lt_before) then
          local close = find_matching_close(text, ws_end + 1, "<", ">")
          if close then
            pos = close + 1
          else
            break
          end
        else
          break
        end
      -- Opening brace { - C# block follows
      elseif after_ws == "{" then
        pos = ws_end
        local close = find_matching_close(text, pos + 1, "{", "}")
        if close then
          pos = close + 1
          -- After a block, check for else/catch/finally
          while true do
            -- Skip whitespace
            while pos <= len and text:sub(pos, pos):match("%s") do
              pos = pos + 1
            end
            local rest = text:sub(pos)
            if rest:match("^else%s*if%s*%(") then
              pos = pos + 4 -- skip "else"
              while pos <= len and text:sub(pos, pos):match("%s") do
                pos = pos + 1
              end
              pos = pos + 2 -- skip "if"
              while pos <= len and text:sub(pos, pos):match("%s") do
                pos = pos + 1
              end
              local paren_close = find_matching_close(text, pos + 1, "(", ")")
              if paren_close then
                pos = paren_close + 1
                while pos <= len and text:sub(pos, pos):match("%s") do
                  pos = pos + 1
                end
                if text:sub(pos, pos) == "{" then
                  local brace_close = find_matching_close(text, pos + 1, "{", "}")
                  if brace_close then
                    pos = brace_close + 1
                  else
                    break
                  end
                else
                  break
                end
              else
                break
              end
            elseif rest:match("^else%s*{") then
              pos = pos + 4 -- skip "else"
              while pos <= len and text:sub(pos, pos):match("%s") do
                pos = pos + 1
              end
              local brace_close = find_matching_close(text, pos + 1, "{", "}")
              if brace_close then
                pos = brace_close + 1
              else
                break
              end
            elseif rest:match("^catch%s*%(") then
              pos = pos + 5 -- skip "catch"
              while pos <= len and text:sub(pos, pos):match("%s") do
                pos = pos + 1
              end
              local paren_close = find_matching_close(text, pos + 1, "(", ")")
              if paren_close then
                pos = paren_close + 1
                while pos <= len and text:sub(pos, pos):match("%s") do
                  pos = pos + 1
                end
                if text:sub(pos, pos) == "{" then
                  local brace_close = find_matching_close(text, pos + 1, "{", "}")
                  if brace_close then
                    pos = brace_close + 1
                  else
                    break
                  end
                else
                  break
                end
              else
                break
              end
            elseif rest:match("^catch%s*{") then
              pos = pos + 5 -- skip "catch"
              while pos <= len and text:sub(pos, pos):match("%s") do
                pos = pos + 1
              end
              local brace_close = find_matching_close(text, pos + 1, "{", "}")
              if brace_close then
                pos = brace_close + 1
              else
                break
              end
            elseif rest:match("^finally%s*{") then
              pos = pos + 7 -- skip "finally"
              while pos <= len and text:sub(pos, pos):match("%s") do
                pos = pos + 1
              end
              local brace_close = find_matching_close(text, pos + 1, "{", "}")
              if brace_close then
                pos = brace_close + 1
              else
                break
              end
            else
              break
            end
          end
        end
        break
      -- Parentheses ( ) - method call or condition
      elseif after_ws == "(" then
        pos = ws_end
        local close = find_matching_close(text, pos + 1, "(", ")")
        if close then
          pos = close + 1
        else
          break
        end
      -- Square brackets [ ] - indexer or attribute
      elseif next_c == "[" then
        local close = find_matching_close(text, pos + 1, "[", "]")
        if close then
          pos = close + 1
        else
          break
        end
      -- Dot . - member access (must be directly attached, no whitespace)
      elseif next_c == "." then
        pos = pos + 1
        -- Consume next identifier
        while pos <= len and text:sub(pos, pos):match("[%w_]") do
          pos = pos + 1
        end
      else
        break
      end
    end

    return pos - 1
  end

  -- Unknown @ construct, just return the @
  return start
end

--- Tokenize HTML/Razor content
---@param text string
---@return table[]
function M.tokenize(text)
  local tokens = {}
  local pos = 1
  local len = #text

  while pos <= len do
    local c = text:sub(pos, pos)

    -- Razor construct
    if c == "@" then
      local end_pos = consume_razor(text, pos)
      table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR, content = text:sub(pos, end_pos) })
      pos = end_pos + 1

    -- HTML comment
    elseif text:sub(pos, pos + 3) == "<!--" then
      local end_marker = text:find("-->", pos + 4, true)
      if end_marker then
        table.insert(tokens, { type = M.TOKEN_TYPES.COMMENT, content = text:sub(pos, end_marker + 2) })
        pos = end_marker + 3
      else
        table.insert(tokens, { type = M.TOKEN_TYPES.COMMENT, content = text:sub(pos) })
        break
      end

    -- DOCTYPE
    elseif text:sub(pos, pos + 8):upper() == "<!DOCTYPE" then
      local end_marker = text:find(">", pos, true)
      if end_marker then
        table.insert(tokens, { type = M.TOKEN_TYPES.DOCTYPE, content = text:sub(pos, end_marker) })
        pos = end_marker + 1
      else
        table.insert(tokens, { type = M.TOKEN_TYPES.DOCTYPE, content = text:sub(pos) })
        break
      end

    -- Closing tag
    elseif text:sub(pos, pos + 1) == "</" then
      local end_marker = text:find(">", pos, true)
      if end_marker then
        local tag_name = text:sub(pos + 2, end_marker - 1):match("^%s*([%w%-]+)")
        table.insert(tokens, { type = M.TOKEN_TYPES.TAG_CLOSE, tag = tag_name, content = text:sub(pos, end_marker) })
        pos = end_marker + 1
      else
        table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = text:sub(pos) })
        break
      end

    -- Opening tag
    elseif c == "<" and text:sub(pos + 1, pos + 1):match("[%a]") then
      -- Find end of tag, handling quoted attributes
      local tag_end = nil
      local search_pos = pos + 1
      local in_quote = nil

      while search_pos <= len do
        local sc = text:sub(search_pos, search_pos)
        if in_quote then
          if sc == in_quote then
            in_quote = nil
          end
        else
          if sc == '"' or sc == "'" then
            in_quote = sc
          elseif sc == ">" then
            tag_end = search_pos
            break
          end
        end
        search_pos = search_pos + 1
      end

      if tag_end then
        local tag_content = text:sub(pos + 1, tag_end - 1)
        local is_self_closing = tag_content:match("/%s*$") ~= nil
        if is_self_closing then
          tag_content = tag_content:gsub("/%s*$", "")
        end

        local tag_name = tag_content:match("^([%w%-]+)")
        if tag_name then
          local attr_string = tag_content:sub(#tag_name + 1)
          local is_void = M.VOID_ELEMENTS[tag_name:lower()]
          local token_type = (is_self_closing or is_void) and M.TOKEN_TYPES.TAG_SELF_CLOSE or M.TOKEN_TYPES.TAG_OPEN

          table.insert(tokens, {
            type = token_type,
            tag = tag_name,
            attributes = M.parse_attributes(attr_string),
            is_void = is_void,
            content = text:sub(pos, tag_end),
          })
        else
          table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = text:sub(pos, tag_end) })
        end
        pos = tag_end + 1
      else
        table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = text:sub(pos) })
        break
      end

    -- Plain text
    else
      local next_special = text:find("[<@]", pos)
      if next_special then
        if next_special > pos then
          table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = text:sub(pos, next_special - 1) })
        end
        pos = next_special
      else
        if pos <= len then
          table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = text:sub(pos) })
        end
        break
      end
    end
  end

  return tokens
end

--- Format HTML content with JetBrains Rider-style formatting
---@param input string
---@param config table
---@return string
function M.format(input, config)
  local tokens = M.tokenize(input)
  local output = {}
  local indent_level = 0
  local indent_str = string.rep(" ", config.indent_size)

  local function get_indent()
    return string.rep(indent_str, indent_level)
  end

  local function add_line(content)
    if content and content ~= "" then
      table.insert(output, content)
    end
  end

  local function add_lines(content)
    -- Add content preserving its internal line structure
    for line in content:gmatch("([^\n]*)\n?") do
      if line ~= "" or content:find("\n") then
        if line ~= "" then
          add_line(line)
        elseif #output > 0 then
          -- Preserve blank lines within content
          add_line("")
        end
      end
    end
  end

  local i = 1
  while i <= #tokens do
    local token = tokens[i]
    local indent = get_indent()

    if token.type == M.TOKEN_TYPES.DOCTYPE then
      add_line(token.content)

    elseif token.type == M.TOKEN_TYPES.COMMENT then
      add_line(indent .. token.content)

    elseif token.type == M.TOKEN_TYPES.RAZOR then
      -- Preserve Razor constructs exactly, but handle indentation for multi-line
      local content = token.content
      local lines = {}
      for line in content:gmatch("[^\n]+") do
        table.insert(lines, line)
      end

      if #lines == 1 then
        -- Single line - just add with current indent if it's a line-level directive
        local trimmed = content:match("^%s*(.-)%s*$")
        if trimmed:match("^@[%a_]") and not trimmed:match("{") then
          -- Line directive like @inject, @using - no indent
          add_line(trimmed)
        else
          add_line(indent .. trimmed)
        end
      else
        -- Multi-line - preserve internal structure
        for _, line in ipairs(lines) do
          add_line(line)
        end
      end

    elseif token.type == M.TOKEN_TYPES.TAG_SELF_CLOSE then
      local formatted = M.format_attributes_stacked(token.attributes, token.tag, indent, true, config)
      add_line(indent .. formatted)

    elseif token.type == M.TOKEN_TYPES.TAG_OPEN then
      local tag_lower = token.tag:lower()
      local formatted = M.format_attributes_stacked(token.attributes, token.tag, indent, false, config)
      add_line(indent .. formatted)

      -- Check if this is a preserve-content element
      if M.PRESERVE_CONTENT_ELEMENTS[tag_lower] then
        local content_parts = {}
        i = i + 1
        while i <= #tokens do
          local next_token = tokens[i]
          if next_token.type == M.TOKEN_TYPES.TAG_CLOSE and next_token.tag and next_token.tag:lower() == tag_lower then
            break
          end
          table.insert(content_parts, next_token.content)
          i = i + 1
        end
        if #content_parts > 0 then
          add_line(table.concat(content_parts))
        end
        if i <= #tokens then
          add_line(indent .. "</" .. tokens[i].tag .. ">")
        end
      else
        indent_level = indent_level + 1
      end

    elseif token.type == M.TOKEN_TYPES.TAG_CLOSE then
      indent_level = math.max(0, indent_level - 1)
      indent = get_indent()
      add_line(indent .. "</" .. token.tag .. ">")

    elseif token.type == M.TOKEN_TYPES.TEXT then
      local text = token.content
      local trimmed = text:match("^%s*(.-)%s*$")
      if trimmed and trimmed ~= "" then
        add_line(indent .. trimmed)
      end
    end

    i = i + 1
  end

  return table.concat(output, "\n")
end

return M
