# AGENTS.md

## Build/Test Commands
- Run all tests: `nvim --headless -u NONE -c "set rtp+=." -c "luafile test.lua" -c "q"`
- Run single test file: `nvim --headless -u NONE -c "set rtp+=." -c "luafile test/html_test.lua" -c "q"`
- Alternative (plain Lua, no vim API): `lua test.lua` (fails if test uses vim.*)

## Code Style
- **Imports**: Use `require("razor-fmt.module")` with local assignment at file top
- **Module pattern**: Return `M = {}` table, define functions as `M.function_name` or `local function`
- **Types**: Use LuaDoc annotations (`---@param`, `---@return`, `---@field`) for public functions
- **Naming**: `snake_case` for functions/variables, `UPPER_CASE` for constants
- **Indentation**: 2 spaces
- **Strings**: Double quotes preferred

## Error Handling
- Return `result, error_string` tuple pattern (nil result on error)
- Use `vim.notify()` for user-facing errors in Neovim context
- Use `pcall()` for optional dependencies (e.g., conform.nvim)

## Project Structure
- `lua/razor-fmt/` - Main plugin code (init.lua is entry point)
- `lua/razor-fmt/html/` - HTML tokenizer, formatter, and utilities
- `test/` - Test files (*_test.lua pattern)
