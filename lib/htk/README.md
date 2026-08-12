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
password masking), multiline editor, checkbox, radio group, slider,
progress, spin, combobox, table (pull model), tree, tabs, titled group
frames, toolbar, statusbar, canvas (color/rect/line), menu bar with
dropdowns, and modal dialogs (`HtkMsgBox`, `HtkPrompt`, `HtkOpenFile`).

## Layout

Tiling containers compute a preferred size bottom-up, then divide space
top-down: `HTK_BOX` (linear, spare space to `expand` kids), `HTK_GRID`
(per-cell col/row), `HTK_SPLIT` (first pane keeps its size), `HTK_SCROLL`
(clipped viewport with scrollbar).  Windows tile with `HtkTile()` or
`HtkCascade()`, drag by their title bar, and close on the `[■]` box.

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
edit — that hook plus the `user` pointer is the whole adapter surface
`lib/ui/htk.hc` needs.  The loop (`HtkMain`, or `HtkStep(timeout)` for
custom loops) polls `lib/term` events: Tab cycles focus, F10 opens menus,
ESC dismisses dialogs, Enter fires a window's default button (`link`),
mouse clicks/drags/wheel route by hit test, ^C sets `TermInterrupted` and
ends the loop.  Timers and queued calls share one hook list
(`HtkHookAdd`), driven by `TermMs()`.

See `examples/htk.hc` for native use, `examples/ui/*.hc` with `-DUI_HTK`
for the portable path.
