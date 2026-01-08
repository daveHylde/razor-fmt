# razor-fmt

Opinionated Razor file formatter for Neovim.

- Formats `@code{}` blocks with [CSharpier](https://csharpier.com/)
- Formats HTML/template sections with JetBrains Rider-inspired defaults
- Formats `<style>` tag content with [cssls](https://github.com/microsoft/vscode-css-languageservice) LSP
- Supports `.razor` and `.cshtml` files

## Requirements

- Neovim 0.9+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

### Optional

- [CSharpier](https://csharpier.com/) - Required for formatting `@code{}` blocks
- [cssls](https://github.com/microsoft/vscode-css-languageservice) - Required for formatting `<style>` tag content

Install CSharpier via Mason:

```vim
:MasonInstall csharpier
```

Or via dotnet:

```sh
dotnet tool install -g csharpier
```

Install cssls via Mason:

```vim
:MasonInstall css-lsp
```

Without CSharpier installed, HTML formatting will still work but `@code{}` blocks will be left unchanged.
Without cssls running, `<style>` tag content will be re-indented but not reformatted.

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

Minimal setup with defaults:

```lua
{
  "daveHylde/razor-fmt",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {},
}
```

With lazy-loading (optional):

```lua
{
  "daveHylde/razor-fmt",
  dependencies = { "nvim-lua/plenary.nvim" },
  ft = { "razor", "cshtml" },
  opts = {},
}
```

With custom options:

```lua
{
  "daveHylde/razor-fmt",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
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

      -- Max attributes before stacking (1 = stack when more than 1 attribute)
      max_attributes_per_line = 1,
    },

    -- CSS formatting options (for <style> tag content)
    css = {
      -- Enable CSS formatting via cssls LSP
      enabled = true,

      -- Indent size for CSS
      indent_size = 4,
    },
  },
}
```

## Usage

### Commands

- `:RazorFormat` - Format the current Razor/cshtml file

### Keymaps

The plugin sets up `<leader>fr` in normal mode for `razor` and `cshtml` files by default.

### Programmatic

```lua
-- Format current buffer
require("razor-fmt").format_buffer()

-- Format a string
local formatted, err = require("razor-fmt").format(razor_content)
```

## conform.nvim Integration

The plugin auto-registers with [conform.nvim](https://github.com/stevearc/conform.nvim) if it's available. No additional configuration needed.

To disable auto-registration or use custom filetypes, configure conform manually:

```lua
require("conform").setup({
  formatters_by_ft = {
    razor = { "razor_fmt" },
    cshtml = { "razor_fmt" },
  },
})
```

## Formatting Style

### HTML

The HTML formatter uses JetBrains Rider-style defaults:

**Before:**

```html
<div class="container" id="main" data-value="123" @onclick="HandleClick">
```

**After:**

```html
<div
    class="container"
    id="main"
    data-value="123"
    @onclick="HandleClick"
>
```

- Tag name on its own line
- Each attribute on its own line, indented one level
- Closing `>` or `/>` on its own line, aligned with the tag name
- Tags with only inline text content stay on a single line (e.g., `<p class="text">Hello</p>`)

### C# (@code blocks)

C# code inside `@code{}` blocks is formatted using CSharpier with proper indentation.

**Before:**

```razor
@code {
private int count=0;
private void IncrementCount(){count++;}
}
```

**After:**

```razor
@code {
    private int count = 0;

    private void IncrementCount()
    {
        count++;
    }
}
```

### Razor Control Flow

Razor control flow blocks (`@if`, `@foreach`, `@for`, `@while`, `@switch`, `@try-catch`, etc.) are formatted with C#-style braces on their own lines:

**Before:**

```razor
@if (condition) { <p>Content</p> }
```

**After:**

```razor
@if (condition)
{
    <p>Content</p>
}
```

### CSS (`<style>` tags)

CSS content inside `<style>` tags is formatted using the cssls LSP server. The `<style>` tag is output on multiple lines with the CSS content properly indented.

**Before:**

```html
<style>.container{padding:1rem;margin:0}.button{color:red;}</style>
```

**After:**

```html
<style>
    .container {
        padding: 1rem;
        margin: 0;
    }
    .button {
        color: red;
    }
</style>
```

If cssls is not running, the CSS content will be re-indented to match the surrounding HTML but not reformatted.

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `indent_size` | number | `4` | Indentation for C# code inside `@code{}` blocks |
| `blank_line_before_code` | boolean | `true` | Add blank line before `@code{}` block if preceded by content |
| `format_html` | boolean | `true` | Enable HTML/template formatting |
| `html.indent_size` | number | `4` | Indent size for HTML elements |
| `html.max_attributes_per_line` | number | `1` | Max attributes before stacking (1 = stack when >1 attribute) |
| `css.enabled` | boolean | `true` | Enable CSS formatting via cssls LSP for `<style>` tags |
| `css.indent_size` | number | `4` | Indent size for CSS content |

## License

MIT
