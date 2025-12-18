-- razor-fmt/html.lua
-- HTML tokenizer and formatter with JetBrains Rider-style defaults
-- Formats HTML tags, preserves Razor control flow blocks as-is

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
  RAZOR_LINE = "RAZOR_LINE",   -- Line directives like @inject, @using
  RAZOR_BLOCK = "RAZOR_BLOCK", -- Control flow blocks like @if, @foreach
}

-- Razor line directives (consume entire line)
local LINE_DIRECTIVES = {
  inject = true,
  using = true,
  namespace = true,
  page = true,
  model = true,
  inherits = true,
  implements = true,
  layout = true,
  attribute = true,
  preservewhitespace = true,
  typeparam = true,
  rendermode = true,
}

-- Razor control flow keywords (have blocks)
local CONTROL_FLOW_KEYWORDS = {
  ["if"] = true,
  ["for"] = true,
  ["foreach"] = true,
  ["while"] = true,
  ["do"] = true,
  ["switch"] = true,
  ["try"] = true,
  ["lock"] = true,
  ["using"] = true, -- using as statement, not directive
  ["code"] = true,  -- Blazor @code block
  ["functions"] = true, -- Razor @functions block
  ["section"] = true, -- @section Name { }
}

-- Forward declarations
local format_control_flow_block

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
            if pos <= len then
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
              else
                -- Just @ followed by something else, continue
              end
            end
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
---@param indent string
---@param is_self_closing boolean
---@param config table
---@param force_inline boolean|nil If true, don't stack even if many attributes
---@return string
function M.format_attributes_stacked(attrs, tag_name, indent, is_self_closing, config, force_inline)
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

--- Skip over a balanced construct (braces, parens, brackets, angle brackets)
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

