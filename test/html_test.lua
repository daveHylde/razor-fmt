-- Test file for razor-fmt HTML formatter
-- Run with: nvim --headless -u NONE -c "set rtp+=." -c "luafile test/html_test.lua" -c "q"

package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local html = require("razor-fmt.html")

local config = {
  indent_size = 4,
  max_attributes_per_line = 1,
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
test("Multiple attributes stack on block element",
  "<div class=\"foo\" id=\"bar\"><span>child</span></div>",
  "<div\n    class=\"foo\"\n    id=\"bar\"\n>\n    <span>child</span>\n</div>")

test("Multiple attributes inline when only text content",
  "<div class=\"foo\" id=\"bar\">content</div>",
  "<div class=\"foo\" id=\"bar\">content</div>")

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

test("@if block formats braces on own lines",
  "@if (x) { y }",
  "@if (x)\n{\n    y\n}")

test("@if inside div",
  "<div>\n    @if (x) { y }\n</div>",
  "<div>\n    @if (x)\n    {\n        y\n    }\n</div>")

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
test("Blazor component with attributes and inline content",
  "<MudButton Variant=\"Variant.Filled\" Color=\"Color.Primary\" OnClick=\"HandleClick\">Click Me</MudButton>",
  "<MudButton Variant=\"Variant.Filled\" Color=\"Color.Primary\" OnClick=\"HandleClick\">Click Me</MudButton>")

test("Blazor component with attributes and block content",
  "<MudButton Variant=\"Variant.Filled\" Color=\"Color.Primary\"><span>Click Me</span></MudButton>",
  "<MudButton\n    Variant=\"Variant.Filled\"\n    Color=\"Color.Primary\"\n>\n    <span>Click Me</span>\n</MudButton>")

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
  "<input\n    @bind=\"searchText\"\n    @bind:event=\"oninput\"\n/>")

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
  [[<MudDynamicTabs CloseTab="@(x => ProcessingPageState.DeleteTab(x.ID as int? ?? -1))" KeepPanelsAlive>content</MudDynamicTabs>]])

