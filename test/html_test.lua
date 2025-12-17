-- Test file for razor-fmt HTML formatter
-- Run with: nvim --headless -u NONE -c "set rtp+=." -c "luafile test/html_test.lua" -c "q"

package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local html = require("razor-fmt.html")

local config = {
  indent_size = 4,
  max_attributes_per_line = 1,
  align_attributes = true,
}

local tests_passed = 0
local tests_failed = 0

local function test(name, input, expected)
  local result = html.format(input, config)
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

local function test_tokenize(name, input, expected_types)
  local tokens = html.tokenize(input)
  local actual_types = {}
  for _, t in ipairs(tokens) do
    table.insert(actual_types, t.type)
  end
  
  local match = #actual_types == #expected_types
  if match then
    for i, t in ipairs(expected_types) do
      if actual_types[i] ~= t then
        match = false
        break
      end
    end
  end
  
  if match then
    tests_passed = tests_passed + 1
    print("✓ " .. name)
  else
    tests_failed = tests_failed + 1
    print("✗ " .. name)
    print("  Input: " .. input:gsub("\n", "\\n"))
    print("  Expected types: " .. table.concat(expected_types, ", "))
    print("  Got types: " .. table.concat(actual_types, ", "))
    print("  Tokens:")
    for i, t in ipairs(tokens) do
      print("    " .. i .. ": " .. t.type .. " = " .. t.content:gsub("\n", "\\n"):sub(1, 50))
    end
    print("")
  end
end

print("=== TOKENIZER TESTS ===\n")

-- Basic HTML
test_tokenize("Simple tag",
  "<div>Hello</div>",
  {"TAG_OPEN", "TEXT", "TAG_CLOSE"})

test_tokenize("Self-closing tag",
  "<br />",
  {"TAG_SELF_CLOSE"})

test_tokenize("Nested tags",
  "<div><span>text</span></div>",
  {"TAG_OPEN", "TAG_OPEN", "TEXT", "TAG_CLOSE", "TAG_CLOSE"})

-- Razor line directives
test_tokenize("@inject directive",
  "@inject IService Service",
  {"RAZOR_LINE"})

test_tokenize("@using directive",
  "@using System.Collections",
  {"RAZOR_LINE"})

test_tokenize("@page directive",
  "@page \"/counter\"",
  {"RAZOR_LINE"})

test_tokenize("@model directive",
  "@model MyViewModel",
  {"RAZOR_LINE"})

test_tokenize("@inherits directive",
  "@inherits LayoutComponentBase",
  {"RAZOR_LINE"})

test_tokenize("@implements directive",
  "@implements IDisposable",
  {"RAZOR_LINE"})

test_tokenize("@layout directive",
  "@layout MainLayout",
  {"RAZOR_LINE"})

test_tokenize("@namespace directive",
  "@namespace MyApp.Pages",
  {"RAZOR_LINE"})

test_tokenize("@attribute directive",
  "@attribute [Authorize]",
  {"RAZOR_LINE"})

test_tokenize("@typeparam directive",
  "@typeparam TItem",
  {"RAZOR_LINE"})

test_tokenize("@preservewhitespace directive",
  "@preservewhitespace true",
  {"RAZOR_LINE"})

test_tokenize("@rendermode directive",
  "@rendermode InteractiveServer",
  {"RAZOR_LINE"})

test_tokenize("Multiple directives",
  "@page \"/test\"\n@inject IService Svc",
  {"RAZOR_LINE", "TEXT", "RAZOR_LINE"})  -- newline becomes TEXT

-- Razor control flow
test_tokenize("@if block",
  "@if (condition) { <p>yes</p> }",
  {"RAZOR_BLOCK"})

test_tokenize("@if-else block",
  "@if (x) { a } else { b }",
  {"RAZOR_BLOCK"})

test_tokenize("@if-else if-else block",
  "@if (x) { a } else if (y) { b } else { c }",
  {"RAZOR_BLOCK"})

test_tokenize("@foreach block",
  "@foreach (var item in items) { <li>@item</li> }",
  {"RAZOR_BLOCK"})

test_tokenize("@for block",
  "@for (int i = 0; i < 10; i++) { <span>@i</span> }",
  {"RAZOR_BLOCK"})

test_tokenize("@while block",
  "@while (condition) { <p>loop</p> }",
  {"RAZOR_BLOCK"})

test_tokenize("@switch block",
  "@switch (value) { case 1: <p>one</p> break; }",
  {"RAZOR_BLOCK"})

test_tokenize("@try-catch block",
  "@try { risky() } catch (Exception ex) { handle() }",
  {"RAZOR_BLOCK"})

test_tokenize("@try-catch-finally block",
  "@try { a } catch { b } finally { c }",
  {"RAZOR_BLOCK"})

test_tokenize("@lock block",
  "@lock (syncObj) { critical() }",
  {"RAZOR_BLOCK"})

