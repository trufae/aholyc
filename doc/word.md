# Markdown word processor

`examples/word.hc` is a native HolyC application built with this repository's
compiler and HTK. It stores Markdown; formatting changes the source directly.

```sh
make word
./word examples/word.md
./word first.md second.md
# Explicit backend, if desired:
./aholyc -b c examples/word.hc -o word
```

Each argument opens a separate document window. The desktop's **App** menu
has **New Markdown** and **Open Markdown...** launchers. Open uses a directory
browser: select a name and press Enter, or enter a path and press Open.
Closing the last document leaves the desktop available; Quit exits.

## Editing

The two square toolbar toggles are independent:

| Source | Editable | View |
| --- | --- | --- |
| Off | Off | Rendered, read only |
| Off | On | Rendered, editable |
| On | Off | Markdown source, read only |
| On | On | Markdown source, editable |

Drag or use Shift+arrows to select text. Formatting buttons apply to that
selection. B/I/U toggle bold, italic and underline; FG/BG insert HTML color
spans. Font reuses the Unicode alphabet converter, and Emoji opens a grid
picker. Unicode styles alter the actual characters. Underline uses `<u>`.
The toolbar wraps as the window is resized; all actions also have menus.

| Shortcut | Action |
| --- | --- |
| Ctrl+N / Ctrl+O | New / open another window |
| Ctrl+S / Ctrl+Shift+S | Save / save as |
| Ctrl+W / Ctrl+Q | Close window / quit |
| Ctrl+C / Ctrl+X / Ctrl+V | Copy / cut / paste |
| Ctrl+A / Ctrl+F | Select all / find |
| Ctrl+Z / Ctrl+Y or Ctrl+Shift+Z | Undo / redo |
| Ctrl+B / Ctrl+I / Ctrl+U | Bold / italic / underline |
| Shift+arrows | Extend selection |
| Home / End, Ctrl+Home / Ctrl+End | Line / document boundaries |
| PageUp / PageDown, mouse wheel | Navigate / scroll |
| Alt+Left / Alt+Right | Horizontal scroll |
| Ctrl+G | HTK window menu |

Some terminals send Ctrl+I as Tab and cannot distinguish shifted control
letters. Use the corresponding menu or button there. Copies always populate
HTK's shared, length-bounded clipboard and also emit OSC 52 in the application;
host clipboard support depends on the terminal. Ctrl+V uses the HTK clipboard.
Terminal paste can enter text from other applications.

Undo retains up to 128 edit deltas per document. Adjacent typing is grouped
until a space, navigation, command or save boundary. Formatting and table
operations are individual history steps. **Edit > History...** restores
through a chosen undo/redo entry. Editing after undo discards the redo branch.
Read-only mode blocks all changes, including undo and redo. Save status tracks
the history revision, so undoing to the saved state clears the dirty marker.

## Navigation and layout

The heading tree opens a title's source position. **View** controls the outline,
source line numbers, top and left rulers, column width, and lines per page.
Click the top ruler to set a wrap column; zero in Column width means the
available window width. Line numbers refer to source lines, including wrapped
lines. The left ruler counts display rows; the top ruler counts terminal cells.

Continuous, Pages and Current section are display layouts. Pages divides the
rendered rows at the selected page length, with visible page separators.
`<!-- pagebreak -->` creates an explicit break and is preserved in Markdown.
Format also offers a line separator (`---`). These are terminal page previews,
not paper-size print layout. A section includes its child headings until the
next heading of equal or higher rank. Click the outline or use Previous/Next
section to change the section being displayed.

Fenced code accepts backticks or tildes, including longer matching fences.
Code retains its text and uses simple keyword, string, number and comment
highlighting. Each rendered block has a **Copy** button that copies the exact
code bytes without fences or display padding. Long code lines scroll
horizontally. Indented code retains the existing renderer's tab-block support.

