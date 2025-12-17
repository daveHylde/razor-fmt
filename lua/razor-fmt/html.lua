-- razor-fmt/html.lua
-- HTML tokenizer and formatter with JetBrains Rider-style defaults

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

-- Inline elements that shouldn't force newlines
M.INLINE_ELEMENTS = {
  a = true,
  abbr = true,
  acronym = true,
  b = true,
  bdo = true,
  big = true,
  br = true,
  button = true,
  cite = true,
  code = true,
  dfn = true,
  em = true,
  i = true,
  img = true,
  input = true,
  kbd = true,
  label = true,
  map = true,
  object = true,
  q = true,
  samp = true,
  script = true,
  select = true,
  small = true,
  span = true,
  strong = true,
  sub = true,
  sup = true,
  textarea = true,
  tt = true,
  var = true,
}

-- Token types for HTML parsing
M.TOKEN_TYPES = {
  TAG_OPEN = "TAG_OPEN",
  TAG_CLOSE = "TAG_CLOSE",
  TAG_SELF_CLOSE = "TAG_SELF_CLOSE",
  TEXT = "TEXT",
  COMMENT = "COMMENT",
  DOCTYPE = "DOCTYPE",
  RAZOR_BLOCK = "RAZOR_BLOCK",
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

    -- Match attribute name (including Blazor @ prefixed attributes and directives)
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

--- Tokenize HTML content
---@param html string
---@return table[]
function M.tokenize(html)
  local tokens = {}
  local pos = 1
  local len = #html

  while pos <= len do
    -- Check for Razor expressions/blocks that should be preserved
    if html:sub(pos, pos) == "@" then
      local next_char = html:sub(pos + 1, pos + 1)
      -- Razor code block @{ }
      if next_char == "{" then
        local brace_count = 1
        local end_pos = pos + 2
        while end_pos <= len and brace_count > 0 do
          local c = html:sub(end_pos, end_pos)
          if c == "{" then
            brace_count = brace_count + 1
          elseif c == "}" then
            brace_count = brace_count - 1
          end
          end_pos = end_pos + 1
        end
        table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_BLOCK, content = html:sub(pos, end_pos - 1) })
        pos = end_pos
      -- Razor expression @( )
      elseif next_char == "(" then
        local paren_count = 1
        local end_pos = pos + 2
        while end_pos <= len and paren_count > 0 do
          local c = html:sub(end_pos, end_pos)
          if c == "(" then
            paren_count = paren_count + 1
          elseif c == ")" then
            paren_count = paren_count - 1
          end
          end_pos = end_pos + 1
        end
        table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = html:sub(pos, end_pos - 1) })
        pos = end_pos
      -- Razor identifier @identifier
      elseif next_char:match("[%a_]") then
        local end_pos = pos + 1
        while end_pos <= len and html:sub(end_pos, end_pos):match("[%w_.]") do
          end_pos = end_pos + 1
        end
        table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = html:sub(pos, end_pos - 1) })
        pos = end_pos
      else
        -- Just @ symbol
        table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = "@" })
        pos = pos + 1
      end
    -- Check for HTML comment
    elseif html:sub(pos, pos + 3) == "<!--" then
      local end_pos = html:find("-->", pos + 4, true)
      if end_pos then
        table.insert(tokens, { type = M.TOKEN_TYPES.COMMENT, content = html:sub(pos, end_pos + 2) })
        pos = end_pos + 3
      else
        table.insert(tokens, { type = M.TOKEN_TYPES.COMMENT, content = html:sub(pos) })
        break
      end
    -- Check for DOCTYPE
    elseif html:sub(pos, pos + 8):upper() == "<!DOCTYPE" then
      local end_pos = html:find(">", pos, true)
      if end_pos then
        table.insert(tokens, { type = M.TOKEN_TYPES.DOCTYPE, content = html:sub(pos, end_pos) })
        pos = end_pos + 1
      else
        table.insert(tokens, { type = M.TOKEN_TYPES.DOCTYPE, content = html:sub(pos) })
        break
      end
    -- Check for closing tag
    elseif html:sub(pos, pos + 1) == "</" then
      local end_pos = html:find(">", pos, true)
      if end_pos then
        local tag_content = html:sub(pos + 2, end_pos - 1)
        local tag_name = tag_content:match("^%s*([%w%-]+)")
        table.insert(tokens, { type = M.TOKEN_TYPES.TAG_CLOSE, tag = tag_name, content = html:sub(pos, end_pos) })
        pos = end_pos + 1
      else
        table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = html:sub(pos) })
        break
      end
    -- Check for opening tag
    elseif html:sub(pos, pos) == "<" then
      -- Find the end of the tag (accounting for attributes with > in values)
      local tag_end = nil
      local search_pos = pos + 1
      local in_quote = nil

      while search_pos <= len do
        local c = html:sub(search_pos, search_pos)
        if in_quote then
          if c == in_quote then
            in_quote = nil
          end
        else
          if c == '"' or c == "'" then
            in_quote = c
          elseif c == ">" then
            tag_end = search_pos
            break
          end
        end
        search_pos = search_pos + 1
      end

      if tag_end then
        local tag_content = html:sub(pos + 1, tag_end - 1)
        local is_self_closing = tag_content:match("/%s*$") ~= nil
        if is_self_closing then
          tag_content = tag_content:gsub("/%s*$", "")
        end

        local tag_name = tag_content:match("^([%w%-]+)")
        local attr_string = tag_content:sub(#tag_name + 1)

        if tag_name then
          local is_void = M.VOID_ELEMENTS[tag_name:lower()]
          local token_type = (is_self_closing or is_void) and M.TOKEN_TYPES.TAG_SELF_CLOSE or M.TOKEN_TYPES.TAG_OPEN

          table.insert(tokens, {
            type = token_type,
            tag = tag_name,
            attributes = M.parse_attributes(attr_string),
            is_void = is_void,
            content = html:sub(pos, tag_end),
          })
        else
          table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = html:sub(pos, tag_end) })
        end
        pos = tag_end + 1
      else
        table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = html:sub(pos) })
        break
      end
    -- Text content
    else
      local next_special = html:find("[<@]", pos)
      if next_special then
        local text = html:sub(pos, next_special - 1)
        if text ~= "" then
          table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = text })
        end
        pos = next_special
      else
        table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = html:sub(pos) })
        break
      end
    end
  end

  return tokens
