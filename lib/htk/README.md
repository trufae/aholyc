# lib/htk — the holy termkit

A Borland-style widget toolkit for the terminal, written in pure HolyC on
top of `lib/term`: windows with shadows dragged over a ▒ desktop,
double-line frames, menus, dialogs, and every common widget — rendered
into `lib/term`'s cell grid, so each frame reaches the terminal as one
minimal diffed write.

It is also a first-class **backend for `lib/ui`**: build any `ui.hc`
program with `-DUI_HTK` and it runs in the terminal with zero source
changes (pixel sizes map onto 8x16 cells).

```console
$ aholyc run -DUI_HTK examples/ui/simpledemo.hc
```

## Widgets

label, separator, button, entry (with optional byte-length bound and
password masking), multiline editor, checkbox, switch, radio group, slider,
progress, activity spinner, spin, combobox, table (pull model), tree, tabs, titled group
frames, toolbar, statusbar, canvas (color/rect/line), menu bar with
dropdowns, and modal dialogs (`HtkMsgBox`, `HtkPrompt`, `HtkOpenFile`).

`HtkMsgBox` and `HtkPrompt` are modal to the active window.  Use
`HtkMsgBoxFor(owner, ...)`, `HtkPromptFor(owner, ...)`, or
`HtkModalFor(dialog, owner)` to choose the owner explicitly; a `NULL` owner
makes a dialog application-modal.  Clicking a blocked owner raises and
refocuses its dialog.
Application-modal dialogs also stay above every window and block the desktop
and window bar until dismissed.  A window's title-bar context menu has an
**Always on top** toggle; `HtkWindowSetAlwaysOnTop(window, TRUE)` exposes the
same behavior programmatically.

`HtkNotify("Saved", 3000)` posts a non-modal notification at the lower right,
stacked above the window bar; the optional timeout is in milliseconds.  A zero
timeout leaves it visible until its `[x]` button is clicked.  `HtkNoticeClose`
can dismiss the `HtkNotice *` returned by `HtkNotify` programmatically.

`HtkAppRegister("Editor", &EditorStart, data)` adds a desktop launcher to the
App menu.  Its `EditorStart(data)` callback creates the app's window(s).
Registered launchers keep the desktop alive after all windows close, allowing
users to launch any registered app again; call `HtkQuit()` to leave desktop.

By default `^C` keeps its SIGINT behavior and exits `HtkMain`; a focused
`HtkTerminal` always receives `^C` as `0x03` for its child process instead.
Use `HtkCtrlCSet(HTK_CTRLC_IGNORE)` to consume it, or
`HtkCtrlCSet(HTK_CTRLC_COPY)` to copy an entry/multiline selection or the
selected table row (TSV) without exiting.  `HtkClipboardText()` returns the
in-process clipboard.  Build with `-DHTK_NATIVE_CLIPBOARD` to additionally
send copies through OSC 52 to terminals that permit host clipboard access.
`HtkCtrlCHandler(fn, data)` plus `HTK_CTRLC_CALLBACK` queues `fn(data)` on
HTK's event-loop thread, suitable for a confirmation dialog.

## Markdown widgets

The [word processor](../../doc/word.md) uses `HtkMarkdownNew(edit)` from
`markdown.hc`, compact `HtkToolButtonNew` buttons and a single-row
`HtkToolbarNew`. `HTK_FLOW` is available for wrapping controls.
`choice.hc` provides grid/list choices and `HtkEmojiPick`;
`history.hc` provides a history picker, and `filepick.hc` provides
`HtkFilePickFor(owner, directory)` without changing the working directory.
All dialog results and Markdown widget state belong to their instances.
Markdown task-list checkboxes toggle on click in View mode, on double-click
in Edit mode, and with Space on the current task's source line in View mode.
Only the `[ ]`/`[x]` state byte changes, with one undo entry; ordinary text
stays locked in View. Fenced and tab-indented code is inert. Set the Markdown
view's `task_interactive` to FALSE for strict read-only viewers or source
editors; the Vim example does this.

`HtkClipboardSetStrs` / `HtkClipboardGet` preserve explicit byte lengths,
including embedded NUL. The older C-string clipboard helpers still work.

