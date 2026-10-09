# HolyC UI library

Include `lib/ui/ui.hc` for the common widget and callback API, documented
in that file. The default backend is Cocoa on macOS, Win32 on Windows,
Intuition/GadTools on classic AmigaOS, and GTK4 elsewhere. Use
`-DUI_BACKEND=UI_AMIGA`, `UI_COCOA`, `UI_WIN32`, `UI_GTK4`, or `UI_HTK`
to select a backend explicitly; `-DUI_HTK` also selects the terminal UI.

## AmigaOS

```console
$ ./aholyc -t amiga examples/ui/amiga.hc -o holy-ui
```

Copy `holy-ui` to an Amiga and run it from the shell. The backend requires
AmigaOS 3.0 or later (V39 libraries), uses the current public screen, and
calls Intuition, GadTools, graphics, and ASL through the cross toolchain's
`libamiga` stubs. It needs no third-party GUI toolkit. The compact demo fits
a standard 640x256 Workbench screen. The larger demos need a taller screen.

Supported widgets include windows, labels, buttons, entries, checkboxes,
sliders, integer fields, cycle selectors, radio groups, progress indicators,
menus with one submenu level, and canvases with rectangle/line drawing and
mouse callbacks. Boxes, grids, groups, toolbars, status bars, visibility,
enabling, resize layout, multiple windows, queued callbacks, and timers use
the common API. Message boxes and file selection use native requesters;
text prompts and RGB selection use modal GadTools windows.

Tables, trees, and read-only multiline text use native scrolling listviews.
Tables display their cells as text columns separated by ` | `; trees display
the complete hierarchy as indented rows. Tabs use a native cycle selector.
Split containers distribute space between their children, with no draggable
divider. Canvas colors use the closest pen in the screen's existing palette.
Layout assumes an eight-pixel monospace font and is intended for the default
Workbench font. Entry callbacks fire when editing is committed, rather than
on every keystroke. Timers are serviced by Intuition ticks, approximately
every 100 ms while a window is open. Slider ranges must fit signed 16 bits,
and integer field ranges must fit signed 32 bits.

Masked password fields, editable multiline text, popup context menus, and
scrolling arbitrary containers currently raise a `UI` exception.
`UiScrollNew` accepts tables, trees, and multiline text, which already have
native scrollbars. The backend runs on one task; call the UI API on that
task. Controls retain their metadata until the program exits, as in the
other backends.

`amiga_api.hc` keeps native pointer fields four bytes wide and describes
the NDK layouts explicitly; ordinary HolyC pointers remain eight-byte slots.
`make test-amiga` runs host-side model/layout tests, checks these offsets
against the installed NDK, and cross-links the compact, widget, drawing,
table, and tree demos. Those checks do not execute the graphical interface;
an Amiga or emulator is needed for that verification.

API references: [GadTools gadgets](https://wiki.amigaos.net/wiki/GadTools_Gadgets)
and [GadTools menus](https://wiki.amigaos.net/wiki/GadTools_Menus).