end

--- Format HTML content with JetBrains Rider-style formatting
---@param html string
---@param config table
---@return string
function M.format(html, config)
  local tokens = M.tokenize(html)
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

  local i = 1
  while i <= #tokens do
    local token = tokens[i]
    local indent = get_indent()

    if token.type == M.TOKEN_TYPES.DOCTYPE then
      add_line(token.content)
    elseif token.type == M.TOKEN_TYPES.COMMENT then
      add_line(indent .. token.content)
    elseif token.type == M.TOKEN_TYPES.RAZOR_BLOCK then
      add_line(indent .. token.content)
    elseif token.type == M.TOKEN_TYPES.TAG_SELF_CLOSE then
      local formatted = M.format_attributes_stacked(token.attributes, token.tag, indent, true, config)
      add_line(indent .. formatted)
    elseif token.type == M.TOKEN_TYPES.TAG_OPEN then
      local tag_lower = token.tag:lower()
      local formatted = M.format_attributes_stacked(token.attributes, token.tag, indent, false, config)
      add_line(indent .. formatted)

      -- Check if this is a preserve-content element
      if M.PRESERVE_CONTENT_ELEMENTS[tag_lower] then
        -- Find the closing tag and preserve everything in between
        local content_parts = {}
        i = i + 1
        while i <= #tokens do
          local next_token = tokens[i]
          if next_token.type == M.TOKEN_TYPES.TAG_CLOSE and next_token.tag:lower() == tag_lower then
            break
          end
          table.insert(content_parts, next_token.content)
          i = i + 1
        end
        if #content_parts > 0 then
          add_line(table.concat(content_parts))
        end
        -- Add closing tag
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
      -- Trim and normalize whitespace for non-empty text
      local trimmed = text:match("^%s*(.-)%s*$")
      if trimmed and trimmed ~= "" then
        -- Check if it's just whitespace between tags
        if not text:match("^%s+$") then
          add_line(indent .. trimmed)
        end
      end
    end

    i = i + 1
  end

  return table.concat(output, "\n")
end

return M