Vim support is optional: compile with `aholyc -D UI_HTK_VIMODE app.hc`, or
define `UI_HTK_VIMODE` before including HTK. Without it, `vim.hc`, its input
hooks, control state, history dependency and desktop setting are omitted.
The Word and Vim examples define this flag themselves.
When enabled, multiline and Markdown editors share Vim mode from `vim.hc`.
Their cursor is a block in Normal/Visual modes and a vertical bar in Insert.
Ordinary text editing and command prompts use a bar. Set an entry, multiline
or Markdown control's `cursor_shape` to `TERM_CURSOR_BLOCK`, `TERM_CURSOR_BAR`
or `TERM_CURSOR_DEFAULT` to choose its shape outside Vim mode; Vim overrides
that choice while enabled. The focused control selects the shape at draw time.
`HtkVimSet(TRUE)` enables it for existing windows and future textarea controls;
`HtkVimMode(editor, FALSE)` overrides one control. The desktop Settings checkbox
saves this preference as `vim_mode = 1` in `[htk]`. State belongs to each editor.
Normal mode supports `h/j/k/l`, `w/b/W/B`, `0/^/$`, `gg/G`, `i/a/I/A`, `o/O`,
`J`, `x`, `dd/yy`, `dw/cw`, `p/P`, `u`, and Ctrl+R. Esc returns from Insert
to Normal. `J` joins source lines with Vim spacing and trims indentation.
Insert typing (including spaces, line breaks and deletions) groups with `cw`
or `o/O` as one undo step until navigation, a command, Esc or a save boundary.
Motions and edits preserve UTF-8 boundaries; read-only editors reject changes.
Ctrl-F/PageDown and Ctrl-B/PageUp page in every Vim mode with two rows of
overlap, extending Visual selections. Markdown paging follows display rows,
including wrapping, and excludes the ruler and footer from the page height.
Insert mode provides Ctrl-A/E (line start/end), Ctrl-P/N (previous/next line),
Ctrl-D/H (delete next/previous character), Ctrl-K (cut to line end or its newline),
Ctrl-U (cut to line start), Ctrl-W (cut previous word), Ctrl-Y (paste), and
Ctrl-T (transpose characters). Consecutive cuts combine in the clipboard;
each cut/paste is one undo step. Ctrl-Y remains redo outside Insert mode.
`V` enters Visual line mode and `v` enters Visual character mode. Motions
extend the inclusive selection; `o` swaps its active end. `y` copies,
`d`/`x` deletes, `c` enters Insert to change it, and `p/P` replaces it with
the clipboard. Esc cancels. `HtkVimCaret(control, fallback)` supplies the
logical caret while `CEdit` retains ordinary exclusive selection bounds.
Custom textarea controls can set `vim_editor`, inherit `htk_vim_mode`, and call
`HtkVimKey(control, edit, event)` with their `CEdit` model before ordinary input.
Their optional `vim_changed` callback refreshes UI when the setting changes.
An optional `vim_page(control, edit, direction)` callback maps paging through
the adapter's visual layout; `direction` is -1 or 1. App key handlers can use
`HtkVimControl(control, event)` to give these Ctrl bindings precedence while
that Vim editor is focused.
Adapters should cancel Visual selection through `HtkVimCancel(control, edit)`
when disabling the mode or placing the caret with the mouse.

## Layout

