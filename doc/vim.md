# HTK Vim example

Build with `make vim`, then run `./vim [file ...]` in a terminal. Additional
files open in vertical splits. A missing filename creates an empty named
buffer. The editor reuses HTK's Vim handler, source renderer, menus, clipboard,
themes and settings. It starts in Normal mode; `i` enters Insert mode and
Esc returns to Normal mode.
Normal and Visual modes use a block cursor; Insert and the command prompt
use a thin vertical `|` cursor.
This example defines `UI_HTK_VIMODE`; other HTK apps opt in by defining it
before including HTK or passing `-D UI_HTK_VIMODE` to the compiler.

In Normal mode, `V` selects whole source lines and `v` selects characters.
Motions extend the selection in either direction; `o` swaps its active end.
`y` copies, `d`/`x` deletes, `c` changes the selection in Insert mode, and
`p` replaces it with the clipboard. Esc cancels selection. The status line
shows `V-LINE` or `VISUAL` and the logical caret's position.

Splits share text and undo history when they display the same buffer. Each
pane keeps its own cursor, selection, scroll position, wrapping and line
numbers. One shared status line shows the active pane's mode, line/column,
filename, `[+]` for unsaved changes and command messages. The command prompt
replaces that same row. Tabs are eight columns and Insert-mode Tab inserts a tab.

Press `:` for commands, Enter to run one, or Esc to cancel. Filenames may
contain spaces; optional surrounding quotes are accepted. Commands use
literal paths, without shell expansion.

| Command | Action |
| --- | --- |
| `:split`, `:sp [file]` | Split above/below, sharing the buffer or opening a file |
| `:vsplit`, `:vs [file]` | Split left/right |
| `:new [file]`, `:vnew [file]` | Open an empty or named buffer in a split |
| `:e[!] [file]` | Open a file; no filename reloads the current file |
| `:o[!] [file]`, `:open[!] [file]` | Open in the current pane, with the same behavior as `:e` |
| `:w[!] [file]` | Save; `!` allows an explicit overwrite or readonly write |
| `:q[!]`, `:wq`, `:qa[!]` | Close a pane, save and close, or close the editor |
| `:only[!]` | Keep the active pane |
| `:ls`, `:buffers` | List buffer IDs in the message strip |
| `:b id`, `:bn`, `:bp` | Select a buffer, or cycle buffers |
| `:set [no]number [no]wrap [no]readonly [no]vim` | Change view/editor options |
| `:number` | Jump to a source line |
| `:help` | Show the key and command reference |

Closing or replacing the last view of a modified buffer requires saving or
an explicit `!`. Failed writes preserve the file and pane. Saving to a path
owned by another open buffer is rejected. Clean hidden buffers remain
available through `:b`, `:bn` and `:bp`.

In Normal or Visual mode, Ctrl-W followed by `s`/`v` splits, `w`/`W` cycles panes, `h`/`j`/`k`/`l`
moves toward another pane, `c` closes it, and `o` keeps only it. Repeated
Ctrl-W also cycles. `/text` and `?text` search literally in either direction;
`n` repeats and `N` reverses. Search wraps. Ctrl-S saves, Ctrl-C copies the
selection and leaves Insert mode, F10 opens the window menus, and Alt-A
opens App/settings.

Ctrl-F/PageDown and Ctrl-B/PageUp page in every Vim mode, using the active
pane's visible height with two rows of overlap. Visual paging extends the
selection. Insert mode also supports these editing shortcuts:

| Keys | Action |
| --- | --- |
| Ctrl-A / Ctrl-E | Start / end of the source line |
| Ctrl-P / Ctrl-N | Previous / next source line, retaining the column |
| Ctrl-D / Ctrl-H | Delete next / previous character |
| Ctrl-K | Cut to line end, or cut the newline when already at line end |
| Ctrl-U / Ctrl-W | Cut to line start / cut the previous word |
| Ctrl-Y | Paste the clipboard |
| Ctrl-T | Transpose adjacent characters within the line |

Consecutive cuts combine in the shared clipboard; each cut and paste is
independently undoable. Navigation or another command starts a fresh cut.
In Normal mode, Ctrl-Y keeps its redo behavior. Ctrl-Z undoes in Insert mode.

This is a small Vim-style example. It supports HTK's shared motions and
editing commands, including `J`, clipboard operations and grouped undo.
Counts, macros, regular expressions and full Vim compatibility
are outside its current command set.
