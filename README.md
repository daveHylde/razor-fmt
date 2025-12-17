# razor-fmt

Opinionated Razor file formatter for Neovim.

- Formats `@code{}` blocks with [CSharpier](https://csharpier.com/)
- Formats HTML/template sections with JetBrains Rider-style defaults (attributes stacked, one per line)
- Supports `.razor` and `.cshtml` files

## Requirements

- Neovim 0.9+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

### Optional

- [CSharpier](https://csharpier.com/) - Required for formatting `@code{}` blocks

Install via Mason:

```vim
:MasonInstall csharpier
```

Or via dotnet:

```sh
dotnet tool install -g csharpier
```

Without CSharpier installed, HTML formatting will still work but `@code{}` blocks will be left unchanged.

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

      -- Align attributes with first attribute
      align_attributes = true,
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
<div class="container"
     id="main"
     data-value="123"
     @onclick="HandleClick">
```

- First attribute stays on the same line as the tag
- Subsequent attributes are aligned with the first attribute
- Closing `>` or `/>` stays on the last attribute line

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

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `indent_size` | number | `4` | Indentation for C# code inside `@code{}` blocks |
| `blank_line_before_code` | boolean | `true` | Add blank line before `@code{}` block if preceded by content |
| `format_html` | boolean | `true` | Enable HTML/template formatting |
| `html.indent_size` | number | `4` | Indent size for HTML elements |
| `html.max_attributes_per_line` | number | `1` | Max attributes before stacking (1 = stack when >1 attribute) |
| `html.align_attributes` | boolean | `true` | Align stacked attributes with first attribute |

## License

MIT