Tiling containers compute a preferred size bottom-up, then divide space
top-down: `HTK_BOX` (linear, spare space to `expand` kids), `HTK_GRID`
(per-cell col/row), `HTK_SPLIT` (first pane keeps its size), `HTK_SCROLL`
(clipped viewport with scrollbar).  Windows tile with `HtkTile()` or
`HtkCascade()`, drag by their title bar and resize by dragging any of the
four frame corners.  The title carries Windows-style boxes: `[_]` minimizes the window
to a button on a one-row taskbar at the bottom of the terminal (click the
button to bring it back), `[□]` maximizes over the desktop and `[▣]`
restores, `[■]` closes (`HtkWindowMinimize/Maximize/Restore/Close`).  A
`HtkStatusbarNew` control draws as an inverse strip, so a box with the
status bar last gives a docked bar like the GTK/Cocoa/Win32 backends.
Status bars can also hold children: an expanding label yields its width to
fixed buttons at the right, allowing view modes alongside document statistics.
On Termux, tap or swipe the title text to start **Move**, then tap the
destination for the title point you grabbed. The bottom row shows the
Move prompt. Termux reports finger swipes as wheel events at a fixed cell,
without a press, release or changing drag coordinates, so a continuous
two-dimensional finger drag cannot reach HTK. Physical mouse drags still
move windows normally. Wheel events over window contents still scroll.
The top-left system-menu button also offers **Move**, which places the
title's center at the destination, and **Resize**, which places the
bottom-right corner at the destination. **Ctrl-G** opens that menu from
the keyboard on any terminal.
The direct title fallback is enabled when `TERMUX_VERSION` is present;
set `htk_touch_titles` after initialization to override it (for example,
when using Termux to run HTK through SSH).

**Alt-F7** enters Move directly; **Alt-F8** enters Resize. Arrow keys adjust
the position or bottom-right corner by one cell, and **Shift+arrows** adjust
by five cells. **Enter** accepts; **Escape** restores the original position
and size. Resize respects `HtkWindowSetSizeLimits`. Maximized and minimized
windows cannot enter either mode. Ordinary mouse title/frame dragging
continues to work alongside these modes.

Change the activation shortcuts in **App > Settings** (Move shortcut and
Resize shortcut), then **Save**, or edit the `[htk]` section of `~/htk.ini`:

```ini
[htk]
move_key = Alt+m
resize_key = Alt+r
```

Bindings accept `Ctrl`, `Alt`, and `Shift` modifiers joined with `+`, a
letter, `F1` through `F12`, or a named key such as `Home` or `PageUp`.
`None` disables a shortcut. The two shortcuts must be distinct; malformed
or conflicting configuration retains the existing bindings. Settings
**Reset** restores Alt-F7 and Alt-F8. The settings file is available with
the default desktop layer; `HTK_NODESK` apps can configure keys in code:

```c
HtkWindowSetKeybinding(HTK_WM_MOVE, 'm', TERM_MOD_ALT);
HtkWindowSetKeybinding(HTK_WM_RESIZE, 'r', TERM_MOD_ALT);
// key 0 disables the action; FALSE reports an invalid/conflicting binding.
```

Call this after `HtkInit` / `UiInit` to override loaded settings.
The window bar's `[App]` button (and a right click on the desktop) opens
registered apps, Settings... and Quit. Settings picks a theme preset, the
desktop/window-bar/border colors, whether the bar is always shown, a clock at
its right, Vim mode for textarea editors, window shadows, and dimming of
unfocused windows (`htk_bar_always`, `htk_bar_clock`, `htk_window_shadow`,
`htk_dim_inactive`, `HtkThemePreset`). Window shadows preview immediately.
**Save** persists
these choices in `~/htk.ini`; **Reset** restores defaults and removes that
file. Build with `-DHTK_NODESK` to drop that layer: the bar then appears only
while windows are minimized.
Entries and the multiline editor support selection: drag with the mouse or
move with Shift+arrows/Home/End; typing, Enter, Backspace and Delete replace
or remove the selected range (`anchor`/`cursor` byte indices).
`HtkColorPick(title, rgb)` is a modal color picker that adapts to the
terminal: 16 swatches, the 256-color palette, or palette plus R/G/B sliders
on true-color terminals (via `TermColorRgb`/`TermColor256`; lib/ui exposes it
as `UiPickColor`).
`HtkButtonBarNew()` creates a horizontal action row whose buttons are
right-aligned and bottom-docked in its vertical parent by default; set its
`->right` or `->bottom` field to `FALSE` to opt out, or add an expanding child
for a deliberate spacer.
`HtkWindowSetSizeLimits(window, min_width, min_height, max_width, max_height)`
sets resize bounds; use zero for either maximum to leave that dimension
unbounded.  HTK maintains an absolute 12×4 minimum frame.
`HtkWindowSetControls(window, mask)` configures title actions with
`HTK_WINDOW_MENU`, `HTK_WINDOW_MINIMIZE`, `HTK_WINDOW_MAXIMIZE`, and
`HTK_WINDOW_CLOSE`; new windows use `HTK_WINDOW_DEFAULT_CONTROLS`.
When many windows are minimized the bar's button strip scrolls: drag it
left/right (or use the wheel); `[App]` stays fixed at the left, a right
click on a button opens that window's menu.
`HtkTerminalNew(cols, rows)` is a terminal emulator control (`HTK_TERM`):
a pty with `$SHELL` on Unix, ConPTY with `%COMSPEC%` on Windows, an xterm
subset with 16/256/true colors, Tab and ^C forwarded while focused;
`HtkTerminalWindow()` wraps one in a window and the desktop layer offers it
as App > Terminal.
A right click on a title bar, or its top-left `[=]` system-menu button, opens
the window menu (Minimize, Maximize or Restore, Tile ▸ Left/Right/Top/Bottom,
Close).  Any control can carry its
own context menu: build one with `HtkContextMenuNew` (+ `HtkMenuItem`,
`HtkSubMenu` for ▸ submenus), assign it to `ctl->menu`, and a right click
on the control (or anything inside it) pops it up; `HtkMenuOpenAt` shows a
menu at an arbitrary cell.
`HtkMenuSeparator(menu)` adds a horizontal rule between action groups;
keyboard navigation skips separator rows. Word and Vim use these in their
window menus. Serial draws the rules as ASCII dashes.

