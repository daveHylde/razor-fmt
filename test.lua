-- Test runner for razor-fmt
-- Run with: nvim --headless -u NONE -c "set rtp+=." -c "luafile test.lua" -c "q"
-- Or with: lua test.lua

package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local test_files = {
  "test/html_test.lua",
  "test/css_test.lua",
}

local total_exit_code = 0

for _, file in ipairs(test_files) do
  print("\n" .. string.rep("=", 60))
  print("Running: " .. file)
  print(string.rep("=", 60) .. "\n")

  local chunk, err = loadfile(file)
  if chunk then
    local ok, result = pcall(chunk)
    if not ok then
      print("ERROR: " .. tostring(result))
      total_exit_code = 1
    end
  else
    print("ERROR loading file: " .. tostring(err))
    total_exit_code = 1
  end
end

print("\n" .. string.rep("=", 60))
print("All test files completed")
print(string.rep("=", 60))

if total_exit_code > 0 then
  os.exit(1)
end
