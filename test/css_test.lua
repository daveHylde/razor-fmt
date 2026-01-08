-- Test file for razor-fmt CSS formatting in <style> tags
-- Run with: nvim --headless -u NONE -c "set rtp+=." -c "luafile test/css_test.lua" -c "q"

package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local html = require("razor-fmt.html")

local config = {
  indent_size = 4,
  max_attributes_per_line = 1,
  css = {
    enabled = true,
    indent_size = 4,
  },
}

local config_css_disabled = {
  indent_size = 4,
  max_attributes_per_line = 1,
  css = {
    enabled = false,
    indent_size = 4,
  },
}

local tests_passed = 0
local tests_failed = 0

local function test(name, input, expected, test_config)
  test_config = test_config or config
  local result = html.format(input, test_config)
  if result == expected then
    tests_passed = tests_passed + 1
    print("✓ " .. name)
  else
    tests_failed = tests_failed + 1
    print("✗ " .. name)
    print("  Input:")
    for line in input:gmatch("[^\n]+") do
      print("    " .. line)
    end
    print("  Expected:")
    for line in expected:gmatch("[^\n]+") do
      print("    " .. line)
    end
    print("  Got:")
    for line in result:gmatch("[^\n]+") do
      print("    " .. line)
    end
    print("")
  end
end

print("=== CSS FORMATTING TESTS ===\n")

-- Note: These tests verify the structure of the output.
-- When cssls LSP is not available, CSS content is re-indented but not reformatted.
-- The tests are designed to pass whether or not cssls is running.

-- Basic style tag formatting
test("Empty style tag",
  "<style></style>",
  "<style></style>")

test("Style tag with simple CSS - formats to multi-line",
  "<style>.foo { color: red; }</style>",
  "<style>\n    .foo { color: red; }\n</style>")

test("Style tag with multiple rules",
  "<style>.foo { color: red; } .bar { color: blue; }</style>",
  "<style>\n    .foo { color: red; } .bar { color: blue; }\n</style>")

-- Style tag inside elements
test("Style tag inside head",
  "<head><style>.foo { color: red; }</style></head>",
  "<head>\n    <style>\n        .foo { color: red; }\n    </style>\n</head>")

-- Style tag with attributes
test("Style tag with type attribute",
  "<style type=\"text/css\">.foo { color: red; }</style>",
  "<style type=\"text/css\">\n    .foo { color: red; }\n</style>")

-- Multi-line CSS content
test("Style tag with multi-line CSS preserves structure",
  "<style>\n.foo {\n    color: red;\n}\n</style>",
  "<style>\n    .foo {\n        color: red;\n    }\n</style>")

-- Style tag with Blazor scoped attribute
test("Style tag with scoped attribute",
  "<style scoped>.component { margin: 0; }</style>",
  "<style scoped>\n    .component { margin: 0; }\n</style>")

-- CSS disabled - should preserve content exactly like other preserved elements
test("Style tag with CSS disabled preserves content",
  "<style>.foo { color: red; }</style>",
  "<style>.foo { color: red; }</style>",
  config_css_disabled)

-- Complex real-world examples
test("Blazor component with style tag",
  "<div class=\"container\"><style>.container { padding: 1rem; }</style><p>Content</p></div>",
  "<div class=\"container\">\n    <style>\n        .container { padding: 1rem; }\n    </style>\n    <p>Content</p>\n</div>")

test("Style tag with media query",
  "<style>@media (max-width: 768px) { .foo { display: none; } }</style>",
  "<style>\n    @media (max-width: 768px) { .foo { display: none; } }\n</style>")

test("Style tag with CSS variables",
  "<style>:root { --primary: #007bff; } .btn { color: var(--primary); }</style>",
  "<style>\n    :root { --primary: #007bff; } .btn { color: var(--primary); }\n</style>")

-- Nested style in Razor component structure
test("Style tag in full Razor component",
  "@page \"/test\"\n\n<div>\n    <style>.test { color: red; }</style>\n    <p>Hello</p>\n</div>",
  "@page \"/test\"\n\n<div>\n    <style>\n        .test { color: red; }\n    </style>\n    <p>Hello</p>\n</div>")

-- Complex multi-rule CSS with @keyframes (without cssls, indentation is preserved but not reformatted)
test("Style tag with keyframes preserves relative indentation",
  "<style>\n.loading { display: flex; }\n.spinner { width: 50px; }\n@keyframes rotate {\n    from { transform: rotate(0deg); }\n    to { transform: rotate(360deg); }\n}\n</style>",
  "<style>\n    .loading { display: flex; }\n    .spinner { width: 50px; }\n    @keyframes rotate {\n        from { transform: rotate(0deg); }\n        to { transform: rotate(360deg); }\n    }\n</style>")

-- Bug: CSS with inconsistent input indentation - without cssls, relative indentation is preserved
-- (This is expected behavior without LSP - proper formatting requires cssls)
test("Style tag with inconsistent indentation preserves relative structure",
  "<style>\n.loading-screen-container {\n        display: flex;\n        justify-content: center;\n    }\n    .spinner {\n        width: 50px;\n    }\n</style>",
  "<style>\n    .loading-screen-container {\n            display: flex;\n            justify-content: center;\n        }\n        .spinner {\n            width: 50px;\n        }\n</style>")

print("\n=== SUMMARY ===")
print("Passed: " .. tests_passed)
print("Failed: " .. tests_failed)

if tests_failed > 0 then
  os.exit(1)
end
