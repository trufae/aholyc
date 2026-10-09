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

The bottom-right status-bar buttons show the current view and editing modes.
Click **Render / Source** or **Edit / View** to change them independently:

| Source | Editable | View |
| --- | --- | --- |
| Off | Off | Rendered, read only |
| Off | On | Rendered, editable |
| On | Off | Markdown source, read only |
| On | On | Markdown source, editable |

Drag or use Shift+arrows to select text. Formatting buttons apply to that
selection. B/I/U toggle bold, italic and underline. The remaining toolbar
symbols are **☺** (emoji picker), **↗** (link), **⌕** (find/replace), and **V**
(Vim mode). **Outline**, **Render/Source**, and **Edit/View** sit at the bottom
right of the status bar. The window has one menubar row and one toolbar
row, with distinct backgrounds. New, Open and Save live in the File menu.
Text/background colors and Unicode Font styles remain in Format. Unicode
styles alter the actual characters; underline uses `<u>`.

The status bar counts whitespace-separated words and Unicode characters in
the Markdown source, including markup and line breaks. It also shows the
source line/column, editing mode, and an asterisk for unsaved changes.

| Shortcut | Action |
| --- | --- |
| Ctrl+N / Ctrl+O | New / open another window |
| Ctrl+S / Ctrl+Shift+S | Save / save as |
| Ctrl+W / Ctrl+Q | Close window / quit |
| Ctrl+C / Ctrl+X / Ctrl+V | Copy / cut / paste |
| Ctrl+A / Ctrl+F | Select all / find and replace |
| Ctrl+Z / Ctrl+Y or Ctrl+Shift+Z | Undo / redo |
| Ctrl+B / Ctrl+I / Ctrl+U | Bold / italic / underline |
| Shift+arrows | Extend selection |
| Home / End, Ctrl+Home / Ctrl+End | Line / document boundaries |
| PageUp / PageDown, mouse wheel | Navigate / scroll |
| Alt+Left / Alt+Right | Horizontal scroll |
| Ctrl+G | HTK window menu |
| F10 / Alt+M | Window menubar; arrows navigate, Enter activates, Esc dismisses |
| Alt+A / Alt+F10 | Desktop App menu |

Some terminals send Ctrl+I as Tab and cannot distinguish shifted control
letters. Use the corresponding menu or button there. Copies always populate
HTK's shared, length-bounded clipboard and also emit OSC 52 in the application;
host clipboard support depends on the terminal. Ctrl+V uses the HTK clipboard.
Terminal paste can enter text from other applications.

Find performs literal, case-sensitive searches and wraps at the document end.
Enable **Replace** in the same dialog to replace the selected/next match, or
enable **Replace all matches**. An empty replacement deletes matches; Replace
all is one undo step. Read-only documents still allow searching.

**Edit > Toggle Vim mode**, the **V** button, and **App > Settings** use HTK's
shared Vim setting, including other multiline editors and new windows.
This example defines `UI_HTK_VIMODE`; other HTK apps enable this optional
feature with `-D UI_HTK_VIMODE` or the same define before including HTK.
Normal mode supports `h/j/k/l`, `w/b/W/B`, `0/^/$`, `gg/G`, `i/a/I/A`, `o/O`, `J`,
`x`, `dd`, `yy`, `dw`, `cw`, `p/P`, `u`, and Ctrl+R. `J` joins source lines,
trims the next line's indentation, and adds Vim-style spacing. `cw` preserves
following spaces. Esc leaves Insert mode. Motions use UTF-8 boundaries and
source lines; vertical moves keep the display column across short lines.
Ctrl-F/PageDown and Ctrl-B/PageUp page in every Vim mode; the page height
excludes the top ruler and footer. Paging follows wrapped/rendered rows.
In Insert mode, Ctrl-A/E move to line start/end, Ctrl-P/N move between source
lines, Ctrl-D/H delete characters, Ctrl-K/U/W cut to line end/start or the
previous word, Ctrl-Y pastes, and Ctrl-T transposes characters. Consecutive
cuts combine in the clipboard. These editor bindings take precedence while
the Vim editor has focus; Find, Bold, New, Close and other app actions remain
available through the menus. Outside Vim mode, app shortcuts are unchanged.
`V` selects whole source lines; `v` selects characters. Motions extend the
selection, `o` swaps its active end, and `y`/`d`/`c` copy/delete/change it.
Esc cancels Visual selection. The statusbar shows `V-LINE` or `VISUAL`.
The cursor is a block in Normal/Visual modes and a thin vertical `|` in
Insert or ordinary editing mode.
Save the preference in HTK Settings to retain it between launches.

Undo retains up to 128 edit deltas per document. Adjacent typing is grouped
until a space, navigation, command or save boundary. In Vim Insert mode,
spaces, line breaks, deletions and the initiating `cw` or `o/O` command share
one undo step; navigation, Esc, commands and saving end that group. Formatting and table
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

## Paragraph alignment

The toolbar's **L**, **C**, **R**, and **J** buttons align the current paragraph
left, center, right, or justify it across the column width. Full labels are
in **Format → Paragraph alignment**. A selection applies the alignment to
each selected paragraph, preserving code blocks and tables. Wrapped justified
lines expand word spacing; the final line stays left aligned. Each action
is one undo step, and applying another alignment replaces the existing one.

Alignment is saved using Pandoc fenced divs, for example:

```markdown
::: {.htk-align-center style="text-align:center"}
Centered paragraph.
:::
```

The rendered editor and HTML/PDF exports honor these settings. Plain text
and Gemtext retain the text without the div markers.

## Tables and export

New tables have empty header and body cells. Place the cursor in a table to
add/delete rows or columns, align the current
column, or change its border style. The header and final column cannot be
deleted. Escaped pipes, pipes in inline code, and empty cells are supported.
While editing a cell, Tab advances to the next cell and Shift+Tab returns to
the previous cell, in both rendered and source views. They skip the alignment
row and stay in the table at its first/last cell. Outside a table, Tab moves
keyboard focus normally.
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

**File > Export** writes HTML, Gemini Gemtext (`.gem`), plain text, or PDF.
HTML uses semantic headings/tables, safe links, images and color spans;
Gemtext emits `=>` links and fenced tables. Relative export links remain
relative, so export beside the document to preserve their destinations.
**PDF...** opens page settings before asking for a destination. Choose A4,
A5, Letter or Legal, portrait/landscape, independent margins in whole
millimeters, a 10–12 pt body font, and an optional table of contents.
**PDF settings...** edits these choices independently; each document window
keeps its own settings for the session. PDF export uses Pandoc plus the chosen
XeLaTeX (default), PDFLaTeX or LuaLaTeX engine, which must be on `PATH`.
It exports the current buffer, including unsaved edits, resolves image paths
beside the Markdown file, and preserves the destination if conversion fails.
Pandoc controls PDF formatting; HTK's terminal-only table border hints and
HTML-only formatting may differ in the PDF.
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

`HtkToolButtonNew` is a compact selectable button; `HtkToolbarNew` keeps the
editor's actions on one row. `HtkStatusbarNew` can contain a flexible stats
label and mode buttons. `HtkCtl.keyfn` permits control/window key handling,
`closing` can veto
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
