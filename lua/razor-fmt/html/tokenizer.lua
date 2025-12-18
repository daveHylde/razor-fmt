-- razor-fmt/html/tokenizer.lua
-- HTML/Razor tokenizer

local constants = require("razor-fmt.html.constants")
local attributes = require("razor-fmt.html.attributes")
local razor = require("razor-fmt.html.razor")

local M = {}

local TOKEN_TYPES = constants.TOKEN_TYPES
local VOID_ELEMENTS = constants.VOID_ELEMENTS

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
      local block_end = razor.try_consume_control_flow(text, pos)
      if block_end then
        table.insert(tokens, { type = TOKEN_TYPES.RAZOR_BLOCK, content = text:sub(pos, block_end) })
        pos = block_end + 1
        goto continue
      end

      -- Try line directive
      local line_end = razor.try_consume_line_directive(text, pos)
      if line_end then
        table.insert(tokens, { type = TOKEN_TYPES.RAZOR_LINE, content = text:sub(pos, line_end) })
        pos = line_end + 1
        goto continue
      end
    end

    -- HTML comment
    if text:sub(pos, pos + 3) == "<!--" then
      local end_marker = text:find("-->", pos + 4, true)
      if end_marker then
        table.insert(tokens, { type = TOKEN_TYPES.COMMENT, content = text:sub(pos, end_marker + 2) })
        pos = end_marker + 3
      else
        table.insert(tokens, { type = TOKEN_TYPES.COMMENT, content = text:sub(pos) })
        break
      end
      goto continue
    end

    -- DOCTYPE
    if text:sub(pos, pos + 8):upper() == "<!DOCTYPE" then
      local end_marker = text:find(">", pos, true)
      if end_marker then
        table.insert(tokens, { type = TOKEN_TYPES.DOCTYPE, content = text:sub(pos, end_marker) })
        pos = end_marker + 1
      else
        table.insert(tokens, { type = TOKEN_TYPES.DOCTYPE, content = text:sub(pos) })
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
          table.insert(tokens, { type = TOKEN_TYPES.TAG_CLOSE, tag = tag_name, content = text:sub(pos, end_marker) })
        else
          table.insert(tokens, { type = TOKEN_TYPES.TEXT, content = text:sub(pos, end_marker) })
        end
        pos = end_marker + 1
      else
        table.insert(tokens, { type = TOKEN_TYPES.TEXT, content = text:sub(pos) })
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
          local is_void = VOID_ELEMENTS[tag_name:lower()]
          local token_type = (is_self_closing or is_void) and TOKEN_TYPES.TAG_SELF_CLOSE or TOKEN_TYPES.TAG_OPEN

          table.insert(tokens, {
            type = token_type,
            tag = tag_name,
            attributes = attributes.parse(attr_string),
            is_void = is_void,
            content = text:sub(pos, tag_end),
          })
        else
          table.insert(tokens, { type = TOKEN_TYPES.TEXT, content = text:sub(pos, tag_end) })
        end
        pos = tag_end + 1
      else
        table.insert(tokens, { type = TOKEN_TYPES.TEXT, content = text:sub(pos) })
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
        if razor.try_consume_control_flow(text, text_end) or razor.try_consume_line_directive(text, text_end) then
          break
        end
        -- Otherwise, @ is just text (inline expression like @User.Name)
        text_end = text_end + 1
      else
        text_end = text_end + 1
      end
    end

    if text_end > pos then
      table.insert(tokens, { type = TOKEN_TYPES.TEXT, content = text:sub(pos, text_end - 1) })
      pos = text_end
    else
      -- Safety: advance by 1 to prevent infinite loop
      table.insert(tokens, { type = TOKEN_TYPES.TEXT, content = text:sub(pos, pos) })
      pos = pos + 1
    end

    ::continue::
  end

  return tokens
end

return M