test_tokenize("@using statement (not directive)",
  "@using (var scope = new Scope()) { work() }",
  {"RAZOR_BLOCK"})

test_tokenize("@{ } code block",
  "@{ var x = 1; }",
  {"RAZOR_BLOCK"})

-- Inline Razor expressions (should be TEXT, not special tokens)
test_tokenize("Inline @variable",
  "<span>@User.Name</span>",
  {"TAG_OPEN", "TEXT", "TAG_CLOSE"})

test_tokenize("Inline @method call",
  "<span>@GetValue()</span>",
  {"TAG_OPEN", "TEXT", "TAG_CLOSE"})

test_tokenize("Inline @indexer",
  "<span>@L[\"Key\"]</span>",
  {"TAG_OPEN", "TEXT", "TAG_CLOSE"})

test_tokenize("Text with inline expression",
  "<span>Hello @User.Name!</span>",
  {"TAG_OPEN", "TEXT", "TAG_CLOSE"})

test_tokenize("Multiple inline expressions",
  "<span>@First and @Second</span>",
  {"TAG_OPEN", "TEXT", "TAG_CLOSE"})

-- Mixed content
test_tokenize("Directive then HTML",
  "@inject IService Svc\n<div>content</div>",
  {"RAZOR_LINE", "TEXT", "TAG_OPEN", "TEXT", "TAG_CLOSE"})

test_tokenize("HTML with control flow inside",
  "<div>@if (x) { <p>y</p> }</div>",
  {"TAG_OPEN", "RAZOR_BLOCK", "TAG_CLOSE"})

test_tokenize("Control flow between tags",
  "<ul>@foreach (var i in items) { <li>@i</li> }</ul>",
  {"TAG_OPEN", "RAZOR_BLOCK", "TAG_CLOSE"})

print("\n=== FORMATTER TESTS ===\n")

-- Basic formatting
test("Simple div",
  "<div>Hello</div>",
  "<div>Hello</div>")

test("Nested divs",
  "<div><div>inner</div></div>",
  "<div>\n    <div>inner</div>\n</div>")

test("Self-closing tag",
  "<input type=\"text\" />",
  "<input type=\"text\" />")

-- Attribute stacking
test("Multiple attributes stack",
  "<div class=\"foo\" id=\"bar\">content</div>",
  "<div class=\"foo\"\n     id=\"bar\">content</div>")

test("Single attribute no stack",
  "<div class=\"foo\">content</div>",
  "<div class=\"foo\">content</div>")

-- Line directives
test("@inject at root",
  "@inject IService Service",
  "@inject IService Service")

test("@inject with generic type",
  "@inject ILogger<MyClass> Logger",
  "@inject ILogger<MyClass> Logger")

test("Multiple directives",
  "@inject IService Svc\n@using System",
  "@inject IService Svc\n@using System")

-- Control flow formatting
test("@if block preserves content",
  "@if (x)\n{\n    <p>yes</p>\n}",
  "@if (x)\n{\n    <p>yes</p>\n}")

test("@if inside div",
  "<div>\n    @if (x) { y }\n</div>",
  "<div>\n    @if (x) { y }\n</div>")

test("@foreach inside ul",
  "<ul>\n    @foreach (var i in items)\n    {\n        <li>@i</li>\n    }\n</ul>",
  "<ul>\n    @foreach (var i in items)\n    {\n        <li>@i</li>\n    }\n</ul>")

-- Inline expressions preserved
test("Inline expression in text",
  "<span>Hello @User.Name</span>",
  "<span>Hello @User.Name</span>")

test("Multiple inline expressions",
  "<p>@First and @Second</p>",
  "<p>@First and @Second</p>")

test("Indexer expression",
  "<span>@L[\"SendToEmail\"]</span>",
  "<span>@L[\"SendToEmail\"]</span>")

-- Complex real-world examples
test("Blazor component with attributes",
  "<MudButton Variant=\"Variant.Filled\" Color=\"Color.Primary\" OnClick=\"HandleClick\">Click Me</MudButton>",
  "<MudButton Variant=\"Variant.Filled\"\n           Color=\"Color.Primary\"\n           OnClick=\"HandleClick\">Click Me</MudButton>")

test("Full page structure",
  "@page \"/test\"\n@inject IService Svc\n\n<div class=\"container\">\n    <h1>Title</h1>\n    <p>@Model.Description</p>\n</div>",
  "@page \"/test\"\n@inject IService Svc\n\n<div class=\"container\">\n    <h1>Title</h1>\n    <p>@Model.Description</p>\n</div>")

print("\n=== EDGE CASE TESTS ===\n")

-- Razor comments
test_tokenize("@* comment *@",
  "@* this is a comment *@",
  {"RAZOR_BLOCK"})

