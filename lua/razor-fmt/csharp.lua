-- razor-fmt/csharp.lua
-- CSharpier integration for formatting C# code blocks

local M = {}

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
---@return string|nil formatted_code
---@return string|nil error
function M.format(code)
  local wrapped = "public class __RazorCodeBlock__\n{\n" .. code .. "\n}"

  local result, error_msg = run_formatter("csharpier", { "format", "--write-stdout" }, wrapped)

  if error_msg then
    return nil, error_msg
  end

  if result then
    local result_lines = vim.split(result, "\n", { plain = true })

    local start_idx = nil
    local end_idx = nil

    for idx, line in ipairs(result_lines) do
      if line:match("^public%s+class%s+__RazorCodeBlock__") then
        start_idx = idx + 1
      elseif start_idx and line:match("^{%s*$") and not end_idx then
        start_idx = idx + 1
      end
    end

    for idx = #result_lines, 1, -1 do
      if result_lines[idx]:match("^}%s*$") then
        end_idx = idx - 1
        break
      end
    end

    if start_idx and end_idx and end_idx >= start_idx then
      local content_lines = {}
      for idx = start_idx, end_idx do
        local line = result_lines[idx]
        -- Remove one level of indentation added by the wrapper class
        local dedented = line:gsub("^    ", "")
        table.insert(content_lines, dedented)
      end
      result = table.concat(content_lines, "\n")
    end
  end

  return result, nil
end

--- Extract the C# code from inside @code{} block (without the @code wrapper)
---@param block_content string
---@return string
function M.extract_from_block(block_content)
  local code = block_content:gsub("^%s*@code%s*{", "")
  code = code:gsub("}%s*$", "")
  return code
end

--- Wrap formatted C# code back in @code{} block with proper indentation
---@param formatted_code string
---@param indent_size number
---@return string
function M.wrap_in_block(formatted_code, indent_size)
  formatted_code = formatted_code:gsub("%s+$", "")
  local indent = string.rep(" ", indent_size)
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

return M
