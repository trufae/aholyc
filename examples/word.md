# HolyC Markdown editor

Select some **bold**, *italic* or <u>underlined</u> text and try the toolbar.
<span style="color:#72c7ff;background-color:#202838">Foreground and background colors</span> remain plain Markdown with small HTML spans.

## Navigation

Click a title in the outline, or follow [the editor guide](../doc/word.md).
Try independent **Source** and **Editable** toggles, then View > Pages or
Current section. Emoji and Unicode styles work too: 😀 🌱 🚀 𝓗𝓸𝓵𝔂𝓒.

## Tables

<!-- table-border: round -->
| Action | Result | Shortcut |
| :--- | :--- | ---: |
| Save | Preserve the Markdown source | Ctrl+S |
| Undo | Restore the previous edit | Ctrl+Z |
| Code cell | `a|b` and escaped \| pipes | |
| Fit | This longer cell wraps when you make the document window narrower | |

Place the cursor in a cell to add rows, columns, change alignment or borders.
Turn off table fit to scroll horizontally.

## Code

```hc
U0 Hello(U8 *name="world")
{
  // Copy preserves this code, including its indentation.
  "Hello %s!\n", name;
}
Hello;
```

---

<!-- pagebreak -->

## Another page

View > Line numbers, Top ruler and Left ruler add document guides.
Edit > History restores several changes at once.

[Back to the title](#holyc-markdown-editor)
