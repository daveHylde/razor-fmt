-- razor-fmt: Razor file formatter for Neovim
-- Formats @code{} blocks with CSharpier and HTML with opinionated formatter

local html = require("razor-fmt.html")
local csharp = require("razor-fmt.csharp")
local parser = require("razor-fmt.parser")

local M = {}

M.config = {
  -- Indentation for C# code inside @code{} blocks
  indent_size = 4,
  -- Add blank line before @code{} block
  blank_line_before_code = true,
  -- Format HTML/template sections
  format_html = true,
  -- HTML formatting options (JetBrains Rider-style defaults)
  html = {
    -- Indent size for HTML
    indent_size = 4,
    -- Max attributes before stacking (0 = always stack when >1 attribute)
    max_attributes_per_line = 1,
  },
}

--- Format Razor content - formats @code{} blocks with CSharpier and HTML with custom formatter
---@param input string
---@return string|nil formatted
---@return string|nil error
function M.format(input)
  local lines = vim.split(input, "\n", { plain = true })
  local code_blocks = parser.find_code_blocks(lines)

  -- First, format HTML regions
  if M.config.format_html then
    local html_regions = parser.find_html_regions(lines, code_blocks)

    -- Format HTML regions in reverse order to preserve line numbers
    table.sort(html_regions, function(a, b)
      return a.start_line > b.start_line
    end)

    for _, region in ipairs(html_regions) do
      local region_lines = {}
      for i = region.start_line, region.end_line do
        table.insert(region_lines, lines[i])
      end
      local region_content = table.concat(region_lines, "\n")

      -- Only format if there's actual content
      if not region_content:match("^%s*$") then
        local formatted_html = html.format(region_content, M.config.html)
        local formatted_lines = vim.split(formatted_html, "\n", { plain = true })

        -- Remove old lines
        for i = region.end_line, region.start_line, -1 do
          table.remove(lines, i)
        end

        -- Insert formatted lines
        for i, line in ipairs(formatted_lines) do
          table.insert(lines, region.start_line + i - 1, line)
        end
      end
    end

    -- Re-find code blocks after HTML formatting (line numbers may have changed)
    code_blocks = parser.find_code_blocks(lines)
  end

  -- Then, format @code{} blocks
  if #code_blocks > 0 then
    table.sort(code_blocks, function(a, b)
      return a.start_line > b.start_line
    end)

    for _, block in ipairs(code_blocks) do
      local csharp_code = csharp.extract_from_block(block.content)
      local formatted_csharp, err = csharp.format(csharp_code)

      if err then
        vim.notify("CSharpier error: " .. err, vim.log.levels.WARN)
      elseif formatted_csharp then
        local new_block = csharp.wrap_in_block(formatted_csharp, M.config.indent_size)
        local new_block_lines = vim.split(new_block, "\n", { plain = true })

        local need_blank_line = false
        if M.config.blank_line_before_code then
          local line_before_idx = block.start_line - 1
          if line_before_idx >= 1 then
            local line_before = lines[line_before_idx]
            if line_before and line_before ~= "" then
              need_blank_line = true
            end
          end
        end

        for i = block.end_line, block.start_line, -1 do
          table.remove(lines, i)
        end

        if need_blank_line then
          table.insert(lines, block.start_line, "")
        end

        local insert_offset = need_blank_line and 1 or 0
        for i, line in ipairs(new_block_lines) do
          table.insert(lines, block.start_line + insert_offset + i - 1, line)
        end
      end
    end
  end

  return table.concat(lines, "\n"), nil
end

--- Format the current buffer
---@param bufnr number|nil
function M.format_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local input = table.concat(lines, "\n")

  local formatted, err = M.format(input)
  if err then
    vim.notify("Razor format error: " .. err, vim.log.levels.ERROR)
    return
  end

  if formatted then
    local new_lines = vim.split(formatted, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
    vim.notify("Razor file formatted", vim.log.levels.INFO)
  end
end

--- Setup the plugin
---@param opts table|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.api.nvim_create_user_command("RazorFormat", function()
    M.format_buffer()
  end, { desc = "Format Razor file with CSharpier and HTML formatter" })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "razor", "cshtml" },
    callback = function(ev)
      vim.keymap.set("n", "<leader>fr", function()
        M.format_buffer(ev.buf)
      end, { buffer = ev.buf, desc = "Format Razor file" })
    end,
  })

  -- Auto-register with conform.nvim if available
  local has_conform, conform = pcall(require, "conform")
  if has_conform then
    conform.formatters.razor_fmt = M.get_conform_formatter()
    -- Auto-register filetypes
    conform.formatters_by_ft.razor = conform.formatters_by_ft.razor or { "razor_fmt" }
    conform.formatters_by_ft.cshtml = conform.formatters_by_ft.cshtml or { "razor_fmt" }
  end
end

--- Get conform.nvim formatter specification
---@return table
function M.get_conform_formatter()
  return {
    meta = {
      url = "https://github.com/daveHylde/razor-fmt",
      description = "Razor formatter: CSharpier for @code{} blocks, opinionated HTML formatter",
    },
    format = function(_, _, lines, callback)
      local input = table.concat(lines, "\n")
      local formatted, err = M.format(input)
      if err then
        callback(err)
      else
        local output_lines = vim.split(formatted or "", "\n", { plain = true })
        callback(nil, output_lines)
      end
    end,
  }
end

return M
