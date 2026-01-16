-- razor-fmt/html/formatter.lua
-- HTML formatter with JetBrains Rider-style formatting

local constants = require("razor-fmt.html.constants")
local attributes = require("razor-fmt.html.attributes")
local razor = require("razor-fmt.html.razor")
local tokenizer = require("razor-fmt.html.tokenizer")
local css = require("razor-fmt.css")

local M = {}

local TOKEN_TYPES = constants.TOKEN_TYPES
local PRESERVE_CONTENT_ELEMENTS = constants.PRESERVE_CONTENT_ELEMENTS

--- Calculate the inline length of a tag with all its attributes
---@param tag_name string
---@param attrs table[]
---@param is_self_closing boolean
---@return number
local function calculate_inline_length(tag_name, attrs, is_self_closing)
  -- Start with: <tagname
  local length = 1 + #tag_name
  
  -- Add each attribute: space + name + = + quote + value + quote
  for _, attr in ipairs(attrs) do
    if attr.value then
      length = length + 1 + #attr.name + 1 + 1 + #attr.value + 1  -- " name="value""
    else
      length = length + 1 + #attr.name  -- " name"
    end
  end
  
  -- Add closing: " />" or ">"
  if is_self_closing then
    length = length + 3  -- " />"
  else
    length = length + 1  -- ">"
  end
  
  return length
end

--- Check if attributes should be stacked based on config
---@param attrs table[]
---@param tag_name string
---@param is_self_closing boolean
---@param config table
---@param indent_chars number Current indentation in characters
---@return boolean
local function should_stack_attributes(attrs, tag_name, is_self_closing, config, indent_chars)
  if #attrs == 0 then
    return false
  end
  
  local max_attrs = config.max_attributes_per_line
  local max_line_length = config.max_line_length or 0
  
  -- Check attribute count
  if #attrs > max_attrs then
    return true
  end
  
  -- Check line length
  if max_line_length > 0 then
    local inline_length = calculate_inline_length(tag_name, attrs, is_self_closing)
    if indent_chars + inline_length > max_line_length then
      return true
    end
  end
  
  return false
end

-- Forward declaration
local format_control_flow_block

--- Format a control flow block with proper indentation
--- Brackets on their own line, body indented and recursively formatted
---@param content string The raw control flow content
---@param base_indent string The base indentation
---@param config table Formatter config
---@return string Formatted control flow block
format_control_flow_block = function(content, base_indent, config)
  local parsed = razor.parse_control_flow(content)
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
     
     -- First, normalize the body indentation by removing common leading whitespace
     -- This is necessary because the body retains its original source indentation
     local body_lines = {}
     local min_body_indent = nil
     for line in body:gmatch("[^\n]*") do
       table.insert(body_lines, line)
       if line:match("%S") then  -- Only check non-blank lines
         local spaces = line:match("^( *)")
         local count = spaces and #spaces or 0
         if min_body_indent == nil or count < min_body_indent then
           min_body_indent = count
         end
       end
     end
     
     min_body_indent = min_body_indent or 0
     
     -- Remove the common leading whitespace from the body
     local normalized_body = {}
     for _, line in ipairs(body_lines) do
       if line:match("%S") then
         table.insert(normalized_body, line:sub(min_body_indent + 1))
       elseif #normalized_body > 0 then
         table.insert(normalized_body, "")
       end
     end
     
     local body_normalized = table.concat(normalized_body, "\n")
     
     -- Now format the normalized body
     local body_formatted = M.format(body_normalized, config)

     -- Split into lines and add proper indentation
     for line in body_formatted:gmatch("[^\n]*") do
       if line:match("%S") then
         -- The formatted body starts at indent level 0, so we just need to apply our indent
         table.insert(result, indent .. line)
       elseif #result > 0 then
         -- Preserve blank lines within content
         table.insert(result, "")
       end
     end

     return result
   end
  
  -- Helper to format a switch case's content (HTML mixed with break statement)
  local function format_switch_case_content(case_content, indent)
    local result = {}
    
    -- Split the content to separate the break statement from HTML
    -- The content may end with "break;" which we want to preserve
    local trimmed = case_content:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
      return result
    end
    
    -- Check if it ends with break;
    local main_content, has_break = trimmed:match("^(.-)%s*(break%s*;)%s*$")
    if not main_content then
      main_content = trimmed
      has_break = nil
    end
    
     -- Format the main HTML content
     if main_content and main_content:match("%S") then
       -- Normalize the content indentation by removing common leading whitespace
       local content_lines = {}
       local min_content_indent = nil
       for line in main_content:gmatch("[^\n]*") do
         table.insert(content_lines, line)
         if line:match("%S") then  -- Only check non-blank lines
           local spaces = line:match("^( *)")
           local count = spaces and #spaces or 0
           if min_content_indent == nil or count < min_content_indent then
             min_content_indent = count
           end
         end
       end
       
       min_content_indent = min_content_indent or 0
       
       -- Remove the common leading whitespace
       local normalized_content = {}
       for _, line in ipairs(content_lines) do
         if line:match("%S") then
           table.insert(normalized_content, line:sub(min_content_indent + 1))
         elseif #normalized_content > 0 then
           table.insert(normalized_content, "")
         end
       end
       
       local content_normalized = table.concat(normalized_content, "\n")
       local formatted = M.format(content_normalized, config)
       
       for line in formatted:gmatch("[^\n]*") do
         if line:match("%S") then
           table.insert(result, indent .. line)
         elseif #result > 0 then
           table.insert(result, "")
         end
       end
     end
    
    -- Add break statement
    if has_break then
      table.insert(result, indent .. "break;")
    end
    
    return result
  end

   -- Special case: @{ } code block - format with CSharpier if available
   if parsed.keyword == "" and parsed.header == "@" then
     table.insert(lines, base_indent .. "@{")
     
     -- Try to format the C# code with CSharpier
     local csharp_available, csharp = pcall(require, "razor-fmt.csharp")
     local formatted_csharp = nil
     
     if csharp_available then
       formatted_csharp, _ = csharp.format(parsed.body)
     end
     
     if formatted_csharp then
       -- CSharpier formatted it successfully - use the formatted version
       local csharp_lines = vim.split(formatted_csharp, "\n", { plain = true })
       for _, line in ipairs(csharp_lines) do
         if line:match("%S") then
           table.insert(lines, base_indent .. indent_str .. line)
         else
           table.insert(lines, "")
         end
       end
     else
       -- CSharpier not available or errored - fall back to HTML formatting
       -- but at least normalize the indentation
       local body_lines = format_body(parsed.body, base_indent .. indent_str)
       for _, line in ipairs(body_lines) do
         table.insert(lines, line)
       end
     end
     
     table.insert(lines, base_indent .. "}")
     return table.concat(lines, "\n")
   end
  
  -- Special case: @switch - need to handle case/default labels specially
  if parsed.keyword == "switch" then
    table.insert(lines, base_indent .. parsed.header)
    table.insert(lines, base_indent .. "{")
    
    -- Parse the switch body into cases
    local cases = razor.parse_switch_cases(parsed.body)
    local case_indent = base_indent .. indent_str
    local body_indent = base_indent .. indent_str .. indent_str
    
    for _, case in ipairs(cases) do
      -- Add the case/default label
      table.insert(lines, case_indent .. case.label .. ":")
      
      -- Format and add the case content
      local case_lines = format_switch_case_content(case.content, body_indent)
      for _, line in ipairs(case_lines) do
        table.insert(lines, line)
      end
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