test_tokenize("Comment in HTML",
  "<div>@* comment *@</div>",
  {"TAG_OPEN", "RAZOR_BLOCK", "TAG_CLOSE"})

-- @@ escape
test_tokenize("@@ escape",
  "<p>Email: test@@example.com</p>",
  {"TAG_OPEN", "TEXT", "TAG_CLOSE"})

-- Nested control flow
test_tokenize("Nested @if",
  "@if (a) { @if (b) { c } }",
  {"RAZOR_BLOCK"})

-- Section directive (has a block)
test_tokenize("@section with block",
  "@section Scripts { <script>code</script> }",
  {"RAZOR_BLOCK"})

-- @code block (Blazor)
test_tokenize("@code block",
  "@code { private int count = 0; }",
  {"RAZOR_BLOCK"})

-- Expression with generics - this is a known limitation
-- Generic syntax <T> conflicts with HTML tags, so this may not work perfectly
-- For now, we accept that @GetItems<string>() gets parsed with <string> as a tag
test_tokenize("Generic method call (known limitation)",
  "<span>@GetItems<string>()</span>",
  {"TAG_OPEN", "TEXT", "TAG_OPEN", "TEXT", "TAG_CLOSE"})

-- For ternary, we need to use single quotes or escape properly
-- This tests that attributes with Razor expressions work
test("Attribute with parenthesized expression",
  "<div class=\"@(GetClass())\">content</div>",
  "<div class=\"@(GetClass())\">content</div>")

-- Event handlers
test("Blazor event handler",
  "<button @onclick=\"HandleClick\">Click</button>",
  "<button @onclick=\"HandleClick\">Click</button>")

test("Blazor event with lambda",
  "<button @onclick=\"() => count++\">Click</button>",
  "<button @onclick=\"() => count++\">Click</button>")

-- Bind attributes
test("Blazor @bind",
  "<input @bind=\"searchText\" />",
  "<input @bind=\"searchText\" />")

test("Blazor @bind:event",
  "<input @bind=\"searchText\" @bind:event=\"oninput\" />",
  "<input @bind=\"searchText\"\n       @bind:event=\"oninput\" />")

-- ref attribute
test("Blazor @ref",
  "<input @ref=\"inputElement\" />",
  "<input @ref=\"inputElement\" />")

-- Complex real-world component
test("Complex MudBlazor component",
  [[<MudDialog>
    <TitleContent>
        <MudText Typo="Typo.h6">@Title</MudText>
    </TitleContent>
    <DialogContent>
        @ChildContent
    </DialogContent>
</MudDialog>]],
  [[<MudDialog>
    <TitleContent>
        <MudText Typo="Typo.h6">@Title</MudText>
    </TitleContent>
    <DialogContent>
        @ChildContent
    </DialogContent>
</MudDialog>]])

-- Complex attributes with lambdas should not break
test("Lambda in attribute stays intact",
  [[<MudDynamicTabs CloseTab="@(x => ProcessingPageState.DeleteTab(x.ID as int? ?? -1))" KeepPanelsAlive>content</MudDynamicTabs>]],
  "<MudDynamicTabs CloseTab=\"@(x => ProcessingPageState.DeleteTab(x.ID as int? ?? -1))\"\n                KeepPanelsAlive>content</MudDynamicTabs>")

-- @for inside component
test("@for block inside component",
  [[<div>
    @for(var i = 0; i < 10; i++){
        <span>@i</span>
    }
</div>]],
  [[<div>
    @for(var i = 0; i < 10; i++){
        <span>@i</span>
    }
</div>]])

-- HTML comment
test_tokenize("HTML comment",
  "<!-- comment -->",
  {"COMMENT"})

test("HTML comment preserved",
  "<div><!-- comment --></div>",
  "<div>\n    <!-- comment -->\n</div>")

-- Void elements
test("Multiple void elements",
  "<div><br /><hr /><input type=\"text\" /></div>",
  "<div>\n    <br />\n    <hr />\n    <input type=\"text\" />\n</div>")

-- Pre tag preserves content
test("Pre tag preserves whitespace",
  "<pre>  line1\n    line2\n  line3</pre>",
  "<pre>  line1\n    line2\n  line3</pre>")

-- Blank lines around Razor blocks
test("Blank line before Razor block with content before",
  "<div>\n    <span>Before</span>\n    @if (x) { y }\n    <span>After</span>\n</div>",
  "<div>\n    <span>Before</span>\n\n    @if (x) { y }\n\n    <span>After</span>\n</div>")

test("No blank line when Razor block is first child",
  "<div>\n    @if (x) { y }\n    <span>After</span>\n</div>",
  "<div>\n    @if (x) { y }\n\n    <span>After</span>\n</div>")

print("\n=== SUMMARY ===")
print("Passed: " .. tests_passed)
print("Failed: " .. tests_failed)

if tests_failed > 0 then
  os.exit(1)
end