Click a rendered link or image label for **Open in new window**, **Replace
this window**, **Edit link**, **Open with system handler**, or **Copy target**.
Relative files resolve beside the current document. Heading fragments use
lowercase heading text with spaces replaced by hyphens. Images display their
alt text in the terminal; the system handler opens the actual image.

## Tables and export

Place the cursor in a table to add/delete rows or columns, align the current
column, or change its border style. The header and final column cannot be
deleted. Escaped pipes, pipes in inline code, and empty cells are supported.
Fit mode wraps cells to the viewport; natural-width mode preserves widths and
uses Alt+Left/Right or the bottom `< >` controls to scroll. If even minimum
column widths cannot fit, horizontal scrolling remains available. Tables
support up to 32 columns; wider input remains visible as source text.

Border choices are single, round, ASCII and none. A portable Markdown comment
before the table preserves the preference, for example:

```md
<!-- table-border: round -->
| Name | Value |
| :--- | ---: |
| Example | 42 |
```

**File > Export** writes HTML, Gemini Gemtext (`.gem`), or plain text.
HTML uses semantic headings/tables, safe links, images and color spans;
Gemtext emits `=>` links and fenced tables. Relative export links remain
relative, so export beside the document to preserve their destinations.
Save writes a temporary sibling and renames it over the destination only
after a successful write. Unsaved changes prompt on close, replace and quit.

The renderer extends the repository's Markdown subset; it is not a full
CommonMark/HTML engine. It supports ATX headings, emphasis, strike, inline and
fenced code, rules, pipe tables, inline links/images, and basic HTML (`span`
colors, `u`, `a`, `img`, `br`, comments and common entities). List/quote markers
remain visible. Unsupported HTML is literal text and escaped on export.
Terminal width handling covers common wide CJK characters and single-scalar
emoji; complex grapheme clusters and bidirectional shaping are not implemented.

## Reuse and ownership

There is no application-global document state. `CWordApp` owns `CWordDoc`
instances; each owns a `CEdit` model and an HTK window. Library state is passed
explicitly. The existing HTK context/clipboard remains shared across windows.

| Library | Responsibility |
| --- | --- |
| `lib/text/edit.hc` | UTF-8 byte boundaries, selection, bounded edits, delta history |
| `lib/text/markdown.hc`, `md_inline.hc`, `md_block.hc` | Streaming rendering, inline HTML/links, fenced blocks and highlighting |
| `lib/text/md_edit.hc`, `md_export.hc` | Table/format transformations, sections, exports |
| `lib/htk/markdown.hc` | Editable/read-only Markdown canvas, source mapping and guides |
| `lib/htk/choice.hc`, `history.hc`, `filepick.hc` | Grid/list choices, emoji/history dialogs, file browser |
| `lib/io/replace.hc` | Length-bounded replacement writes and path comparison |

`HtkToolButtonNew` is a compact selectable button; `HTK_FLOW` wraps toolbar
children. `HtkCtl.keyfn` permits control/window key handling, `closing` can veto
window close/quit, and a window's `submit` runs after close. `HtkDestroy` frees
a detached tree and invokes payload `destroy` callbacks. Close a window first;
callbacks should defer destruction until their event has finished.
`HtkMarkdownNew(edit)` borrows the caller-owned model. Drawing and hit testing
stream through the same renderer, without a per-byte glyph map or a second
editable document. Layout currently traverses the document on redraw and
wrapped tables may reparse cells; very large documents are not virtualized.

All document, history, parser and clipboard operations use `CStrs` ranges
`[a,b)` or explicit lengths. `CStrBuf` keeps a trailing NUL for C interop;
it never defines the end of a document. UI labels and OS paths use the
existing C-string APIs. Tests include unterminated input and embedded NULs.

`tests/word.HC` runs headlessly from `make test` on native C/LLVM backends.
The interactive application needs a terminal. The native file browser has
Linux, macOS and Windows implementations; development validation used Linux.