--- Try to consume a Razor control flow block starting at pos
--- Returns end position if this is a control flow block, nil otherwise
---@param text string
---@param pos number Position of the @
---@return number|nil end_pos
local function try_consume_control_flow(text, pos)
  local len = #text
  if pos > len or text:sub(pos, pos) ~= "@" then
    return nil
  end

  local after_at = pos + 1
  if after_at > len then
    return nil
  end

  local c = text:sub(after_at, after_at)

  -- @{ } code block
  if c == "{" then
    local close = find_matching_close(text, after_at + 1, "{", "}")
    return close
  end

  -- @* comment *@
  if c == "*" then
    local end_marker = text:find("%*@", after_at + 1)
    if end_marker then
      return end_marker + 1
    end
    return len
  end

  -- Check for control flow keyword
  if not c:match("[%a]") then
    return nil
  end

  -- Consume identifier
  local id_end = after_at
  while id_end <= len and text:sub(id_end, id_end):match("[%w_]") do
    id_end = id_end + 1
  end
  local identifier = text:sub(after_at, id_end - 1):lower()

  -- Check if it's a control flow keyword
  if not CONTROL_FLOW_KEYWORDS[identifier] then
    return nil
  end

  -- For 'using', check if it's a statement (has parens) or directive (no parens)
  if identifier == "using" then
    local ws_end = id_end
    while ws_end <= len and text:sub(ws_end, ws_end):match("%s") do
      ws_end = ws_end + 1
    end
    if text:sub(ws_end, ws_end) ~= "(" then
      return nil -- It's a directive, not a statement
    end
  end

  -- Skip whitespace after keyword
  local kw_pos = id_end
  while kw_pos <= len and text:sub(kw_pos, kw_pos):match("%s") do
    kw_pos = kw_pos + 1
  end

  -- For @section, consume the section name first
  if identifier == "section" then
    -- Consume section name (identifier)
    if not text:sub(kw_pos, kw_pos):match("[%a_]") then
      return nil
    end
    while kw_pos <= len and text:sub(kw_pos, kw_pos):match("[%w_]") do
      kw_pos = kw_pos + 1
    end
    -- Skip whitespace before block
    while kw_pos <= len and text:sub(kw_pos, kw_pos):match("%s") do
      kw_pos = kw_pos + 1
    end
  end

  -- Consume condition in parens if present (for if, for, foreach, while, switch, lock, using, catch)
  if text:sub(kw_pos, kw_pos) == "(" then
    local paren_close = find_matching_close(text, kw_pos + 1, "(", ")")
    if paren_close then
      kw_pos = paren_close + 1
    else
      return nil
    end
  end

  -- Skip whitespace before block
  while kw_pos <= len and text:sub(kw_pos, kw_pos):match("%s") do
    kw_pos = kw_pos + 1
  end

  -- Consume block
  if text:sub(kw_pos, kw_pos) ~= "{" then
    -- do-while doesn't need initial brace check, single statement form
    if identifier == "do" then
      -- For do, we need: do { } while (condition);
      -- But if no brace, might be single statement - let's just require brace
      return nil
    end
    return nil
  end

  local brace_close = find_matching_close(text, kw_pos + 1, "{", "}")
  if not brace_close then
    return nil
  end

  kw_pos = brace_close + 1

  -- Handle chained blocks: else, else if, catch, finally, while (for do-while)
  while true do
    -- Skip whitespace
    local ws_start = kw_pos
    while kw_pos <= len and text:sub(kw_pos, kw_pos):match("%s") do
      kw_pos = kw_pos + 1
    end

    local rest = text:sub(kw_pos)

    -- else if
    if rest:match("^else%s+if%s*%(") or rest:match("^else%s*if%s*%(") then
      kw_pos = kw_pos + 4 -- skip "else"
      while kw_pos <= len and text:sub(kw_pos, kw_pos):match("%s") do
        kw_pos = kw_pos + 1
      end
      kw_pos = kw_pos + 2 -- skip "if"
      while kw_pos <= len and text:sub(kw_pos, kw_pos):match("%s") do
        kw_pos = kw_pos + 1
      end
      local paren_close = find_matching_close(text, kw_pos + 1, "(", ")")
      if not paren_close then break end
      kw_pos = paren_close + 1
      while kw_pos <= len and text:sub(kw_pos, kw_pos):match("%s") do
        kw_pos = kw_pos + 1
      end
      if text:sub(kw_pos, kw_pos) ~= "{" then break end
      brace_close = find_matching_close(text, kw_pos + 1, "{", "}")
      if not brace_close then break end
      kw_pos = brace_close + 1

    -- else
    elseif rest:match("^else%s*{") then
      kw_pos = kw_pos + 4 -- skip "else"
      while kw_pos <= len and text:sub(kw_pos, kw_pos):match("%s") do
        kw_pos = kw_pos + 1
      end
      brace_close = find_matching_close(text, kw_pos + 1, "{", "}")
      if not brace_close then break end
      kw_pos = brace_close + 1

    -- catch with exception type
    elseif rest:match("^catch%s*%(") then
      kw_pos = kw_pos + 5 -- skip "catch"
      while kw_pos <= len and text:sub(kw_pos, kw_pos):match("%s") do
        kw_pos = kw_pos + 1
      end
      local paren_close = find_matching_close(text, kw_pos + 1, "(", ")")
      if not paren_close then break end
      kw_pos = paren_close + 1
      while kw_pos <= len and text:sub(kw_pos, kw_pos):match("%s") do
        kw_pos = kw_pos + 1
      end
      if text:sub(kw_pos, kw_pos) ~= "{" then break end
      brace_close = find_matching_close(text, kw_pos + 1, "{", "}")
      if not brace_close then break end
      kw_pos = brace_close + 1

    -- catch without exception type
    elseif rest:match("^catch%s*{") then
      kw_pos = kw_pos + 5 -- skip "catch"
      while kw_pos <= len and text:sub(kw_pos, kw_pos):match("%s") do
        kw_pos = kw_pos + 1
      end
      brace_close = find_matching_close(text, kw_pos + 1, "{", "}")
      if not brace_close then break end
      kw_pos = brace_close + 1

    -- finally
    elseif rest:match("^finally%s*{") then
      kw_pos = kw_pos + 7 -- skip "finally"
      while kw_pos <= len and text:sub(kw_pos, kw_pos):match("%s") do
        kw_pos = kw_pos + 1
      end
      brace_close = find_matching_close(text, kw_pos + 1, "{", "}")
      if not brace_close then break end
      kw_pos = brace_close + 1

    -- while (for do-while)
    elseif identifier == "do" and rest:match("^while%s*%(") then
      kw_pos = kw_pos + 5 -- skip "while"
      while kw_pos <= len and text:sub(kw_pos, kw_pos):match("%s") do
        kw_pos = kw_pos + 1
      end
      local paren_close = find_matching_close(text, kw_pos + 1, "(", ")")
      if not paren_close then break end
      kw_pos = paren_close + 1
      -- Skip optional semicolon
      while kw_pos <= len and text:sub(kw_pos, kw_pos):match("%s") do
        kw_pos = kw_pos + 1
      end
      if text:sub(kw_pos, kw_pos) == ";" then
        kw_pos = kw_pos + 1
      end
      break -- do-while is complete

    else
      break
    end
  end

  return kw_pos - 1
