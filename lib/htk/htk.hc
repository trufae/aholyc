#ifndef AHOLYC_LIB_HTK_HC
#define AHOLYC_LIB_HTK_HC

// htk — a Borland-style widget toolkit for the terminal, in pure HolyC on
// top of lib/term.  Windows with shadows on a ▒ desktop, double-line
// frames, tiling layout containers (box, grid, split, scroll), and the
// common widgets: label, button, entry, checkbox, switch, radio, slider,
// progress, spinner,
// spin, combobox, table, tree, tabs, group, toolbar, statusbar, canvas,
// menus, and modal dialogs.
//
// Quick start:
//   HtkInit();
//   HtkCtl *w = HtkWindowNew("Hello", 40, 12);
//   HtkCtl *box = HtkNew(HTK_BOX);  box->vertical = TRUE;
//   HtkAdd(box, HtkButtonNew("Press me"));
//   HtkAdd(w, box);
//   HtkMain();       // Tab cycles focus, F10 opens menus, ^C interrupts
//   HtkFini();
//
// Widgets fire their `changed` hook on activation or edit; the hook plus
// the `user` field is all lib/ui needs to adapt htk as a backend.  One
// HtkStep(timeout) call runs a single iteration for custom loops; drawing
// goes through lib/term's cell grid, so a frame costs one diffed commit.
//
// HtkTile() and HtkCascade() arrange the window stack; windows drag by
// their title bar and close on the [■] box.

#include "../term/term.hc"
#include "core.hc"
#include "box.hc"
#include "label.hc"
#include "button.hc"
#include "entry.hc"
#include "checkbox.hc"
#include "slider.hc"
#include "list.hc"
#include "combobox.hc"
#include "menu.hc"
#include "table.hc"
#include "tree.hc"
#include "tabs.hc"
#include "group.hc"
#include "canvas.hc"
#include "window.hc"
#include "loop.hc"
#include "dialog.hc"
#include "colorpick.hc"
// The terminal control's pty backend: HTK_PTY_WINDOWS/HTK_PTY_POSIX let
// cross-builds override the compiler host.
#include "terminal.hc"
#ifdef HTK_PTY_WINDOWS
#include "pty_windows.hc"
#else
#ifdef HTK_PTY_POSIX
#include "pty_posix.hc"
#else
#ifdef IS_WINDOWS
#include "pty_windows.hc"
#else
#include "pty_posix.hc"
#endif
#endif
#endif
#ifdef HTK_NODESK
U0 HtkAppMenuOpen(I64 x, I64 y)
{
}
#else
#include "desktop.hc"
#endif

#endif
