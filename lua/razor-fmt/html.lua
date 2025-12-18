-- razor-fmt/html.lua
-- HTML tokenizer and formatter with JetBrains Rider-style defaults
-- Formats HTML tags, preserves Razor control flow blocks as-is
--
-- This module re-exports from submodules for backward compatibility.
-- The implementation is split across:
--   html/constants.lua   - Token types, element sets, directive keywords
--   html/attributes.lua  - HTML attribute parsing and formatting
--   html/utils.lua       - Balanced construct parsing utilities
--   html/razor.lua       - Razor-specific parsing (control flow, directives)
--   html/tokenizer.lua   - HTML/Razor tokenization
--   html/formatter.lua   - HTML formatting logic

local constants = require("razor-fmt.html.constants")
local attributes = require("razor-fmt.html.attributes")
local tokenizer = require("razor-fmt.html.tokenizer")
local formatter = require("razor-fmt.html.formatter")

local M = {}

-- Re-export constants for backward compatibility
M.VOID_ELEMENTS = constants.VOID_ELEMENTS
M.PRESERVE_CONTENT_ELEMENTS = constants.PRESERVE_CONTENT_ELEMENTS
M.TOKEN_TYPES = constants.TOKEN_TYPES

--- Parse attributes from an attribute string
---@param attr_string string
---@return table[] List of { name, value, quote } tables
function M.parse_attributes(attr_string)
  return attributes.parse(attr_string)
end

--- Format attributes with stacking
---@param attrs table[]
---@param tag_name string
---@param _ string (unused, kept for backward compatibility)
---@param is_self_closing boolean
---@param config table
---@param force_inline boolean|nil If true, don't stack even if many attributes
---@return string
function M.format_attributes_stacked(attrs, tag_name, _, is_self_closing, config, force_inline)
  return attributes.format_stacked(attrs, tag_name, is_self_closing, config, force_inline)
end

--- Tokenize HTML/Razor content
---@param text string
---@return table[]
function M.tokenize(text)
  return tokenizer.tokenize(text)
end

--- Format HTML content with JetBrains Rider-style formatting
---@param input string
---@param config table
---@return string
function M.format(input, config)
  return formatter.format(input, config)
end

return M