end

--- Try to consume a Razor line directive starting at pos
--- Returns end position if this is a line directive, nil otherwise
---@param text string
---@param pos number Position of the @
---@return number|nil end_pos
local function try_consume_line_directive(text, pos)
  local len = #text
  if pos > len or text:sub(pos, pos) ~= "@" then
    return nil
  end

  local after_at = pos + 1
  if after_at > len then
    return nil
  end

  local c = text:sub(after_at, after_at)
  if not c:match("[%a]") then
    return nil
  end

  -- Consume identifier
  local id_end = after_at
  while id_end <= len and text:sub(id_end, id_end):match("[%w_]") do
    id_end = id_end + 1
  end
  local identifier = text:sub(after_at, id_end - 1)
  local identifier_lower = identifier:lower()

  -- Directives must be lowercase (e.g., @model not @Model)
  if identifier ~= identifier_lower then
    return nil
  end

  if not LINE_DIRECTIVES[identifier_lower] then
    return nil
  end

  -- Make sure it's not followed by . or ( which would make it an expression
  local next_char = text:sub(id_end, id_end)
  if next_char == "." or next_char == "(" or next_char == "[" then
    return nil
  end

  -- Consume until end of line
  local newline = text:find("\n", id_end)
  if newline then
    return newline - 1
  end
  return len
end

--- Extract content inside braces (returns content without surrounding braces)
---@param text string
---@param start_pos number Position of opening brace
---@return string|nil content
---@return number|nil end_pos Position of closing brace
local function extract_brace_content(text, start_pos)
  local len = #text
  if start_pos > len or text:sub(start_pos, start_pos) ~= "{" then
    return nil, nil
  end

  local close_pos = find_matching_close(text, start_pos + 1, "{", "}")
  if not close_pos then
    return nil, nil
  end

  local content = text:sub(start_pos + 1, close_pos - 1)
  return content, close_pos
end