## Theme

Every color lives in the runtime `htk_theme` struct; assign any field to
restyle live. `HtkThemeDefault()` restores the Borland palette.

Presets are Borland (dark blue contents), Light Borland (the original pale
palette), Dark, Light, Teal, Modern, and Serial. Modern uses charcoal surfaces
and a muted sage accent, with a basic-color fallback. Serial uses basic ANSI colors
and ASCII glyphs, including window borders, controls, and Unicode fallbacks;
document and clipboard bytes remain unchanged. `menu_bg/menu_fg` and
`tool_bg/tool_fg` color the separate window menubar and toolbar strips.

```holyc
htk_theme.frame = TERM_BRIGHT_YELLOW;
htk_theme.btn_bg = TERM_MAGENTA;
htk_dirty = TRUE;
```

## Model

One `HtkCtl` class describes every widget; behavior is dispatched by
`kind` in loop.hc.  Widgets fire their `changed` hook on activation or
edit, entries fire `submit` on Enter — those hooks plus the `user` pointer
are the whole adapter surface `lib/ui/htk.hc` needs.  The loop (`HtkMain`,
or `HtkStep(timeout)` for custom loops) polls `lib/term` events: Tab cycles
focus, F10 or Alt-M opens the window menubar, Left/Right hop between menus,
ESC dismisses
dialogs, Enter fires a window's default button (`link`),
mouse clicks/drags/wheel route by hit test, ^C sets `TermInterrupted` and
ends the loop.  Timers and queued calls share one hook list
(`HtkHookAdd`), driven by `TermMs()`.
Desktop shortcuts: **Ctrl-Tab** / **Ctrl-Shift-Tab** cycle visible windows,
**Ctrl-G** opens the active window's system menu, and **Ctrl-O** opens App.
**Alt-A** or **Alt-F10** opens App even when an application uses Ctrl-O for Open.
Custom move/resize bindings have precedence over these menu shortcuts.
In an open menu or combo box, **j** and **k** move the selection down and up.
For a menubar menu, **h** and **l** move to the previous and next top-level
menu (and back out of or into submenus).

See `examples/htk.hc` for native use, `examples/ui/*.hc` with `-DUI_HTK`
for the portable path.

`examples/vim.hc` combines the shared Vim handler and Markdown control's
literal source mode into a split source editor; see [its guide](../../doc/vim.md).
For `HTK_SPLIT`, `value` from 1 to 999 sets the first child's share in
thousandths (`500` gives equal panes), following window resizes. Zero keeps
the first child's preferred size. Source views offer `no_wrap` and
`tab_width` (default four). `CEdit.spliced(edit, a, b, size)` optionally
notifies views of each replacement, including undo/redo, so other panes can
adjust their positions without copying the document.
