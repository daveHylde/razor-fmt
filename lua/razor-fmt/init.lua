-- razor-fmt: Razor file formatter for Neovim
-- Formats @code{} blocks with CSharpier and HTML with LSP

local M = {}

M.config = {
  -- Indentation for C# code inside @code{} blocks
  indent_size = 4,
  -- Add blank line before @code{} block
  blank_line_before_code = true,
  -- Format HTML with LSP (requires html LSP attached)
  format_html = true,
}

--- Find all @code{} blocks in the buffer using pattern matching
--- Returns a list of { start_line, end_line, content } tables (1-indexed)
---@param lines string[]
---@return table[]
local function find_code_blocks(lines)
  local blocks = {}
  local in_code_block = false
  local brace_count = 0
  local block_start = nil
  local block_content = {}

  for i, line in ipairs(lines) do
    if not in_code_block then
      local code_start = line:match("@code%s*{")
      if code_start then
        in_code_block = true
        block_start = i
        for _ in line:gmatch("{") do
          brace_count = brace_count + 1
        end
        for _ in line:gmatch("}") do
          brace_count = brace_count - 1
        end
        table.insert(block_content, line)
      end
    else
      for _ in line:gmatch("{") do
        brace_count = brace_count + 1
      end
      for _ in line:gmatch("}") do
        brace_count = brace_count - 1
      end
      table.insert(block_content, line)

      if brace_count == 0 then
        table.insert(blocks, {
          start_line = block_start,
          end_line = i,
          content = table.concat(block_content, "\n"),
        })
        in_code_block = false
        block_content = {}
        block_start = nil
      end
    end
  end

  return blocks
end

--- Extract the C# code from inside @code{} block (without the @code wrapper)
---@param block_content string
---@return string
local function extract_csharp_code(block_content)
  local code = block_content:gsub("^%s*@code%s*{", "")
  code = code:gsub("}%s*$", "")
  return code
end

--- Wrap formatted C# code back in @code{} block with proper indentation
---@param formatted_code string
---@return string
local function wrap_in_code_block(formatted_code)
  formatted_code = formatted_code:gsub("%s+$", "")
  local indent = string.rep(" ", M.config.indent_size)
  local indented_lines = {}
  local lines = vim.split(formatted_code, "\n", { plain = true })
  for _, line in ipairs(lines) do
    if line ~= "" then
      table.insert(indented_lines, indent .. line)
    else
      table.insert(indented_lines, "")
    end
  end
  return "@code {\n" .. table.concat(indented_lines, "\n") .. "\n}"
end

--- Run a shell command with stdin and return stdout
---@param cmd string
---@param args string[]
---@param input string
---@return string|nil output
---@return string|nil error
local function run_formatter(cmd, args, input)
  if vim.fn.executable(cmd) ~= 1 then
    return nil, cmd .. " not found in PATH"
  end

  local Job = require("plenary.job")
  local result = nil
  local error_msg = nil

  Job:new({
    command = cmd,
    args = args,
    writer = input,
    on_exit = function(j, return_val)
      if return_val == 0 then
        result = table.concat(j:result(), "\n")
      else
        error_msg = table.concat(j:stderr_result(), "\n")
      end
    end,
  }):sync(10000)

  return result, error_msg
end

--- Format C# code using CSharpier
---@param code string
---@return string|nil, string|nil
local function format_with_csharpier(code)
  local wrapped = "public class __RazorCodeBlock__\n{\n" .. code .. "\n}"

  local result, error_msg = run_formatter("csharpier", { "format", "--write-stdout" }, wrapped)

  if error_msg then
    return nil, error_msg
  end

  if result then
    local result_lines = vim.split(result, "\n", { plain = true })

    local start_idx = nil
    local end_idx = nil

    for i, line in ipairs(result_lines) do
      if line:match("^public%s+class%s+__RazorCodeBlock__") then
        start_idx = i + 1
      elseif start_idx and line:match("^{%s*$") and not end_idx then
        start_idx = i + 1
      end
    end

    for i = #result_lines, 1, -1 do
      if result_lines[i]:match("^}%s*$") then
        end_idx = i - 1
        break
      end
    end

    if start_idx and end_idx and end_idx >= start_idx then
      local content_lines = {}
      for i = start_idx, end_idx do
        local line = result_lines[i]
        local dedented = line:gsub("^    ", "")
        table.insert(content_lines, dedented)
      end
      result = table.concat(content_lines, "\n")
    end
  end

  return result, nil
