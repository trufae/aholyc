# lib/term

Portable terminal control for aholyc's native backends: cursor movement,
colors, keyboard and mouse input, terminal size and resize notification,
and `^C` detection — with the ANSI escape codes (and the legacy Win32
console) abstracted away.  The design borrows from radare2's `r_cons`:
output is buffered and hits the terminal in one write, interrupts are a
polled flag, and resizes are events instead of asynchronous callbacks.

## Model

The screen is an off-screen grid of cells.  Drawing calls only store cells;
nothing reaches the terminal until `TermCommit`, which diffs the grid
against what is already displayed and emits the smallest possible update in
a single write.  Partial updates never flicker, and unchanged commits cost
nothing.

Each cell (rune, colors, attributes) packs into one `U64`, so a cell write
is a single aligned store.  Any number of threads may draw between commits
without mutexes — last writer wins per cell — as long as exactly one thread
calls `TermCommit`.  The `TermCell`/`TermText`/`TermFill` primitives take
explicit coordinates and colors and touch no shared state, so they are the
ones to use from threads; the cursor/pen conveniences (`TermGotoXY`,
`TermColor`, `TermPuts`, `TermPrint`) share one cursor and are meant for
single-threaded drawing.  Blocking synchronization primitives can be layered
on later without changing this API.

Text is UTF-8 throughout, decoded with `lib/text/utf8.HC` — one cell per
rune, never per byte.

## Backends

* `posix.hc` — Linux and macOS: termios raw mode, `TIOCGWINSZ`, `SIGINT`/
  `SIGWINCH` flags, SGR (1006) mouse reports, escape-sequence key parsing.
* `windows.hc` — Windows 10+ consoles run the same ANSI stream through
  virtual terminal processing; older consoles are detected automatically
  and updated with `WriteConsoleOutputW` cell blits instead.  Input always
  uses `ReadConsoleInputW` records, `^C` uses a console ctrl handler.

Define `TERM_POSIX` or `TERM_WINDOWS` to override the host default.

## API

```holyc
#include "lib/term/term.hc"

Bool TermInit(Bool alt_screen=TRUE, Bool raw=TRUE);
U0   TermFini();

I64  TermWidth();  I64 TermHeight();          // cached size
Bool TermGetSize(I64 *width, I64 *height);    // live query
U0   TermOnResize(U8 *callback);              // U0 (*)(I64 width, I64 height)

// Thread-safe drawing: explicit coordinates, no shared state.
U0   TermCell(I64 x, I64 y, I64 ch, I64 fg=TERM_DEFAULT,
              I64 bg=TERM_DEFAULT, I64 attr=0);
U0   TermText(I64 x, I64 y, U8 *text, I64 fg=..., I64 bg=..., I64 attr=0);
U0   TermFill(I64 x, I64 y, I64 w, I64 h, I64 ch=' ', ...);
U0   TermClear();

// Single-thread cursor + pen conveniences.
U0   TermGotoXY(I64 x, I64 y);
U0   TermColor(I64 fg, I64 bg=TERM_DEFAULT);
U0   TermAttr(I64 attr);   // TERM_BOLD|UNDERLINE|REVERSE|ITALIC|STRIKE|DIM|BLINK
U0   TermPutChar(I64 ch);  U0 TermPuts(U8 *text);
U0   TermPrint(U8 *fmt, ...);
U0   TermShowCursor(Bool visible=TRUE);

U0   TermCommit();                            // sync the grid to the screen
U0   TermRedraw();                            // force a full repaint

Bool TermPollEvent(CTermEvent *event, I64 timeout_ms=-1);
I64  TermReadKey(I64 timeout_ms=-1);          // 0 on timeout
I64  TermReadLine(U8 *buffer, I64 capacity);  // cooked line, -1 on EOF
I64  TermReadByte();                          // cooked byte, -1 on EOF
Bool TermInterrupted(Bool clear=TRUE);        // did the user press ^C?
U0   TermMouse(Bool enable=TRUE);
U0   TermRaw(Bool enable=TRUE);

// Raw output for scrolling uses of the terminal (see lib/line).
U0   TermWrite(U8 *bytes, I64 count);         // bypass the cell grid
Bool TermLegacy();                            // console without ANSI

I64  TermMs();                                // monotonic milliseconds
U64  TermPeek(I64 x, I64 y);                  // read back a drawn cell
```

Colors are the 16 ANSI colors (`TERM_BLACK` … `TERM_BRIGHT_WHITE`) plus
`TERM_DEFAULT`; `TermColor256(n)` and `TermColorRgb(r, g, b)` give values
from the 256-color palette and true color that work anywhere a color is
accepted.  `TermColorDepth()` (16, 256 or 16777216, detected from `TERM`
and `COLORTERM`, overridable with `TermSetColorDepth`) drives automatic
degradation to what the terminal supports, and `TermColorToRgb` maps any
value back to `0xRRGGBB`.  Cells now hold rune (21 bits), attributes and
two 18-bit colors; read them with `TermCellChar/Attr/Fg/Bg`.  Keys are Unicode codepoints, with specials as
`TERM_KEY_UP`, `TERM_KEY_F1`, … and modifiers reported in
`event->mods` (`TERM_MOD_SHIFT|ALT|CTRL`).  Ctrl+letter arrives as the
letter with `TERM_MOD_CTRL`; `^C` never arrives as a key — it sets the
flag behind `TermInterrupted` even in raw mode.

`TermInit(FALSE, FALSE)` skips the alternate screen and raw mode for
plain console programs that just want `TermInterrupted`, sizes, colors,
and `TermReadLine`.

## Example

```holyc
#include "lib/term/term.hc"

U0 Main()
{
  CTermEvent e;
  if (!TermInit)
    return;
  TermText(2, 1, "hello", TERM_BRIGHT_GREEN, TERM_DEFAULT, TERM_BOLD);
  TermCommit;
  while (!TermInterrupted) {
    if (TermPollEvent(&e, 100) && e.type == TERM_EVENT_KEY && e.key == 'q')
      break;
    TermCommit;
  }
  TermFini;
}
Main;
```

See `examples/term.hc` for a fuller demo with mouse and resize handling.