--- Check if token is inline (single line, no block structure)
---@param token table
---@return boolean
local function is_inline(token)
  if token.type == TOKEN_TYPES.TEXT then
    return not token.content:find("\n")
  end
  return false
end

--- Format HTML content with JetBrains Rider-style formatting
---@param input string
---@param config table
---@return string
function M.format(input, config)
  local tokens = tokenizer.tokenize(input)
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
    -- Add blank line only if last line isn't already blank
    if #output > 0 and output[#output] ~= "" then
      table.insert(output, "")
    end
  end

  local i = 1
  while i <= #tokens do
    local token = tokens[i]
    local indent = get_indent()

    if token.type == TOKEN_TYPES.DOCTYPE then
      add_line(token.content)

    elseif token.type == TOKEN_TYPES.COMMENT then
      add_line(indent .. token.content)

    elseif token.type == TOKEN_TYPES.RAZOR_LINE then
      -- Line directives at root level get no indent
      local trimmed = token.content:match("^%s*(.-)%s*$")
      if indent_level == 0 then
        add_line(trimmed)
        had_directive = true
      else
        add_line(indent .. trimmed)
      end

    elseif token.type == TOKEN_TYPES.RAZOR_BLOCK then
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

    elseif token.type == TOKEN_TYPES.TAG_SELF_CLOSE then
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
      local indent_chars = #indent
      local formatted = attributes.format_stacked(token.attributes, token.tag, true, config, false, indent_chars)
      -- Handle multi-line formatted output (stacked attributes)
      for line in formatted:gmatch("[^\n]*") do
        if line ~= "" then
          add_line(indent .. line)
        end
      end

    elseif token.type == TOKEN_TYPES.TAG_OPEN then
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
        if t.type == TOKEN_TYPES.TAG_CLOSE and t.tag and t.tag:lower() == tag_lower then
          close_idx = j
          break
        elseif t.type == TOKEN_TYPES.TAG_OPEN or t.type == TOKEN_TYPES.TAG_SELF_CLOSE or
               t.type == TOKEN_TYPES.RAZOR_BLOCK then
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

      if tag_lower == "style" then
        -- Handle <style> tag - either format with CSS LSP or preserve content
        -- Must check this BEFORE the has_only_inline check to ensure style content is handled properly
        local formatted_tag = attributes.format_stacked(token.attributes, token.tag, false, config, true)
        local content_parts = {}
        local content_start = i + 1
        local content_end = content_start
        while content_end <= #tokens do
          local next_token = tokens[content_end]
          if next_token.type == TOKEN_TYPES.TAG_CLOSE and next_token.tag and next_token.tag:lower() == tag_lower then
            break
          end
          table.insert(content_parts, next_token.content)
          content_end = content_end + 1
        end

        local css_content = table.concat(content_parts)
        local trimmed_css = css_content:match("^%s*(.-)%s*$")

        if config.css and config.css.enabled and trimmed_css and trimmed_css ~= "" then
          -- Format CSS content and output multi-line style block
          local css_indent_size = config.css.indent_size or config.indent_size
          local formatted_css = css.format_for_html(trimmed_css, indent, css_indent_size)
          add_line(indent .. formatted_tag)
          -- Add the formatted CSS lines
          for line in formatted_css:gmatch("[^\n]*") do
            add_line(line)
          end
          add_line(indent .. "</" .. token.tag .. ">")
        else
          -- CSS disabled or empty - preserve content exactly
          add_line(indent .. formatted_tag .. css_content .. "</" .. token.tag .. ">")
        end
        i = content_end
      elseif has_only_inline and close_idx and #inline_parts > 0 then
        -- Single line: <tag attrs>content</tag> - force inline formatting
        local formatted = attributes.format_stacked(token.attributes, token.tag, false, config, true)
        local inline_content = table.concat(inline_parts, " ")
        local indent_chars = #indent
        local should_stack = should_stack_attributes(token.attributes, token.tag, false, config, indent_chars)
        if should_stack then
          -- Stack attributes, but keep content on same line as closing >
          local formatted = attributes.format_stacked(token.attributes, token.tag, false, config, false, indent_chars)
          local formatted_lines = {}
          for line in formatted:gmatch("[^\n]*") do
            if line ~= "" then
              table.insert(formatted_lines, line)
            end
          end
          -- Add all lines except the last one normally
          for idx = 1, #formatted_lines - 1 do
            add_line(indent .. formatted_lines[idx])
          end
          -- Last line is ">" - append content and closing tag to it
          if #formatted_lines > 0 then
            add_line(indent .. formatted_lines[#formatted_lines] .. inline_content .. "</" .. token.tag .. ">")
          end
        else
          -- Few attributes - keep everything inline
          local formatted = attributes.format_stacked(token.attributes, token.tag, false, config, true, indent_chars)
          add_line(indent .. formatted .. inline_content .. "</" .. token.tag .. ">")
        end
        i = close_idx
      elseif has_only_inline and close_idx and #inline_parts == 0 then
        -- Empty tag - stack attributes if many, but keep open/close on same structure
        local indent_chars = #indent
        local should_stack = should_stack_attributes(token.attributes, token.tag, false, config, indent_chars)
        if should_stack then
          -- Stack attributes, closing tag immediately after the >
          local formatted = attributes.format_stacked(token.attributes, token.tag, false, config, false, indent_chars)
          local formatted_lines = {}
          for line in formatted:gmatch("[^\n]*") do
            if line ~= "" then
              table.insert(formatted_lines, line)
            end
          end
          -- Add all lines except the last one normally
          for idx = 1, #formatted_lines - 1 do
            add_line(indent .. formatted_lines[idx])
          end
          -- Last line is ">" - append closing tag to it
          if #formatted_lines > 0 then
            add_line(indent .. formatted_lines[#formatted_lines] .. "</" .. token.tag .. ">")
          end
        else
          -- Few attributes - keep inline
          local formatted = attributes.format_stacked(token.attributes, token.tag, false, config, true, indent_chars)
          add_line(indent .. formatted .. "</" .. token.tag .. ">")
        end
        i = close_idx
      elseif PRESERVE_CONTENT_ELEMENTS[tag_lower] then
        -- Preserve content exactly (script, pre, textarea) - force inline
        local indent_chars = #indent
        local formatted = attributes.format_stacked(token.attributes, token.tag, false, config, true, indent_chars)
        local content_parts = {}
        local content_start = i + 1
        local content_end = content_start
        while content_end <= #tokens do
          local next_token = tokens[content_end]
          if next_token.type == TOKEN_TYPES.TAG_CLOSE and next_token.tag and next_token.tag:lower() == tag_lower then
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
        local indent_chars = #indent
        local formatted = attributes.format_stacked(token.attributes, token.tag, false, config, false, indent_chars)
        -- Handle multi-line formatted output
        for line in formatted:gmatch("[^\n]*") do
          if line ~= "" then
            add_line(indent .. line)
          end
        end
        indent_level = indent_level + 1
        just_opened_tag = true
      end

    elseif token.type == TOKEN_TYPES.TAG_CLOSE then
      -- Don't add blank line before closing tag, just reset the flag
      last_was_razor_block = false
      just_opened_tag = false
      indent_level = math.max(0, indent_level - 1)
      indent = get_indent()
      add_line(indent .. "</" .. token.tag .. ">")

    elseif token.type == TOKEN_TYPES.TEXT then
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