end

--- Format Razor content - formats @code{} blocks with CSharpier
---@param input string
---@return string|nil formatted
---@return string|nil error
function M.format(input)
  local lines = vim.split(input, "\n", { plain = true })
  local code_blocks = find_code_blocks(lines)

  if #code_blocks == 0 then
    return input, nil
  end

  local result_lines = vim.deepcopy(lines)

  table.sort(code_blocks, function(a, b)
    return a.start_line > b.start_line
  end)

  for _, block in ipairs(code_blocks) do
    local csharp_code = extract_csharp_code(block.content)
    local formatted_csharp, err = format_with_csharpier(csharp_code)

    if err then
      vim.notify("CSharpier error: " .. err, vim.log.levels.WARN)
    elseif formatted_csharp then
      local new_block = wrap_in_code_block(formatted_csharp)
      local new_block_lines = vim.split(new_block, "\n", { plain = true })

      local need_blank_line = false
      if M.config.blank_line_before_code then
        local line_before_idx = block.start_line - 1
        if line_before_idx >= 1 then
          local line_before = result_lines[line_before_idx]
          if line_before and line_before ~= "" then
            need_blank_line = true
          end
        end
      end

      for i = block.end_line, block.start_line, -1 do
        table.remove(result_lines, i)
      end

      if need_blank_line then
        table.insert(result_lines, block.start_line, "")
      end

      local insert_offset = need_blank_line and 1 or 0
      for i, line in ipairs(new_block_lines) do
        table.insert(result_lines, block.start_line + insert_offset + i - 1, line)
      end
    end
  end

  return table.concat(result_lines, "\n"), nil
end

--- Format HTML range using LSP
---@param bufnr number
---@param start_line number 0-indexed
---@param end_line number 0-indexed (exclusive)
---@param callback fun()
local function format_html_range_with_lsp(bufnr, start_line, end_line, callback)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  local html_client = nil
  for _, client in ipairs(clients) do
    if client.name == "html" or client.name == "vscode-html-language-server" or client.name == "htmlls" then
      html_client = client
      break
    end
  end

  if not html_client then
    callback()
    return
  end

  vim.lsp.buf.format({
    bufnr = bufnr,
    async = true,
    range = {
      ["start"] = { start_line + 1, 0 },
      ["end"] = { end_line, 0 },
    },
    filter = function(client)
      return client.name == html_client.name
    end,
  })

  vim.defer_fn(callback, 100)
end

--- Format the current buffer (with optional HTML LSP support)
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

    if M.config.format_html then
      local code_blocks = find_code_blocks(new_lines)

      if #code_blocks == 0 then
        format_html_range_with_lsp(bufnr, 0, #new_lines, function()
          vim.notify("Razor file formatted", vim.log.levels.INFO)
        end)
      else
        local first_block = code_blocks[1]
        for _, block in ipairs(code_blocks) do
          if block.start_line < first_block.start_line then
            first_block = block
          end
        end

        if first_block.start_line > 1 then
          local html_end_line = first_block.start_line - 2
          if html_end_line >= 1 then
            format_html_range_with_lsp(bufnr, 0, html_end_line, function()
              vim.notify("Razor file formatted", vim.log.levels.INFO)
            end)
          else
            vim.notify("Razor file formatted", vim.log.levels.INFO)
          end
        else
          vim.notify("Razor file formatted", vim.log.levels.INFO)
        end
      end
    else
      vim.notify("Razor file formatted", vim.log.levels.INFO)
    end
  end
end

--- Setup the plugin
---@param opts table|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.api.nvim_create_user_command("RazorFormat", function()
    M.format_buffer()
  end, { desc = "Format Razor file with CSharpier and HTML LSP" })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "razor" },
    callback = function(ev)
      vim.keymap.set("n", "<leader>fr", function()
        M.format_buffer(ev.buf)
      end, { buffer = ev.buf, desc = "Format Razor file" })
    end,
  })
end

--- Get conform.nvim formatter specification
---@return table
function M.get_conform_formatter()
  return {
    meta = {
      url = "https://github.com/davidosomething/razor-fmt",
      description = "Razor formatter: CSharpier for @code{} blocks",
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
