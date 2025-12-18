-- razor-fmt/html/constants.lua
-- Constants for HTML tokenizer and formatter

local M = {}

--- HTML void elements (self-closing, no end tag)
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

--- Elements that should preserve their content as-is
M.PRESERVE_CONTENT_ELEMENTS = {
  script = true,
  style = true,
  pre = true,
  textarea = true,
}

--- Token types for the HTML/Razor tokenizer
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

--- Razor line directives (consume entire line)
M.LINE_DIRECTIVES = {
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

--- Razor control flow keywords (have blocks)
M.CONTROL_FLOW_KEYWORDS = {
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

return M
