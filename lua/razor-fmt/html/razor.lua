-- razor-fmt/html/razor.lua
-- Razor-specific parsing: control flow blocks, line directives

local utils = require("razor-fmt.html.utils")
local constants = require("razor-fmt.html.constants")

local M = {}

local find_matching_close = utils.find_matching_close
local extract_brace_content = utils.extract_brace_content
local CONTROL_FLOW_KEYWORDS = constants.CONTROL_FLOW_KEYWORDS
local LINE_DIRECTIVES = constants.LINE_DIRECTIVES

--- Try to consume a Razor control flow block starting at pos
--- Returns end position if this is a control flow block, nil otherwise
---@param text string
---@param pos number Position of the @
---@return number|nil end_pos
function M.try_consume_control_flow(text, pos)
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
function M.try_consume_line_directive(text, pos)
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

--- Parse a control flow block into its components
--- Returns a table with header, body, and chained blocks
---@param content string The full control flow content starting with @
---@return table|nil parsed { keyword, header, body, chains }
function M.parse_control_flow(content)
  local len = #content
  if len == 0 or content:sub(1, 1) ~= "@" then
    return nil
  end

  local pos = 2 -- after @

  -- Check for @{ } code block
  if content:sub(pos, pos) == "{" then
    local body_content = extract_brace_content(content, pos)
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

--- Parse switch body into individual case blocks
--- Returns a list of { label, content } where label is "case X:" or "default:" and content is the case body
---@param body string The switch body content (without outer braces)
---@return table[] cases List of { label, content }
function M.parse_switch_cases(body)
  local cases = {}
  local len = #body
  local pos = 1
  
  -- Skip leading whitespace
  while pos <= len and body:sub(pos, pos):match("%s") do
    pos = pos + 1
  end
  
  while pos <= len do
    -- Look for 'case' or 'default'
    local case_match = body:match("^(case%s+.-):", pos)
    local default_match = body:match("^(default)%s*:", pos)
    
    local label, label_end
    
    if case_match and (not default_match or body:find("^case", pos)) then
      -- Found a case label - need to handle complex patterns like { IsLoading: true }
      -- Find the colon that ends the case label (not inside braces)
      local case_start = pos
      pos = pos + 4 -- skip "case"
      
      -- Skip whitespace after case
      while pos <= len and body:sub(pos, pos):match("%s") do
        pos = pos + 1
      end
      
      -- Now find the end of the case pattern (could contain braces for pattern matching)
      local pattern_start = pos
      local brace_depth = 0
      local in_string = nil
      
      while pos <= len do
        local c = body:sub(pos, pos)
        
        if in_string then
          if c == in_string and body:sub(pos - 1, pos - 1) ~= "\\" then
            in_string = nil
          end
        else
          if c == '"' or c == "'" then
            in_string = c
          elseif c == "{" then
            brace_depth = brace_depth + 1
          elseif c == "}" then
            brace_depth = brace_depth - 1
          elseif c == ":" and brace_depth == 0 then
            -- Found the end of case label
            break
          end
        end
        pos = pos + 1
      end
      
      label = "case " .. body:sub(pattern_start, pos - 1):match("^%s*(.-)%s*$")
      label_end = pos + 1 -- skip the colon
      
    elseif default_match then
      label = "default"
      -- Find the colon
      pos = pos + 7 -- skip "default"
      while pos <= len and body:sub(pos, pos):match("%s") do
        pos = pos + 1
      end
      if body:sub(pos, pos) == ":" then
        label_end = pos + 1
      else
        break -- malformed
      end
    else
      -- No more cases found
      break
    end
    
    pos = label_end
    
    -- Skip whitespace after colon
    while pos <= len and body:sub(pos, pos):match("%s") do
      pos = pos + 1
    end
    
    -- Now find the content until next case/default or end
    local content_start = pos
    local content_end = len
    
    -- Look ahead for next case or default
    local search_pos = pos
    local brace_depth = 0
    local in_string = nil
    
    while search_pos <= len do
      local c = body:sub(search_pos, search_pos)
      
      if in_string then
        if c == in_string and body:sub(search_pos - 1, search_pos - 1) ~= "\\" then
          in_string = nil
        end
      else
        if c == '"' or c == "'" then
          in_string = c
        elseif c == "{" then
          brace_depth = brace_depth + 1
        elseif c == "}" then
          brace_depth = brace_depth - 1
        elseif brace_depth == 0 then
          -- Check if we're at a new case or default (at start of line or after whitespace)
          local rest = body:sub(search_pos)
          if rest:match("^case%s") or rest:match("^default%s*:") then
            content_end = search_pos - 1
            break
          end
        end
      end
      search_pos = search_pos + 1
    end
    
    local content = body:sub(content_start, content_end):match("^(.-)%s*$") or ""
    
    table.insert(cases, {
      label = label,
      content = content,
    })
    
    pos = content_end + 1
    
    -- Skip whitespace before next case
    while pos <= len and body:sub(pos, pos):match("%s") do
      pos = pos + 1
    end
  end
  
  return cases
end

return M
