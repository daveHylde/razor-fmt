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

-- Razor directives that take the rest of the line as argument
M.RAZOR_LINE_DIRECTIVES = {
  inject = true,
  using = true,
  page = true,
  namespace = true,
  inherits = true,
  implements = true,
  attribute = true,
  layout = true,
  typeparam = true,
  model = true,
  addTagHelper = true,
  removeTagHelper = true,
  tagHelperPrefix = true,
}

-- Razor block directives that have a body with braces
M.RAZOR_BLOCK_DIRECTIVES = {
  ["if"] = true,
  ["else"] = true,
  ["for"] = true,
  ["foreach"] = true,
  ["while"] = true,
  ["switch"] = true,
  ["try"] = true,
  ["catch"] = true,
  ["finally"] = true,
  ["lock"] = true,
  functions = true,
  section = true,
}

-- Token types for HTML parsing
M.TOKEN_TYPES = {
  TAG_OPEN = "TAG_OPEN",
  TAG_CLOSE = "TAG_CLOSE",
  TAG_SELF_CLOSE = "TAG_SELF_CLOSE",
  TEXT = "TEXT",
  COMMENT = "COMMENT",
  DOCTYPE = "DOCTYPE",
  RAZOR_DIRECTIVE = "RAZOR_DIRECTIVE",
  RAZOR_BLOCK = "RAZOR_BLOCK",
  RAZOR_EXPRESSION = "RAZOR_EXPRESSION",
  RAZOR_CONTROL = "RAZOR_CONTROL",
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

--- Find matching brace, accounting for nesting and strings
---@param text string
---@param start_pos number
---@param open_char string
---@param close_char string
---@return number|nil
local function find_matching_brace(text, start_pos, open_char, close_char)
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

--- Tokenize HTML content with proper Razor support
---@param html string
---@return table[]
function M.tokenize(html)
  local tokens = {}
  local pos = 1
  local len = #html

  while pos <= len do
    -- Check for Razor constructs
    if html:sub(pos, pos) == "@" then
      local next_char = html:sub(pos + 1, pos + 1)

      -- @@ escape sequence
      if next_char == "@" then
        table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = "@" })
        pos = pos + 2

      -- Razor comment @* *@
      elseif next_char == "*" then
        local end_pos = html:find("%*@", pos + 2)
        if end_pos then
          table.insert(tokens, { type = M.TOKEN_TYPES.COMMENT, content = html:sub(pos, end_pos + 1) })
          pos = end_pos + 2
        else
          table.insert(tokens, { type = M.TOKEN_TYPES.COMMENT, content = html:sub(pos) })
          break
        end

      -- Razor code block @{ }
      elseif next_char == "{" then
        local end_pos = find_matching_brace(html, pos + 2, "{", "}")
        if end_pos then
          table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_BLOCK, content = html:sub(pos, end_pos) })
          pos = end_pos + 1
        else
          table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_BLOCK, content = html:sub(pos) })
          break
        end

      -- Razor expression @( )
      elseif next_char == "(" then
        local end_pos = find_matching_brace(html, pos + 2, "(", ")")
        if end_pos then
          table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_EXPRESSION, content = html:sub(pos, end_pos) })
          pos = end_pos + 1
        else
          table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_EXPRESSION, content = html:sub(pos) })
          break
        end

      -- Razor identifier/directive
      elseif next_char:match("[%a_]") then
        -- Extract the identifier
        local id_end = pos + 1
        while id_end <= len and html:sub(id_end, id_end):match("[%w_]") do
          id_end = id_end + 1
        end
        local identifier = html:sub(pos + 1, id_end - 1)

        -- Check if it's a line directive (@inject, @using, etc.)
        if M.RAZOR_LINE_DIRECTIVES[identifier] then
          -- Capture until end of line
          local line_end = html:find("\n", id_end)
          if line_end then
            table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_DIRECTIVE, content = html:sub(pos, line_end - 1) })
            pos = line_end
          else
            table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_DIRECTIVE, content = html:sub(pos) })
            break
          end

        -- Check if it's a block directive (@if, @foreach, etc.)
        elseif M.RAZOR_BLOCK_DIRECTIVES[identifier] then
          -- For @if, we need to capture the entire if/else if/else chain
          if identifier == "if" then
            -- Find the condition in parentheses
            local paren_start = html:find("%(", id_end)
            if paren_start then
              local paren_end = find_matching_brace(html, paren_start + 1, "(", ")")
              if paren_end then
                id_end = paren_end + 1
              end
            end

            -- Find the first block body
            local brace_start = html:find("{", id_end)
            if brace_start then
              local brace_end = find_matching_brace(html, brace_start + 1, "{", "}")
              if brace_end then
                local block_end = brace_end

                -- Look for else/else if chains
                while true do
                  local after_brace = html:sub(block_end + 1)
                  local else_match = after_brace:match("^%s*else%s*if%s*%(")
                  local else_only_match = after_brace:match("^%s*else%s*{")

                  if else_match then
                    -- else if
                    local else_start = html:find("else", block_end + 1)
                    local paren_s = html:find("%(", else_start)
                    if paren_s then
                      local paren_e = find_matching_brace(html, paren_s + 1, "(", ")")
                      if paren_e then
                        local brace_s = html:find("{", paren_e + 1)
                        if brace_s then
                          local brace_e = find_matching_brace(html, brace_s + 1, "{", "}")
                          if brace_e then
                            block_end = brace_e
                          else
                            break
                          end
                        else
                          break
                        end
                      else
                        break
                      end
                    else
                      break
                    end
                  elseif else_only_match then
                    -- else (no condition)
                    local brace_s = html:find("{", block_end + 1)
                    if brace_s then
                      local brace_e = find_matching_brace(html, brace_s + 1, "{", "}")
                      if brace_e then
                        block_end = brace_e
                      else
                        break
                      end
                    else
                      break
                    end
                  else
                    break
                  end
                end

                table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_CONTROL, content = html:sub(pos, block_end) })
                pos = block_end + 1
              else
                table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_CONTROL, content = html:sub(pos) })
                break
              end
            else
              -- No brace found, treat as simple expression
              table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_EXPRESSION, content = html:sub(pos, id_end - 1) })
              pos = id_end
            end

          -- Skip standalone else/catch/finally - they should be captured with their parent
          elseif identifier == "else" or identifier == "catch" or identifier == "finally" then
            -- These should have been captured with @if/@try, but if we see them alone,
            -- treat as expression to preserve them
            table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = html:sub(pos, id_end - 1) })
            pos = id_end

          else
            -- Other block directives: @foreach, @for, @while, @switch, @try, @lock, @functions, @section
            -- Find the condition in parentheses (if present)
            local after_id = html:sub(id_end)
            local paren_match = after_id:match("^%s*%(")
            if paren_match then
              local paren_start = html:find("%(", id_end)
              if paren_start then
                local paren_end = find_matching_brace(html, paren_start + 1, "(", ")")
                if paren_end then
                  id_end = paren_end + 1
                end
              end
            end

            -- Handle @try with catch/finally
            if identifier == "try" then
              local brace_start = html:find("{", id_end)
              if brace_start then
                local brace_end = find_matching_brace(html, brace_start + 1, "{", "}")
                if brace_end then
                  local block_end = brace_end

                  -- Look for catch/finally chains
                  while true do
                    local after_brace = html:sub(block_end + 1)
                    local catch_match = after_brace:match("^%s*catch%s*%(")
                    local catch_no_paren = after_brace:match("^%s*catch%s*{")
                    local finally_match = after_brace:match("^%s*finally%s*{")

                    if catch_match then
                      local paren_s = html:find("%(", block_end + 1)
                      if paren_s then
                        local paren_e = find_matching_brace(html, paren_s + 1, "(", ")")
                        if paren_e then
                          local brace_s = html:find("{", paren_e + 1)
                          if brace_s then
                            local brace_e = find_matching_brace(html, brace_s + 1, "{", "}")
                            if brace_e then
                              block_end = brace_e
                            else
                              break
                            end
                          else
                            break
                          end
                        else
                          break
                        end
                      else
                        break
                      end
                    elseif catch_no_paren then
                      local brace_s = html:find("{", block_end + 1)
                      if brace_s then
                        local brace_e = find_matching_brace(html, brace_s + 1, "{", "}")
                        if brace_e then
                          block_end = brace_e
                        else
                          break
                        end
                      else
                        break
                      end
                    elseif finally_match then
                      local brace_s = html:find("{", block_end + 1)
                      if brace_s then
                        local brace_e = find_matching_brace(html, brace_s + 1, "{", "}")
                        if brace_e then
                          block_end = brace_e
                        else
                          break
                        end
                      else
                        break
                      end
                    else
                      break
                    end
                  end

                  table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_CONTROL, content = html:sub(pos, block_end) })
                  pos = block_end + 1
                else
                  table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_CONTROL, content = html:sub(pos) })
                  break
                end
              else
                table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_EXPRESSION, content = html:sub(pos, id_end - 1) })
                pos = id_end
              end
            else
              -- Standard block directive
              local brace_start = html:find("{", id_end)
              if brace_start then
                local brace_end = find_matching_brace(html, brace_start + 1, "{", "}")
                if brace_end then
                  table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_CONTROL, content = html:sub(pos, brace_end) })
                  pos = brace_end + 1
                else
                  table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_CONTROL, content = html:sub(pos) })
                  break
                end
              else
                -- No brace found, treat as simple expression
                table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_EXPRESSION, content = html:sub(pos, id_end - 1) })
                pos = id_end
              end
            end
          end

        -- Simple Razor expression @identifier or @identifier.property or @identifier[index] or @identifier(args)
        else
          -- Continue reading member access, indexers, and method calls
          while id_end <= len do
            local c = html:sub(id_end, id_end)
            if c == "." then
              -- Member access
              id_end = id_end + 1
              while id_end <= len and html:sub(id_end, id_end):match("[%w_]") do
                id_end = id_end + 1
              end
            elseif c == "[" then
              -- Indexer
              local bracket_end = find_matching_brace(html, id_end + 1, "[", "]")
              if bracket_end then
                id_end = bracket_end + 1
              else
                break
              end
            elseif c == "(" then
              -- Method call
              local paren_end = find_matching_brace(html, id_end + 1, "(", ")")
              if paren_end then
                id_end = paren_end + 1
              else
                break
              end
            else
              break
            end
          end
          table.insert(tokens, { type = M.TOKEN_TYPES.RAZOR_EXPRESSION, content = html:sub(pos, id_end - 1) })
          pos = id_end
        end

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
    elseif html:sub(pos, pos) == "<" and html:sub(pos + 1, pos + 1):match("[%a]") then
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
        if tag_name then
          local attr_string = tag_content:sub(#tag_name + 1)
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
        local text = html:sub(pos)
        if text ~= "" then
          table.insert(tokens, { type = M.TOKEN_TYPES.TEXT, content = text })
        end
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

    elseif token.type == M.TOKEN_TYPES.RAZOR_DIRECTIVE then
      -- @inject, @using, etc. - preserve as-is on own line
      add_line(token.content)

    elseif token.type == M.TOKEN_TYPES.RAZOR_BLOCK then
      -- @{ } blocks - preserve as-is
      add_line(indent .. token.content)

    elseif token.type == M.TOKEN_TYPES.RAZOR_EXPRESSION then
      -- @variable, @Method() - preserve as-is
      add_line(indent .. token.content)

    elseif token.type == M.TOKEN_TYPES.RAZOR_CONTROL then
      -- @if, @foreach, etc. - preserve as-is (contains full block)
      -- Split by lines and indent appropriately
      local lines = {}
      for line in token.content:gmatch("[^\n]+") do
        table.insert(lines, line)
      end
      for _, line in ipairs(lines) do
        add_line(line)
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
        -- Find the closing tag and preserve everything in between
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
        add_line(indent .. trimmed)
      end
    end

    i = i + 1
  end

  return table.concat(output, "\n")
end

return M