-- @for inside component
test("@for block inside component",
  [[<div>
    @for(var i = 0; i < 10; i++){
        <span>@i</span>
    }
</div>]],
  [[<div>
    @for (var i = 0; i < 10; i++)
    {
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
  "<div>\n    <span>Before</span>\n\n    @if (x)\n    {\n        y\n    }\n\n    <span>After</span>\n</div>")

test("No blank line when Razor block is first child",
  "<div>\n    @if (x) { y }\n    <span>After</span>\n</div>",
  "<div>\n    @if (x)\n    {\n        y\n    }\n\n    <span>After</span>\n</div>")

-- Razor expressions with nested quotes in attributes
test("Localizer in attribute value",
  [[<PropertyColumn Title="@Localizer["Status"]">content</PropertyColumn>]],
  [[<PropertyColumn Title="@Localizer["Status"]">content</PropertyColumn>]])

test("Parenthesized expression with nested quotes",
  [[<PropertyColumn Hidden="@(ColumnIsHidden("Name"))">content</PropertyColumn>]],
  [[<PropertyColumn Hidden="@(ColumnIsHidden("Name"))">content</PropertyColumn>]])

test("Complex Func expression in attribute",
  [[<MudDataGrid ServerData="@(new Func<GridState<T>, Task<GridData<T>>>(GetData))">content</MudDataGrid>]],
  [[<MudDataGrid ServerData="@(new Func<GridState<T>, Task<GridData<T>>>(GetData))">content</MudDataGrid>]])

test("Multiple attributes with Razor expressions",
  [[<Column Property="x => x.Name" Title="@Localizer["Name"]" Hidden="@(IsHidden("Name"))">content</Column>]],
  [[<Column Property="x => x.Name" Title="@Localizer["Name"]" Hidden="@(IsHidden("Name"))">content</Column>]])

test("Razor expression with > inside attribute",
  [[<MudTabPanel Text="@($"{(i>9 ? "" : $"({i})")}")" ID="@i">content</MudTabPanel>]],
  [[<MudTabPanel Text="@($"{(i>9 ? "" : $"({i})")}")" ID="@i">content</MudTabPanel>]])

test("Complex ternary with > in attribute",
  [[<span class="@(value > 10 ? "large" : "small")">text</span>]],
  [[<span class="@(value > 10 ? "large" : "small")">text</span>]])

-- Sibling element spacing (JetBrains style: no blank lines between siblings)
test("Sibling self-closing elements no blank lines",
  [[<Columns><PropertyColumn Title="A" /><PropertyColumn Title="B" /><PropertyColumn Title="C" /></Columns>]],
  "<Columns>\n    <PropertyColumn Title=\"A\" />\n    <PropertyColumn Title=\"B\" />\n    <PropertyColumn Title=\"C\" />\n</Columns>")

test("Sibling block elements no blank lines",
  [[<div><header>H</header><main>M</main><footer>F</footer></div>]],
  "<div>\n    <header>H</header>\n    <main>M</main>\n    <footer>F</footer>\n</div>")

print("\n=== CONTROL FLOW FORMATTING TESTS ===\n")

-- @if formatting
test("@if simple formatting",
  "@if (condition) { <p>content</p> }",
  "@if (condition)\n{\n    <p>content</p>\n}")

test("@if with else",
  "@if (a) { <p>yes</p> } else { <p>no</p> }",
  "@if (a)\n{\n    <p>yes</p>\n}\nelse\n{\n    <p>no</p>\n}")

test("@if with else if",
  "@if (a) { <p>A</p> } else if (b) { <p>B</p> }",
  "@if (a)\n{\n    <p>A</p>\n}\nelse if (b)\n{\n    <p>B</p>\n}")

test("@if with else if and else",
  "@if (a) { <p>A</p> } else if (b) { <p>B</p> } else { <p>C</p> }",
  "@if (a)\n{\n    <p>A</p>\n}\nelse if (b)\n{\n    <p>B</p>\n}\nelse\n{\n    <p>C</p>\n}")

test("@if multiple else if chains",
  "@if (a) { 1 } else if (b) { 2 } else if (c) { 3 } else { 4 }",
  "@if (a)\n{\n    1\n}\nelse if (b)\n{\n    2\n}\nelse if (c)\n{\n    3\n}\nelse\n{\n    4\n}")

-- @foreach formatting
test("@foreach simple formatting",
  "@foreach (var item in items) { <li>@item</li> }",
  "@foreach (var item in items)\n{\n    <li>@item</li>\n}")

test("@foreach with multiple elements",
  "@foreach (var item in items) { <tr><td>@item.Name</td><td>@item.Value</td></tr> }",
  "@foreach (var item in items)\n{\n    <tr>\n        <td>@item.Name</td>\n        <td>@item.Value</td>\n    </tr>\n}")

-- @for formatting
test("@for simple formatting",
  "@for (int i = 0; i < 10; i++) { <span>@i</span> }",
  "@for (int i = 0; i < 10; i++)\n{\n    <span>@i</span>\n}")

test("@for with complex increment",
  "@for (int i = start; i <= end; i += step) { <p>@i</p> }",
  "@for (int i = start; i <= end; i += step)\n{\n    <p>@i</p>\n}")

-- @while formatting
test("@while simple formatting",
  "@while (condition) { <p>looping</p> }",
  "@while (condition)\n{\n    <p>looping</p>\n}")

test("@while with complex condition",
  "@while (count > 0 && !done) { <span>@count--</span> }",
  "@while (count > 0 && !done)\n{\n    <span>@count--</span>\n}")

-- @do-while formatting
test("@do-while simple formatting",
  "@do { <p>at least once</p> } while (condition);",
  "@do\n{\n    <p>at least once</p>\n} while (condition);")

test("@do-while with complex condition",
  "@do { <span>@value</span> } while (value < max && !stop);",
  "@do\n{\n    <span>@value</span>\n} while (value < max && !stop);")

-- @switch formatting
test("@switch simple formatting",
  "@switch (value) { case 1: <p>one</p> break; case 2: <p>two</p> break; default: <p>other</p> break; }",
  "@switch (value)\n{\n    case 1:\n        <p>one</p>\n        break;\n    case 2:\n        <p>two</p>\n        break;\n    default:\n        <p>other</p>\n        break;\n}")

test("@switch with enum",
  "@switch (status) { case Status.Active: <span class=\"active\">Active</span> break; }",
  "@switch (status)\n{\n    case Status.Active:\n        <span class=\"active\">Active</span>\n        break;\n}")

-- @try-catch-finally formatting
test("@try-catch simple formatting",
  "@try { <p>risky</p> } catch (Exception ex) { <p>@ex.Message</p> }",
  "@try\n{\n    <p>risky</p>\n}\ncatch (Exception ex)\n{\n    <p>@ex.Message</p>\n}")

test("@try-catch without exception type",
  "@try { <p>risky</p> } catch { <p>error</p> }",
  "@try\n{\n    <p>risky</p>\n}\ncatch\n{\n    <p>error</p>\n}")

test("@try-catch-finally formatting",
  "@try { <p>try</p> } catch (Exception ex) { <p>catch</p> } finally { <p>finally</p> }",
  "@try\n{\n    <p>try</p>\n}\ncatch (Exception ex)\n{\n    <p>catch</p>\n}\nfinally\n{\n    <p>finally</p>\n}")

test("@try with multiple catch blocks",
  "@try { op() } catch (IOException ex) { io() } catch (Exception ex) { gen() }",
  "@try\n{\n    op()\n}\ncatch (IOException ex)\n{\n    io()\n}\ncatch (Exception ex)\n{\n    gen()\n}")

test("@try with multiple catch and finally",
  "@try { a } catch (IOException ex) { b } catch { c } finally { d }",
  "@try\n{\n    a\n}\ncatch (IOException ex)\n{\n    b\n}\ncatch\n{\n    c\n}\nfinally\n{\n    d\n}")

-- @lock formatting
test("@lock simple formatting",
  "@lock (syncObj) { <p>critical section</p> }",
  "@lock (syncObj)\n{\n    <p>critical section</p>\n}")

test("@lock with complex lock object",
  "@lock (typeof(MyClass)) { <p>type lock</p> }",
  "@lock (typeof(MyClass))\n{\n    <p>type lock</p>\n}")

-- @using statement formatting
test("@using statement simple formatting",
  "@using (var scope = new Scope()) { <p>scoped</p> }",
  "@using (var scope = new Scope())\n{\n    <p>scoped</p>\n}")

test("@using statement with resource",
  "@using (var stream = File.OpenRead(path)) { <p>reading</p> }",
  "@using (var stream = File.OpenRead(path))\n{\n    <p>reading</p>\n}")

-- @{ } code block formatting
test("@{ } simple code block",
  "@{ var x = 1; }",
  "@{\n    var x = 1;\n}")

test("@{ } multi-statement code block",
  "@{ var a = 1; var b = 2; }",
  "@{\n    var a = 1; var b = 2;\n}")

-- Nested control flow formatting
test("Nested @if in @foreach",
  "@foreach (var item in items) { @if (item.IsVisible) { <p>@item.Name</p> } }",
  "@foreach (var item in items)\n{\n    @if (item.IsVisible)\n    {\n        <p>@item.Name</p>\n    }\n}")

test("Nested @foreach in @if",
  "@if (hasItems) { <ul> @foreach (var i in items) { <li>@i</li> } </ul> }",
  "@if (hasItems)\n{\n    <ul>\n        @foreach (var i in items)\n        {\n            <li>@i</li>\n        }\n    </ul>\n}")

test("Deeply nested control flow",
  "@if (a) { @foreach (var i in items) { @if (i.Show) { <span>@i</span> } } }",
  "@if (a)\n{\n    @foreach (var i in items)\n    {\n        @if (i.Show)\n        {\n            <span>@i</span>\n        }\n    }\n}")

test("@switch with nested @if",
  "@switch (type) { case 1: @if (flag) { <p>yes</p> } break; }",
  "@switch (type)\n{\n    case 1:\n        @if (flag)\n        {\n            <p>yes</p>\n        }\n        break;\n}")

test("@foreach with @if-else inside",
  "@foreach (var item in items) { @if (item.Active) { <span class=\"active\">@item</span> } else { <span>@item</span> } }",
  "@foreach (var item in items)\n{\n    @if (item.Active)\n    {\n        <span class=\"active\">@item</span>\n    }\n    else\n    {\n        <span>@item</span>\n    }\n}")

-- Control flow with HTML attributes
test("@foreach with component attributes",
  "@foreach (var item in items) { <MudListItem Text=\"@item.Name\" Icon=\"@item.Icon\" /> }",
  "@foreach (var item in items)\n{\n    <MudListItem\n        Text=\"@item.Name\"\n        Icon=\"@item.Icon\"\n    />\n}")

test("@if with styled div",
  "@if (isVisible) { <div class=\"container\" style=\"display: block;\"><p>Content</p></div> }",
  "@if (isVisible)\n{\n    <div\n        class=\"container\"\n        style=\"display: block;\"\n    >\n        <p>Content</p>\n    </div>\n}")

-- Real-world complex examples
test("Table with @foreach rows",
  "<table><tbody>@foreach (var row in rows) { <tr><td>@row.Col1</td><td>@row.Col2</td></tr> }</tbody></table>",
  "<table>\n    <tbody>\n        @foreach (var row in rows)\n        {\n            <tr>\n                <td>@row.Col1</td>\n                <td>@row.Col2</td>\n            </tr>\n        }\n    </tbody>\n</table>")

test("Conditional rendering with @if",
  "<div>@if (user.IsAdmin) { <AdminPanel /> } else { <UserPanel /> }</div>",
  "<div>\n    @if (user.IsAdmin)\n    {\n        <AdminPanel />\n    }\n    else\n    {\n        <UserPanel />\n    }\n</div>")

test("MudBlazor DataGrid with conditional column",
  [[<MudDataGrid Items="@Items">@foreach (var col in Columns) { @if (col.Visible) { <PropertyColumn Property="col.Prop" Title="@col.Title" /> } }</MudDataGrid>]],
  "<MudDataGrid Items=\"@Items\">\n    @foreach (var col in Columns)\n    {\n        @if (col.Visible)\n        {\n            <PropertyColumn\n                Property=\"col.Prop\"\n                Title=\"@col.Title\"\n            />\n        }\n    }\n</MudDataGrid>")

-- Empty component with many attributes should stack attributes
test("Empty component with many attributes should stack",
  [[<MudChart ChartOptions="_chartOptions" ChartType="ChartType.Bar" ChartSeries="@_series" @bind-SelectedIndex="_index" XAxisLabels="@_xAxisLabels" Height="@_height" AxisChartOptions="_axisChartOptions"></MudChart>]],
  "<MudChart\n    ChartOptions=\"_chartOptions\"\n    ChartType=\"ChartType.Bar\"\n    ChartSeries=\"@_series\"\n    @bind-SelectedIndex=\"_index\"\n    XAxisLabels=\"@_xAxisLabels\"\n    Height=\"@_height\"\n    AxisChartOptions=\"_axisChartOptions\"\n></MudChart>")

-- @if-else with stacked attributes in body (regression test for blank line issue)
test("@if-else with stacked attributes no extra blank lines",
  "@if (_loading) { <MudGrid Class=\"pa-8\" Spacing=\"12\"><MudItem sm=\"12\" md=\"6\">Loading</MudItem></MudGrid> } else { <MudGrid Class=\"px-8\" Spacing=\"8\"><MudItem sm=\"12\" md=\"6\">Content</MudItem></MudGrid> }",
  "@if (_loading)\n{\n    <MudGrid\n        Class=\"pa-8\"\n        Spacing=\"12\"\n    >\n        <MudItem sm=\"12\" md=\"6\">Loading</MudItem>\n    </MudGrid>\n}\nelse\n{\n    <MudGrid\n        Class=\"px-8\"\n        Spacing=\"8\"\n    >\n        <MudItem sm=\"12\" md=\"6\">Content</MudItem>\n    </MudGrid>\n}")

-- Stacked attributes should not have blank lines between them
test("Stacked attributes no blank lines between",
  "<MudGrid Class=\"pa-8\" Spacing=\"12\"><p>text</p></MudGrid>",
  "<MudGrid\n    Class=\"pa-8\"\n    Spacing=\"12\"\n>\n    <p>text</p>\n</MudGrid>")

print("\n=== SUMMARY ===")
print("Passed: " .. tests_passed)
print("Failed: " .. tests_failed)

if tests_failed > 0 then
  os.exit(1)
end
