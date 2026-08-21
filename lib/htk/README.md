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
The window bar's `[App]` button (and a right click on the desktop) opens
registered apps, Settings... and Quit. Settings picks a theme preset, the
desktop/window-bar/border colors, whether the bar is always shown, a clock at
its right and dimming of unfocused windows (`htk_bar_always`,
`htk_bar_clock`, `htk_dim_inactive`, `HtkThemePreset`). **Save** persists
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

## Theme

Every color lives in the runtime `htk_theme` struct; assign any field to
restyle live, `HtkThemeDefault()` restores the Borland palette:

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
focus, F10 opens menus and Left/Right hop between them, ESC dismisses
dialogs, Enter fires a window's default button (`link`),
mouse clicks/drags/wheel route by hit test, ^C sets `TermInterrupted` and
ends the loop.  Timers and queued calls share one hook list
(`HtkHookAdd`), driven by `TermMs()`.
Desktop shortcuts: **Ctrl-Tab** / **Ctrl-Shift-Tab** cycle visible windows,
**Ctrl-G** opens the active window's system menu, and **Ctrl-O** opens App.
In an open menu or combo box, **j** and **k** move the selection down and up.
For a menubar menu, **h** and **l** move to the previous and next top-level
menu (and back out of or into submenus).

See `examples/htk.hc` for native use, `examples/ui/*.hc` with `-DUI_HTK`
for the portable path.