--- Parse a control flow block into its components
--- Returns a table with header, body, and chained blocks
---@param content string The full control flow content starting with @
---@return table|nil parsed { keyword, header, body, chains }
local function parse_control_flow(content)
  local len = #content
  if len == 0 or content:sub(1, 1) ~= "@" then
    return nil
  end

  local pos = 2 -- after @

  -- Check for @{ } code block
  if content:sub(pos, pos) == "{" then
    local body_content, close_pos = extract_brace_content(content, pos)
    if body_content then
      return {
        keyword = "",
        header = "@",
        body = body_content,
        chains = {},
      }
    end
    return nil
  end

  -- Check for @* comment *@
  if content:sub(pos, pos) == "*" then
    return nil -- Don't format comments
  end

  -- Get keyword
  if not content:sub(pos, pos):match("[%a]") then
    return nil
  end

  local kw_end = pos
  while kw_end <= len and content:sub(kw_end, kw_end):match("[%w_]") do
    kw_end = kw_end + 1
  end
  local keyword = content:sub(pos, kw_end - 1):lower()

  -- Check if it's a control flow keyword that we format
  if not CONTROL_FLOW_KEYWORDS[keyword] then
    return nil
  end

  -- Don't format @code or @functions blocks (those are C# code)
  if keyword == "code" or keyword == "functions" then
    return nil
  end

  pos = kw_end

  -- Skip whitespace
  while pos <= len and content:sub(pos, pos):match("%s") do
    pos = pos + 1
  end

  -- For @section, consume the section name
  local section_name = nil
  if keyword == "section" then
    local name_start = pos
    while pos <= len and content:sub(pos, pos):match("[%w_]") do
      pos = pos + 1
    end
    section_name = content:sub(name_start, pos - 1)
    while pos <= len and content:sub(pos, pos):match("%s") do
      pos = pos + 1
    end
  end

  -- Get condition in parentheses if present
  local condition = nil
  if content:sub(pos, pos) == "(" then
    local paren_close = find_matching_close(content, pos + 1, "(", ")")
    if paren_close then
      condition = content:sub(pos, paren_close)
      pos = paren_close + 1
    end
  end

  -- Skip whitespace before block
  while pos <= len and content:sub(pos, pos):match("%s") do
    pos = pos + 1
  end

  -- Get body
  if content:sub(pos, pos) ~= "{" then
    return nil
  end

  local body_content, brace_close = extract_brace_content(content, pos)
  if not body_content then
    return nil
  end

  -- Build header
  local header
  if keyword == "section" then
    header = "@section " .. (section_name or "")
  elseif condition then
    header = "@" .. keyword .. " " .. condition
  else
    header = "@" .. keyword
  end

  local result = {
    keyword = keyword,
    header = header,
    body = body_content,
    chains = {},
  }

  pos = brace_close + 1

  -- Handle chained blocks: else, else if, catch, finally, while (for do-while)
  while pos <= len do
    -- Skip whitespace
    while pos <= len and content:sub(pos, pos):match("%s") do
      pos = pos + 1
    end

    if pos > len then
      break
    end

    local rest = content:sub(pos)

    -- else if
    if rest:match("^else%s+if%s*%(") or rest:match("^else%s*if%s*%(") then
      pos = pos + 4 -- skip "else"
      while pos <= len and content:sub(pos, pos):match("%s") do
        pos = pos + 1
      end
      pos = pos + 2 -- skip "if"
      while pos <= len and content:sub(pos, pos):match("%s") do
        pos = pos + 1
      end
      local paren_close = find_matching_close(content, pos + 1, "(", ")")
      if not paren_close then break end
      local chain_condition = content:sub(pos, paren_close)
      pos = paren_close + 1
      while pos <= len and content:sub(pos, pos):match("%s") do
        pos = pos + 1
      end
      if content:sub(pos, pos) ~= "{" then break end
      local chain_body, chain_close = extract_brace_content(content, pos)
      if not chain_body then break end
      table.insert(result.chains, {
        header = "else if " .. chain_condition,
        body = chain_body,
      })
      pos = chain_close + 1

    -- else
    elseif rest:match("^else%s*{") then
      pos = pos + 4 -- skip "else"
      while pos <= len and content:sub(pos, pos):match("%s") do
        pos = pos + 1
      end
      local chain_body, chain_close = extract_brace_content(content, pos)
      if not chain_body then break end
      table.insert(result.chains, {
        header = "else",
        body = chain_body,
      })
      pos = chain_close + 1

    -- catch with exception type
    elseif rest:match("^catch%s*%(") then
      pos = pos + 5 -- skip "catch"
      while pos <= len and content:sub(pos, pos):match("%s") do
        pos = pos + 1
      end
      local paren_close = find_matching_close(content, pos + 1, "(", ")")
      if not paren_close then break end
      local chain_condition = content:sub(pos, paren_close)
      pos = paren_close + 1
      while pos <= len and content:sub(pos, pos):match("%s") do
        pos = pos + 1
      end
      if content:sub(pos, pos) ~= "{" then break end
      local chain_body, chain_close = extract_brace_content(content, pos)
      if not chain_body then break end
      table.insert(result.chains, {
        header = "catch " .. chain_condition,
        body = chain_body,
      })
      pos = chain_close + 1

    -- catch without exception type
    elseif rest:match("^catch%s*{") then
      pos = pos + 5 -- skip "catch"
      while pos <= len and content:sub(pos, pos):match("%s") do
        pos = pos + 1
      end
      local chain_body, chain_close = extract_brace_content(content, pos)
      if not chain_body then break end
      table.insert(result.chains, {
        header = "catch",
        body = chain_body,
      })
      pos = chain_close + 1

    -- finally
    elseif rest:match("^finally%s*{") then
      pos = pos + 7 -- skip "finally"
      while pos <= len and content:sub(pos, pos):match("%s") do
        pos = pos + 1
      end
      local chain_body, chain_close = extract_brace_content(content, pos)
      if not chain_body then break end
      table.insert(result.chains, {
        header = "finally",
        body = chain_body,
      })
      pos = chain_close + 1

    -- while (for do-while)
    elseif keyword == "do" and rest:match("^while%s*%(") then
      pos = pos + 5 -- skip "while"
      while pos <= len and content:sub(pos, pos):match("%s") do
        pos = pos + 1
      end
      local paren_close = find_matching_close(content, pos + 1, "(", ")")
      if not paren_close then break end
      local chain_condition = content:sub(pos, paren_close)
      pos = paren_close + 1
      -- Skip optional semicolon
      while pos <= len and content:sub(pos, pos):match("%s") do
        pos = pos + 1
      end
      if content:sub(pos, pos) == ";" then
        pos = pos + 1
      end
      table.insert(result.chains, {
        header = "while " .. chain_condition,
        body = nil, -- do-while has no body after while
        is_do_while = true,
      })
      break -- do-while is complete

    else
      break
    end
  end

  return result
