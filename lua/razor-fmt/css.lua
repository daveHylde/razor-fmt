-- razor-fmt/css.lua
-- CSS formatting using cssls LSP (optional dependency)
-- If cssls is not running, CSS content is re-indented but not reformatted

local M = {}

--- Format CSS code using cssls LSP
---@param css_content string The CSS content to format
---@param indent_size number The indent size to use
---@return string|nil formatted_css
---@return string|nil error
function M.format(css_content, indent_size)
  indent_size = indent_size or 4

  -- Find cssls client
  local clients = vim.lsp.get_clients({ name = "cssls" })
  if #clients == 0 then
    -- Try vscode-css-language-server as alternative name
    clients = vim.lsp.get_clients({ name = "css-lsp" })
  end

  if #clients == 0 then
    -- cssls not available, return content as-is
    return css_content, nil
  end

  local client = clients[1]

  -- Create a temporary buffer with CSS content
  local temp_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(temp_bufnr, "filetype", "css")

  -- Set buffer content
  local lines = vim.split(css_content, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(temp_bufnr, 0, -1, false, lines)

  -- Attach the LSP client to the buffer temporarily
  vim.lsp.buf_attach_client(temp_bufnr, client.id)

  -- Wait a bit for the LSP to process the buffer
  vim.wait(100, function()
    return false
  end)

  -- Request formatting
  local result = nil
  local error_msg = nil
  local done = false

  local params = {
    textDocument = vim.lsp.util.make_text_document_params(temp_bufnr),
    options = {
      tabSize = indent_size,
      insertSpaces = true,
      trimTrailingWhitespace = true,
      insertFinalNewline = false,
      trimFinalNewlines = true,
    },
  }

  client.request("textDocument/formatting", params, function(err, formatting_result)
    if err then
      error_msg = err.message or tostring(err)
    elseif formatting_result and #formatting_result > 0 then
      -- Apply the edits to get the formatted content
      vim.lsp.util.apply_text_edits(formatting_result, temp_bufnr, client.offset_encoding)
      local formatted_lines = vim.api.nvim_buf_get_lines(temp_bufnr, 0, -1, false)
      result = table.concat(formatted_lines, "\n")
    else
      -- No edits returned, content is already formatted
      result = css_content
    end
    done = true
  end, temp_bufnr)

  -- Wait for the response with timeout
  vim.wait(5000, function()
    return done
  end, 10)

  -- Clean up
  vim.lsp.buf_detach_client(temp_bufnr, client.id)
  vim.api.nvim_buf_delete(temp_bufnr, { force = true })

  if not done then
    return css_content, "CSS LSP formatting timeout"
  end

  return result, error_msg
end

--- Format CSS content and re-indent it for embedding in HTML
---@param css_content string The CSS content to format
---@param base_indent string The base indentation for the CSS block
---@param indent_size number The indent size
---@return string formatted_css
function M.format_for_html(css_content, base_indent, indent_size)
  -- First, try to format with cssls
  local formatted, err = M.format(css_content, indent_size)
  if err then
    vim.notify("CSS formatting error: " .. err, vim.log.levels.DEBUG)
  end

  formatted = formatted or css_content

  -- Re-indent the formatted CSS for HTML embedding
  -- Preserve relative indentation structure from the formatted CSS
  local lines = vim.split(formatted, "\n", { plain = true })
  local result_lines = {}
  local indent_str = string.rep(" ", indent_size)

  -- Find minimum indentation in the CSS (excluding blank lines)
  local min_indent = math.huge
  for _, line in ipairs(lines) do
    if line:match("%S") then
      local leading = line:match("^(%s*)")
      min_indent = math.min(min_indent, #leading)
    end
  end
  if min_indent == math.huge then
    min_indent = 0
  end

  for _, line in ipairs(lines) do
    if line:match("%S") then
      -- Remove the common minimum indent and add base + one level
      local stripped = line:sub(min_indent + 1)
      table.insert(result_lines, base_indent .. indent_str .. stripped)
    elseif #result_lines > 0 then
      -- Preserve blank lines within CSS
      table.insert(result_lines, "")
    end
  end

  return table.concat(result_lines, "\n")
end

return M