end

--- Format a control flow block with proper indentation
--- Brackets on their own line, body indented and recursively formatted
---@param content string The raw control flow content
---@param base_indent string The base indentation
---@param config table Formatter config
---@return string Formatted control flow block
format_control_flow_block = function(content, base_indent, config)
  local parsed = parse_control_flow(content)
  if not parsed then
    -- Can't parse, return as-is with base indentation
    local trimmed = content:match("^%s*(.-)%s*$")
    return base_indent .. trimmed
  end

  local indent_str = string.rep(" ", config.indent_size)
  local lines = {}

  -- Helper to format body content (recursively format template content)
  local function format_body(body, indent)
    if not body then
      return {}
    end

    local result = {}
    -- Tokenize the body content
    local body_tokens = M.tokenize(body)

    -- Use a simplified formatting for the body
    local body_formatted = M.format(body, config)

    -- Split into lines and add proper indentation
    for line in body_formatted:gmatch("[^\n]*") do
      if line:match("%S") then
        table.insert(result, indent .. line)
      elseif #result > 0 then
        -- Preserve blank lines within content
        table.insert(result, "")
      end
    end

    return result
  end

  -- Special case: @{ } code block - keep @{ together
  if parsed.keyword == "" and parsed.header == "@" then
    table.insert(lines, base_indent .. "@{")
    local body_lines = format_body(parsed.body, base_indent .. indent_str)
    for _, line in ipairs(body_lines) do
      table.insert(lines, line)
    end
    table.insert(lines, base_indent .. "}")
    return table.concat(lines, "\n")
  end

  -- Main block
  table.insert(lines, base_indent .. parsed.header)
  table.insert(lines, base_indent .. "{")
  local body_lines = format_body(parsed.body, base_indent .. indent_str)
  for _, line in ipairs(body_lines) do
    table.insert(lines, line)
  end
  table.insert(lines, base_indent .. "}")

  -- Chained blocks
  for _, chain in ipairs(parsed.chains) do
    if chain.is_do_while then
      -- do-while: "while (condition);" on same line as closing brace
      lines[#lines] = base_indent .. "}" .. " " .. chain.header .. ";"
    else
      table.insert(lines, base_indent .. chain.header)
      table.insert(lines, base_indent .. "{")
      local chain_body_lines = format_body(chain.body, base_indent .. indent_str)
      for _, line in ipairs(chain_body_lines) do
        table.insert(lines, line)
      end
      table.insert(lines, base_indent .. "}")
    end
  end

  return table.concat(lines, "\n")
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

    -- Try Razor control flow block first
    if c == "@" then
      local block_end = try_consume_control_flow(text, pos)
      if block_end then
        table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_BLOCK, content = text:sub(pos, block_end) })
        pos = block_end + 1
        goto continue
      end

      -- Try line directive
      local line_end = try_consume_line_directive(text, pos)
      if line_end then
        table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_LINE, content = text:sub(pos, line_end) })
        pos = line_end + 1
        goto continue
      end
    end

    -- HTML comment
    if text:sub(pos, pos + 3) == "<!--" then
      local end_marker = text:find("-->", pos + 4, true)
      if end_marker then
        table.insert(tokens, { type = M.TOKEN_TYPES.COMMENT, content = text:sub(pos, end_marker + 2) })
        pos = end_marker + 3
      else
        table.insert(tokens, { type = M.TOKEN_TYPES.COMMENT, content = text:sub(pos) })
        break
      end
      goto continue
    end

    -- DOCTYPE
    if text:sub(pos, pos + 8):upper() == "<!DOCTYPE" then
      local end_marker = text:find(">", pos, true)
      if end_marker then
        table.insert(tokens, { type = M.TOKEN_TYPES.DOCTYPE, content = text:sub(pos, end_marker) })
        pos = end_marker + 1
      else
        table.insert(tokens, { type = M.TOKEN_TYPES.DOCTYPE, content = text:sub(pos) })
        break
      end
      goto continue
    end

    -- Closing tag
    if text:sub(pos, pos + 1) == "</" then
      local end_marker = text:find(">", pos, true)
      if end_marker then
        local tag_name = text:sub(pos + 2, end_marker - 1):match("^%s*([%w%-]+)")
        if tag_name then
          table.insert(tokens, { type = M.TOKEN_TYPES.TAG_CLOSE, tag = tag_name, content = text:sub(pos, end_marker) })
        else
          table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = text:sub(pos, end_marker) })
        end
        pos = end_marker + 1
      else
        table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = text:sub(pos) })
        break
      end
      goto continue
    end

    -- Opening tag (must start with letter after <)
    if c == "<" and text:sub(pos + 1, pos + 1):match("[%a]") then
      -- Find end of tag, handling quoted attributes with Razor expressions
      local tag_end = nil
      local search_pos = pos + 1
      local in_quote = nil

      while search_pos <= len do
        local sc = text:sub(search_pos, search_pos)
        if in_quote then
          if sc == in_quote then
            in_quote = nil
          elseif sc == "@" then
            -- Razor expression inside attribute - need to skip it properly
            search_pos = search_pos + 1
            if search_pos <= len then
              local next_c = text:sub(search_pos, search_pos)
              if next_c == "(" then
                -- @(...) - skip to matching paren
                search_pos = search_pos + 1
                local depth = 1
                local in_string = nil
                while search_pos <= len and depth > 0 do
                  local pc = text:sub(search_pos, search_pos)
                  if in_string then
                    if pc == in_string and text:sub(search_pos - 1, search_pos - 1) ~= "\\" then
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
                  search_pos = search_pos + 1
                end
                -- Don't increment again at end of loop
                search_pos = search_pos - 1
              elseif next_c == "[" then
                -- @[...] - indexer, skip to matching bracket
                search_pos = search_pos + 1
                local depth = 1
                local in_string = nil
                while search_pos <= len and depth > 0 do
                  local bc = text:sub(search_pos, search_pos)
                  if in_string then
                    if bc == in_string and text:sub(search_pos - 1, search_pos - 1) ~= "\\" then
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
                  search_pos = search_pos + 1
                end
                search_pos = search_pos - 1
              elseif next_c:match("[%a_]") then
                -- @Identifier - consume identifier then check for chained access
                while search_pos <= len and text:sub(search_pos, search_pos):match("[%w_]") do
                  search_pos = search_pos + 1
                end
                -- Check for chained member access, indexers, or method calls
                while search_pos <= len do
                  local chain_c = text:sub(search_pos, search_pos)
                  if chain_c == "." then
                    search_pos = search_pos + 1
                    while search_pos <= len and text:sub(search_pos, search_pos):match("[%w_]") do
                      search_pos = search_pos + 1
                    end
                  elseif chain_c == "[" then
                    search_pos = search_pos + 1
                    local depth = 1
                    local in_string = nil
                    while search_pos <= len and depth > 0 do
                      local bc = text:sub(search_pos, search_pos)
                      if in_string then
                        if bc == in_string and text:sub(search_pos - 1, search_pos - 1) ~= "\\" then
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
                      search_pos = search_pos + 1
                    end
                  elseif chain_c == "(" then
                    search_pos = search_pos + 1
                    local depth = 1
                    local in_string = nil
                    while search_pos <= len and depth > 0 do
                      local pc = text:sub(search_pos, search_pos)
                      if in_string then
                        if pc == in_string and text:sub(search_pos - 1, search_pos - 1) ~= "\\" then
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
                      search_pos = search_pos + 1
                    end
                  else
                    break
                  end
                end
                search_pos = search_pos - 1
              end
            end
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
      goto continue
    end

    -- Plain text - consume until next special character or end
    -- Special characters: < (tags), @ (only if followed by control flow keyword or directive)
    local text_end = pos
    while text_end <= len do
      local tc = text:sub(text_end, text_end)
      if tc == "<" then
        break
      elseif tc == "@" then
        -- Check if this @ starts a control flow or line directive
        if try_consume_control_flow(text, text_end) or try_consume_line_directive(text, text_end) then
          break
        end
        -- Otherwise, @ is just text (inline expression like @User.Name)
        text_end = text_end + 1
      else
        text_end = text_end + 1
      end
    end

    if text_end > pos then
      table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = text:sub(pos, text_end - 1) })
      pos = text_end
    else
      -- Safety: advance by 1 to prevent infinite loop
      table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = text:sub(pos, pos) })
      pos = pos + 1
    end

    ::continue::
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
  local had_directive = false  -- Track if we've seen a directive at root level
  local had_first_tag = false  -- Track if we've seen the first HTML tag at root level
  local last_was_razor_block = false  -- Track if previous output was a Razor block
  local just_opened_tag = false  -- Track if we just opened a block tag (to avoid blank line as first child)

  local function get_indent()
    return string.rep(indent_str, indent_level)
  end

  local function add_line(content)
    if content and content ~= "" then
      table.insert(output, content)
    end
  end

  local function add_blank_line()
    -- Add blank line only if last line wasn't already blank
    if #output > 0 and output[#output] ~= "" then
      table.insert(output, "")
    end
  end

  --- Check if token is inline (single line, no block structure)
  local function is_inline(token)
    if token.type == M.TOKEN_TYPES.TEXT then
      return not token.content:find("\n")
    end
    return false
  end

  --- Check if token is whitespace-only TEXT
  local function is_whitespace_only(token)
    if token.type == M.TOKEN_TYPES.TEXT then
      return token.content:match("^%s*$") ~= nil
    end
    return false
  end

  local i = 1
  while i <= #tokens do
    local token = tokens[i]
    local indent = get_indent()

    if token.type == M.TOKEN_TYPES.DOCTYPE then
      add_line(token.content)

    elseif token.type == M.TOKEN_TYPES.COMMENT then
      add_line(indent .. token.content)

    elseif token.type == M.TOKEN_TYPES.RAZOR_LINE then
      -- Line directives at root level get no indent
      local trimmed = token.content:match("^%s*(.-)%s*$")
      if indent_level == 0 then
        add_line(trimmed)
        had_directive = true
      else
        add_line(indent .. trimmed)
      end

    elseif token.type == M.TOKEN_TYPES.RAZOR_BLOCK then
      -- Add blank line before Razor block (if there's content before it and not first child)
      if #output > 0 and not just_opened_tag then
        add_blank_line()
      end
      just_opened_tag = false

      -- Try to format control flow block with proper structure
      local formatted = format_control_flow_block(token.content, indent, config)

      -- Add the formatted block (may be multi-line)
      for line in formatted:gmatch("[^\n]*") do
        if line ~= "" then
          add_line(line)
        elseif #output > 0 then
          add_line("")
        end
      end

      -- Mark that we just output a Razor block (for adding blank line after)
      last_was_razor_block = true
      last_was_razor_block = true

    elseif token.type == M.TOKEN_TYPES.TAG_SELF_CLOSE then
      -- Add blank line after previous Razor block
      if last_was_razor_block then
        add_blank_line()
        last_was_razor_block = false
      end
      -- Add blank line before first HTML tag if we had directives
      if had_directive and not had_first_tag and indent_level == 0 then
        add_blank_line()
        had_first_tag = true
      end
      just_opened_tag = false
      local formatted = M.format_attributes_stacked(token.attributes, token.tag, indent, true, config)
      -- Handle multi-line formatted output (stacked attributes)
      for line in formatted:gmatch("[^\n]*") do
        if line ~= "" then
          add_line(indent .. line)
        end
      end

    elseif token.type == M.TOKEN_TYPES.TAG_OPEN then
      -- Add blank line after previous Razor block
      if last_was_razor_block then
        add_blank_line()
        last_was_razor_block = false
      end
      -- Add blank line before first HTML tag if we had directives
      if had_directive and not had_first_tag and indent_level == 0 then
        add_blank_line()
        had_first_tag = true
      end
      just_opened_tag = false
      local tag_lower = token.tag:lower()

      -- Look ahead to see if this tag has only inline text content
      local has_only_inline = true
      local inline_parts = {}
      local j = i + 1
      local close_idx = nil

      while j <= #tokens do
        local t = tokens[j]
        if t.type == M.TOKEN_TYPES.TAG_CLOSE and t.tag and t.tag:lower() == tag_lower then
          close_idx = j
          break
        elseif t.type == M.TOKEN_TYPES.TAG_OPEN or t.type == M.TOKEN_TYPES.TAG_SELF_CLOSE or
               t.type == M.TOKEN_TYPES.RAZOR_BLOCK then
          has_only_inline = false
          break
        elseif is_inline(t) then
          local part = t.content:match("^%s*(.-)%s*$")
          if part and part ~= "" then
            table.insert(inline_parts, part)
          end
          j = j + 1
        else
          has_only_inline = false
          break
        end
      end

      if has_only_inline and close_idx and #inline_parts > 0 then
        -- Single line: <tag attrs>content</tag> - force inline formatting
        local formatted = M.format_attributes_stacked(token.attributes, token.tag, indent, false, config, true)
        local inline_content = table.concat(inline_parts, " ")
        add_line(indent .. formatted .. inline_content .. "</" .. token.tag .. ">")
        i = close_idx
      elseif has_only_inline and close_idx and #inline_parts == 0 then
        -- Empty tag - force inline formatting
        local formatted = M.format_attributes_stacked(token.attributes, token.tag, indent, false, config, true)
        add_line(indent .. formatted .. "</" .. token.tag .. ">")
        i = close_idx
      elseif M.PRESERVE_CONTENT_ELEMENTS[tag_lower] then
        -- Preserve content exactly (script, style, pre, textarea) - force inline
        local formatted = M.format_attributes_stacked(token.attributes, token.tag, indent, false, config, true)
        local content_parts = {}
        local content_start = i + 1
        local content_end = content_start
        while content_end <= #tokens do
          local next_token = tokens[content_end]
          if next_token.type == M.TOKEN_TYPES.TAG_CLOSE and next_token.tag and next_token.tag:lower() == tag_lower then
            break
          end
          table.insert(content_parts, next_token.content)
          content_end = content_end + 1
        end
        -- Output opening tag + content + closing tag, preserving exact content
        local preserved_content = table.concat(content_parts)
        add_line(indent .. formatted .. preserved_content .. "</" .. token.tag .. ">")
        i = content_end
      else
        -- Block tag with children - stack attributes
        local formatted = M.format_attributes_stacked(token.attributes, token.tag, indent, false, config)
        -- Handle multi-line formatted output
        for line in formatted:gmatch("[^\n]*") do
          if line ~= "" then
            add_line(indent .. line)
          end
        end
        indent_level = indent_level + 1
        just_opened_tag = true
      end

    elseif token.type == M.TOKEN_TYPES.TAG_CLOSE then
      -- Don't add blank line before closing tag, just reset the flag
      last_was_razor_block = false
      just_opened_tag = false
      indent_level = math.max(0, indent_level - 1)
      indent = get_indent()
      add_line(indent .. "</" .. token.tag .. ">")

    elseif token.type == M.TOKEN_TYPES.TEXT then
      -- Add blank line after previous Razor block (only if this text has content)
      local trimmed = token.content:match("^%s*(.-)%s*$")
      if trimmed and trimmed ~= "" then
        if last_was_razor_block then
          add_blank_line()
          last_was_razor_block = false
        end
        just_opened_tag = false
        add_line(indent .. trimmed)
      else
        -- Whitespace-only text doesn't reset just_opened_tag
        last_was_razor_block = false
      end
    end

    i = i + 1
  end

  return table.concat(output, "\n")
end

return M
