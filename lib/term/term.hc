#ifndef AHOLYC_LIB_TERM_HC
#define AHOLYC_LIB_TERM_HC

// Portable terminal control for aholyc's native backends.
//
// The screen is an off-screen grid of cells.  Drawing calls only store into
// that grid; TermCommit diffs it against what is already on screen and emits
// the smallest update in a single write, so there is no flickering.  Each
// cell is one aligned U64 store, so any number of threads may draw between
// commits without locks as long as exactly one thread calls TermCommit
// (last writer wins per cell).
//
// Output goes through ANSI escapes on POSIX and on Windows 10+ consoles;
// older Windows consoles fall back to Win32 console cell writes.
//
// Setup:
//   Bool TermInit(alt_screen=TRUE, raw=TRUE);
//   U0   TermFini();
//   I64  TermWidth();  I64 TermHeight();       // cached size
//   Bool TermGetSize(&width, &height);         // live query
//   U0   TermOnResize(callback);               // U0 (*)(I64 width, I64 height)
// Drawing (thread-safe, explicit coordinates):
//   U0   TermCell(x, y, ch, fg=TERM_DEFAULT, bg=TERM_DEFAULT, attr=0);
//   U0   TermText(x, y, text, fg=TERM_DEFAULT, bg=TERM_DEFAULT, attr=0);
//   U0   TermFill(x, y, w, h, ch=' ', fg=..., bg=..., attr=0);
//   U0   TermClear();
// Drawing (single-thread cursor + pen convenience):
//   U0   TermGotoXY(x, y);  TermColor(fg, bg=TERM_DEFAULT);  TermAttr(a);
//   U0   TermPutChar(ch);  TermPuts(text);  TermPrint(fmt, ...);
//   U0   TermShowCursor(visible=TRUE);
//   U0   TermCommit();                         // sync grid to the screen
//   U0   TermRedraw();                         // force full repaint
// Input:
//   Bool TermPollEvent(&event, timeout_ms=-1); // key/mouse/resize
//   I64  TermReadKey(timeout_ms=-1);           // 0 on timeout
//   I64  TermReadLine(buffer, capacity);       // cooked line, -1 on EOF
//   I64  TermReadByte();                       // cooked byte, -1 on EOF
//   Bool TermInterrupted(clear=TRUE);          // did the user press ^C?
//   U0   TermMouse(enable=TRUE);
//   U0   TermRaw(enable=TRUE);
// Raw output, for line editors and other scrolling uses of the terminal:
//   U0   TermWrite(bytes, count);              // bypass the cell grid
//   Bool TermLegacy();                         // console without ANSI

// Colors: 16 ANSI colors plus the terminal default.
#define TERM_BLACK          0
#define TERM_RED            1
#define TERM_GREEN          2
#define TERM_YELLOW         3
#define TERM_BLUE           4
#define TERM_MAGENTA        5
#define TERM_CYAN           6
#define TERM_WHITE          7
#define TERM_GRAY           8
#define TERM_BRIGHT_RED     9
#define TERM_BRIGHT_GREEN   10
#define TERM_BRIGHT_YELLOW  11
#define TERM_BRIGHT_BLUE    12
#define TERM_BRIGHT_MAGENTA 13
#define TERM_BRIGHT_CYAN    14
#define TERM_BRIGHT_WHITE   15
#define TERM_DEFAULT        16
// Extended colors: TermColor256(n) and TermColorRgb(r, g, b) return values
// usable wherever a color is expected; TermOutPen degrades them to what the
// terminal supports (TermColorDepth: 16, 256 or 16777216).

// Cell attributes.  Legacy Windows consoles render bold as bright and
// underline natively; italic, strike, dim, and blink degrade to plain there.
#define TERM_BOLD      1
#define TERM_UNDERLINE 2
#define TERM_REVERSE   4
#define TERM_ITALIC    8
#define TERM_STRIKE    16
#define TERM_DIM       32
#define TERM_BLINK     64

// Event types.
#define TERM_EVENT_NONE   0
#define TERM_EVENT_KEY    1
#define TERM_EVENT_MOUSE  2
#define TERM_EVENT_RESIZE 3

// Keys: printable keys are Unicode codepoints; specials sit above them.
#define TERM_KEY_TAB       9
#define TERM_KEY_ENTER     13
#define TERM_KEY_ESCAPE    27
#define TERM_KEY_BACKSPACE 127
#define TERM_KEY_UP        0x110001
#define TERM_KEY_DOWN      0x110002
#define TERM_KEY_RIGHT     0x110003
#define TERM_KEY_LEFT      0x110004
#define TERM_KEY_HOME      0x110005
#define TERM_KEY_END       0x110006
#define TERM_KEY_PGUP      0x110007
#define TERM_KEY_PGDN      0x110008
#define TERM_KEY_INSERT    0x110009
#define TERM_KEY_DELETE    0x11000A
#define TERM_KEY_F1        0x110011
#define TERM_KEY_F2        0x110012
#define TERM_KEY_F3        0x110013
#define TERM_KEY_F4        0x110014
#define TERM_KEY_F5        0x110015
#define TERM_KEY_F6        0x110016
#define TERM_KEY_F7        0x110017
#define TERM_KEY_F8        0x110018
#define TERM_KEY_F9        0x110019
#define TERM_KEY_F10       0x11001A
#define TERM_KEY_F11       0x11001B
#define TERM_KEY_F12       0x11001C

// Modifier bits.
#define TERM_MOD_SHIFT 1
#define TERM_MOD_ALT   2
#define TERM_MOD_CTRL  4

// Mouse buttons.
#define TERM_MOUSE_NONE       0
#define TERM_MOUSE_LEFT       1
#define TERM_MOUSE_MIDDLE     2
#define TERM_MOUSE_RIGHT      3
#define TERM_MOUSE_WHEEL_UP   4
#define TERM_MOUSE_WHEEL_DOWN 5

#include "../text/utf8.HC"

class CTermEvent
{
  I64 type;      // TERM_EVENT_*
  I64 key;       // codepoint or TERM_KEY_*
  I64 mods;      // TERM_MOD_* bits
  I64 x;         // mouse cell, 0-based
  I64 y;
  I64 button;    // TERM_MOUSE_*
  Bool pressed;  // mouse: button is down
  Bool motion;   // mouse: movement report, not a new press
  I64 width;     // resize: new size
  I64 height;
};

// A cell packs into one U64 so a store is atomic on 64-bit targets:
// codepoint in bits 0..20, attr 21..27, fg 28..45, bg 46..63.
#define TERM_CELL_EMPTY   0x400100000020
#define TERM_CELL_INVALID 0xFFFFFFFFFFFFFFFF

// Set by the backends, polled by the application.
Bool term_interrupted;
Bool term_resize_pending;

I64 term_width;
I64 term_height;
U64 *term_back;
U64 *term_front;
I64 term_cursor_x;
I64 term_cursor_y;
I64 term_fg;
I64 term_bg;
I64 term_attr;
Bool term_cursor_visible;
Bool term_started;
Bool term_alt_screen;
Bool term_raw;
Bool term_mouse;
U0 TermResizeCallback(I64 width, I64 height); // ran after a resize
TermResizeCallback *term_resize_callback;
U8 *term_out;
I64 term_out_length;
I64 term_out_capacity;
I64 term_committed_x;
I64 term_committed_y;
Bool term_committed_visible;

// Decode the next rune of a NUL-terminated string at *index, advancing it.
// Invalid bytes consume one byte and decode to the replacement rune, so
// broken input cannot stall a caller.
I64 TermRuneNext(U8 *text, I64 *index)
{
  I64 rune;
  I64 consumed = Utf8DecodeRune(text + *index, 4, &rune);

  if (!consumed) {
    (*index)++;
    return RUNE_REPLACEMENT;
  }
  *index += consumed;
  return rune;
}

// Cell unpacking and color degradation, used by the native backends below.
I64 TermCellChar(U64 cell);
I64 TermCellAttr(U64 cell);
I64 TermCellFg(U64 cell);
I64 TermCellBg(U64 cell);
I64 TermColorToRgb(I64 color);
I64 TermRgbToBasic(I64 rgb);

// TERM_WINDOWS/TERM_POSIX let cross-builds override the compiler host.
#ifdef TERM_WINDOWS
#include "windows.hc"
#else
#ifdef TERM_POSIX
#include "posix.hc"
#else
#ifdef IS_WINDOWS
#include "windows.hc"
#else
#ifdef IS_UNIX
#include "posix.hc"
#else
#error lib/term supports Linux, macOS, and Windows native targets
#endif
#endif
#endif
#endif

U0 TermEmit(U8 *text)
{
  TermNativeWrite(text, StrLen(text));
}

U0 TermOutReserve(I64 need)
{
  U8 *grown;

  if (term_out_length + need <= term_out_capacity)
    return;
  while (term_out_length + need > term_out_capacity)
    term_out_capacity *= 2;
  grown = MAlloc(term_out_capacity);
  MemCpy(grown, term_out, term_out_length);
  Free(term_out);
  term_out = grown;
}

U0 TermOutText(U8 *text)
{
  I64 length = StrLen(text);

  TermOutReserve(length);
  MemCpy(term_out + term_out_length, text, length);
  term_out_length += length;
}

U0 TermOutChar(I64 rune)
{
  I64 count;

  TermOutReserve(4);
  count = Utf8EncodeRune(rune, term_out + term_out_length);
  if (!count) {
    term_out[term_out_length] = '?';
    count = 1;
  }
  term_out_length += count;
}

U0 TermOutMove(I64 x, I64 y)
{
  U8 sequence[32];

  StrPrint(sequence, "\x1B[%d;%dH", y + 1, x + 1);
  TermOutText(sequence);
}

// Full reset-based SGR: a few bytes more than incremental updates, but
// always correct and trivially portable.
// --- extended colors ------------------------------------------------------

extern U8 *getenv(U8 *name);

I64 term_color_depth = 16;   // 16, 256 or 16777216
I64 *term_rgb_table;         // registry behind TermColorRgb handles
I64 term_rgb_count;
I64 term_rgb_cap;

// The xterm defaults for the 16 basic colors, as 0xRRGGBB.
I64 term_basic_rgb[16] = {
  0x000000, 0xCD0000, 0x00CD00, 0xCDCD00, 0x0000EE,
  0xCD00CD, 0x00CDCD, 0xE5E5E5, 0x7F7F7F, 0xFF0000, 0x00FF00, 0xFFFF00,
  0x5C5CFF, 0xFF00FF, 0x00FFFF, 0xFFFFFF
};

public I64 TermColorDepth()
{
  return term_color_depth;
}

public U0 TermSetColorDepth(I64 colors)
{
  term_color_depth = colors;
}

U0 TermDetectColorDepth()
{
  U8 *colorterm = getenv("COLORTERM");
  U8 *term = getenv("TERM");

  term_color_depth = 16;
  if (term && MemMem(term, StrLen(term), "256", 3))
    term_color_depth = 256;
  if (colorterm && (!StrCmp(colorterm, "truecolor") ||
      !StrCmp(colorterm, "24bit")))
    term_color_depth = 16777216;
}

// A color from the 256-color palette (0..255).
public I64 TermColor256(I64 index)
{
  return 256 + (index & 0xFF);
}

// A 24-bit color; distinct values get a handle in a growing registry.
public I64 TermColorRgb(I64 r, I64 g, I64 b)
{
  I64 rgb = (r & 0xFF) << 16 | (g & 0xFF) << 8 | b & 0xFF;
  I64 i;
  I64 *grown;

  for (i = 0; i < term_rgb_count; i++)
    if (term_rgb_table[i] == rgb)
      return 512 + i;
  if (term_rgb_count == term_rgb_cap) {
    term_rgb_cap = term_rgb_cap * 2 + 64;
    grown = MAlloc(term_rgb_cap * sizeof(I64));
    if (term_rgb_count)
      MemCpy(grown, term_rgb_table, term_rgb_count * sizeof(I64));
    Free(term_rgb_table);
    term_rgb_table = grown;
  }
  term_rgb_table[term_rgb_count] = rgb;
  return 512 + term_rgb_count++;
}

I64 TermCubeLevel(I64 step)
{
  if (!step)
    return 0;
  return 55 + step * 40;
}

I64 TermCubeStep(I64 level)
{
  if (level < 48)
    return 0;
  if (level < 115)
    return 1;
  return (level - 35) / 40;
}

// 0xRRGGBB for any color value; TERM_DEFAULT reports -1.
public I64 TermColorToRgb(I64 color)
{
  I64 index, level;

  if (color < 16)
    return term_basic_rgb[color & 15];
  if (color == TERM_DEFAULT)
    return -1;
  if (color < 512) {
    index = color - 256;
    if (index < 16)
      return term_basic_rgb[index];
    if (index < 232) {  // 6x6x6 cube
      index -= 16;
      return TermCubeLevel(index / 36) << 16 |
        TermCubeLevel(index / 6 % 6) << 8 | TermCubeLevel(index % 6);
    }
    level = 8 + (index - 232) * 10;
    return level << 16 | level << 8 | level;
  }
  if (color - 512 < term_rgb_count)
    return term_rgb_table[color - 512];
  return -1;
}

// Nearest basic color by RGB distance.
I64 TermRgbToBasic(I64 rgb)
{
  I64 i, best = 0, best_d = 0x7FFFFFFF, d, dr, dg, db;

  for (i = 0; i < 16; i++) {
    dr = (rgb >> 16 & 0xFF) - (term_basic_rgb[i] >> 16 & 0xFF);
    dg = (rgb >> 8 & 0xFF) - (term_basic_rgb[i] >> 8 & 0xFF);
    db = (rgb & 0xFF) - (term_basic_rgb[i] & 0xFF);
    d = dr * dr + dg * dg + db * db;
    if (d < best_d) {
      best_d = d;
      best = i;
    }
  }
  return best;
}

I64 TermRgbTo256(I64 rgb)
{
  return 16 + 36 * TermCubeStep(rgb >> 16 & 0xFF) +
    6 * TermCubeStep(rgb >> 8 & 0xFF) + TermCubeStep(rgb & 0xFF);
}

// Append a non-negative decimal number and return the next free byte.
U8 *TermPenNumber(U8 *at, I64 number)
{
  U8 digits[20];
  I64 length = 0;

  do {
    digits[length++] = '0' + number % 10;
    number /= 10;
  } while (number);
  while (length)
    *at++ = digits[--length];
  return at;
}

// Append an SGR fragment (";38;5;n" style), degraded to the color depth.
U8 *TermPenColor(U8 *at, I64 color, Bool bg)
{
  I64 base = 30, rgb;

  if (bg)
    base = 40;
  if (color >= 512 && term_color_depth < 16777216) {  // rgb -> 256 or 16
    rgb = TermColorToRgb(color);
    if (term_color_depth >= 256)
      color = TermColor256(TermRgbTo256(rgb));
    else
      color = TermRgbToBasic(rgb);
  }
  if (color >= 256 && color < 512 && term_color_depth < 256)
    color = TermRgbToBasic(TermColorToRgb(color));
  *at++ = ';';
  if (color < 8)
    return TermPenNumber(at, base + color);
  if (color < 16)
    return TermPenNumber(at, base + 60 + color - 8);
  if (color == TERM_DEFAULT)
    return TermPenNumber(at, base + 9);
  at = TermPenNumber(at, base + 8);
  if (color < 512) {
    *at++ = ';';
    *at++ = '5';
    *at++ = ';';
    return TermPenNumber(at, color - 256);
  }
  *at++ = ';';
  *at++ = '2';
  *at++ = ';';
  rgb = TermColorToRgb(color);
  at = TermPenNumber(at, rgb >> 16 & 0xFF);
  *at++ = ';';
  at = TermPenNumber(at, rgb >> 8 & 0xFF);
  *at++ = ';';
  return TermPenNumber(at, rgb & 0xFF);
}

U0 TermOutPen(I64 fg, I64 bg, I64 attr)
{
  U8 sequence[96];
  U8 *at = sequence;

  *at++ = 0x1B;
  *at++ = '[';
  *at++ = '0';
  if (attr & TERM_BOLD) {
    *at++ = ';';
    *at++ = '1';
  }
  if (attr & TERM_DIM) {
    *at++ = ';';
    *at++ = '2';
  }
  if (attr & TERM_ITALIC) {
    *at++ = ';';
    *at++ = '3';
  }
  if (attr & TERM_UNDERLINE) {
    *at++ = ';';
    *at++ = '4';
  }
  if (attr & TERM_BLINK) {
    *at++ = ';';
    *at++ = '5';
  }
  if (attr & TERM_REVERSE) {
    *at++ = ';';
    *at++ = '7';
  }
  if (attr & TERM_STRIKE) {
    *at++ = ';';
    *at++ = '9';
  }
  at = TermPenColor(at, fg, FALSE);
  at = TermPenColor(at, bg, TRUE);
  *at++ = 'm';
  *at = 0;
  TermOutText(sequence);
}

U0 TermBuffersAlloc()
{
  I64 cells = term_width * term_height;
  I64 i;

  term_back = MAlloc(cells * sizeof(U64));
  term_front = MAlloc(cells * sizeof(U64));
  for (i = 0; i < cells; i++) {
    term_back[i] = TERM_CELL_EMPTY;
    term_front[i] = TERM_CELL_INVALID;
  }
}

// Pick up a pending resize: refit the buffers, forget the old screen so the
// next commit repaints fully, and tell the application.
U0 TermSyncSize()
{
  I64 width, height;

  if (!term_resize_pending)
    return;
  term_resize_pending = FALSE;
  if (!TermNativeSize(&width, &height))
    return;
  if (width == term_width && height == term_height)
    return;
  Free(term_back);
  Free(term_front);
  term_width = width;
  term_height = height;
  TermBuffersAlloc;
  if (term_cursor_x >= width)
    term_cursor_x = width - 1;
  if (term_cursor_y >= height)
    term_cursor_y = height - 1;
  if (term_resize_callback)
    term_resize_callback(width, height);
}

public Bool TermInit(Bool alt_screen=TRUE, Bool raw=TRUE)
{
  if (term_started)
    return TRUE;
  if (!TermNativeInit)
    return FALSE;
  if (!TermNativeSize(&term_width, &term_height)) {
    TermNativeFini;
    return FALSE;
  }
  TermDetectColorDepth;
  term_fg = TERM_DEFAULT;
  term_bg = TERM_DEFAULT;
  term_attr = 0;
  term_cursor_x = 0;
  term_cursor_y = 0;
  term_cursor_visible = TRUE;
  term_committed_x = -1;
  term_committed_y = -1;
  term_committed_visible = TRUE;
  term_interrupted = FALSE;
  term_resize_pending = FALSE;
  term_resize_callback = NULL;
  term_out_capacity = 4096;
  term_out_length = 0;
  term_out = MAlloc(term_out_capacity);
  TermBuffersAlloc;
  term_alt_screen = alt_screen;
  if (alt_screen) {
    if (TermNativeLegacy)
      TermNativeAltScreen(TRUE);
    else
      TermEmit("\x1B[?1049h\x1B[2J\x1B[H");
  }
  if (raw)
    term_raw = TermNativeRawOn;
  term_started = TRUE;
  return TRUE;
}

public U0 TermFini()
{
  if (!term_started)
    return;
  if (term_mouse)
    TermNativeMouse(FALSE);
  term_mouse = FALSE;
  if (TermNativeLegacy) {
    TermNativeCursor(term_cursor_x, term_cursor_y, TRUE);
    if (term_alt_screen)
      TermNativeAltScreen(FALSE);
  } else {
    if (term_alt_screen)
      TermEmit("\x1B[0m\x1B[?25h\x1B[?1049l");
    else
      TermEmit("\x1B[0m\x1B[?25h\n");
  }
  if (term_raw)
    TermNativeRawOff;
  term_raw = FALSE;
  TermNativeFini;
  Free(term_back);
  Free(term_front);
  Free(term_out);
  term_back = NULL;
  term_front = NULL;
  term_out = NULL;
  term_started = FALSE;
}

public I64 TermWidth()
{
  return term_width;
}

public I64 TermHeight()
{
  return term_height;
}

public Bool TermGetSize(I64 *width, I64 *height)
{
  return TermNativeSize(width, height);
}

// callback: U0 (*)(I64 width, I64 height), ran during TermCommit or
// TermPollEvent after the buffers have been resized.
public U0 TermOnResize(TermResizeCallback *callback)
{
  term_resize_callback = callback;
}

// Monotonic milliseconds, for animation and timer arithmetic.
public I64 TermMs()
{
  return TermNativeMs;
}

// Read a cell from the drawing grid (as last written, not as displayed).
public U64 TermPeek(I64 x, I64 y)
{
  if (x < 0 || y < 0 || x >= term_width || y >= term_height || !term_back)
    return TERM_CELL_EMPTY;
  return term_back[y * term_width + x];
}

public Bool TermInterrupted(Bool clear=TRUE)
{
  Bool hit = term_interrupted;

  if (hit && clear)
    term_interrupted = FALSE;
  return hit;
}

public U0 TermRaw(Bool enable=TRUE)
{
  if (enable)
    term_raw = TermNativeRawOn;
  else {
    TermNativeRawOff;
    term_raw = FALSE;
  }
}

public U0 TermMouse(Bool enable=TRUE)
{
  term_mouse = enable;
  TermNativeMouse(enable);
}

public U0 TermCell(I64 x, I64 y, I64 ch,
  I64 fg=TERM_DEFAULT, I64 bg=TERM_DEFAULT, I64 attr=0)
{
  if (x < 0 || y < 0 || x >= term_width || y >= term_height)
    return;
  term_back[y * term_width + x] = ch & 0x1FFFFF | (attr & 0x7F) << 21 |
    (fg & 0x3FFFF) << 28 | (bg & 0x3FFFF) << 46;
}

public I64 TermCellChar(U64 cell)
{
  return cell & 0x1FFFFF;
}

public I64 TermCellAttr(U64 cell)
{
  return cell >> 21 & 0x7F;
}

public I64 TermCellFg(U64 cell)
{
  return cell >> 28 & 0x3FFFF;
}

public I64 TermCellBg(U64 cell)
{
  return cell >> 46 & 0x3FFFF;
}

public U0 TermText(I64 x, I64 y, U8 *text,
  I64 fg=TERM_DEFAULT, I64 bg=TERM_DEFAULT, I64 attr=0)
{
  I64 index = 0;

  if (!text)
    return;
  while (text[index]) {
    TermCell(x, y, TermRuneNext(text, &index), fg, bg, attr);
    x++;
  }
}

public U0 TermFill(I64 x, I64 y, I64 width, I64 height, I64 ch=' ',
  I64 fg=TERM_DEFAULT, I64 bg=TERM_DEFAULT, I64 attr=0)
{
  I64 row, column;

  for (row = y; row < y + height; row++)
    for (column = x; column < x + width; column++)
      TermCell(column, row, ch, fg, bg, attr);
}

public U0 TermClear()
{
  I64 cells = term_width * term_height;
  I64 i;

  for (i = 0; i < cells; i++)
    term_back[i] = TERM_CELL_EMPTY;
}

// Forget what is on screen so the next commit repaints every cell.
public U0 TermRedraw()
{
  I64 cells = term_width * term_height;
  I64 i;

  for (i = 0; i < cells; i++)
    term_front[i] = TERM_CELL_INVALID;
}

public U0 TermGotoXY(I64 x, I64 y)
{
  if (x < 0)
    x = 0;
  if (y < 0)
    y = 0;
  if (x >= term_width)
    x = term_width - 1;
  if (y >= term_height)
    y = term_height - 1;
  term_cursor_x = x;
  term_cursor_y = y;
}

public U0 TermColor(I64 fg, I64 bg=TERM_DEFAULT)
{
  term_fg = fg;
  term_bg = bg;
}

public U0 TermAttr(I64 attr)
{
  term_attr = attr;
}

public U0 TermShowCursor(Bool visible=TRUE)
{
  term_cursor_visible = visible;
}

public U0 TermPutChar(I64 ch)
{
  if (ch == '\n') {
    term_cursor_x = 0;
    if (term_cursor_y < term_height - 1)
      term_cursor_y++;
    return;
  }
  if (ch == '\r') {
    term_cursor_x = 0;
    return;
  }
  if (ch == '\t') {
    term_cursor_x = (term_cursor_x & ~7) + 8;
    if (term_cursor_x >= term_width)
      term_cursor_x = term_width - 1;
    return;
  }
  TermCell(term_cursor_x, term_cursor_y, ch, term_fg, term_bg, term_attr);
  term_cursor_x++;
  if (term_cursor_x >= term_width) {
    term_cursor_x = 0;
    if (term_cursor_y < term_height - 1)
      term_cursor_y++;
  }
}

public U0 TermPuts(U8 *text)
{
  I64 index = 0;

  if (!text)
    return;
  while (text[index])
    TermPutChar(TermRuneNext(text, &index));
}

public U0 TermPrint(U8 *fmt, ...)
{
  U8 *text = StrPrintJoin(NULL, fmt, argc, argv);

  TermPuts(text);
  Free(text);
}

U0 TermCommitLegacy()
{
  I64 x, y, start, index;

  for (y = 0; y < term_height; y++) {
    x = 0;
    while (x < term_width) {
      index = y * term_width + x;
      if (term_back[index] == term_front[index]) {
        x++;
      } else {
        start = x;
        while (x < term_width) {
          index = y * term_width + x;
          if (term_back[index] == term_front[index])
            break;
          term_front[index] = term_back[index];
          x++;
        }
        TermNativeBlit(start, y, term_back + (y * term_width + start),
          x - start);
      }
    }
  }
  TermNativeCursor(term_cursor_x, term_cursor_y, term_cursor_visible);
}

public U0 TermCommit()
{
  I64 x, y, index;
  U64 cell, pen;
  I64 last_x, last_y;
  U64 last_pen;
  Bool changed = FALSE;

  if (!term_started)
    return;
  TermSyncSize;
  if (TermNativeLegacy) {
    TermCommitLegacy;
    return;
  }
  term_out_length = 0;
  TermOutText("\x1B[?25l");
  last_x = -2;
  last_y = -2;
  last_pen = TERM_CELL_INVALID;
  for (y = 0; y < term_height; y++) {
    for (x = 0; x < term_width; x++) {
      index = y * term_width + x;
      cell = term_back[index];
      if (cell != term_front[index]) {
        term_front[index] = cell;
        changed = TRUE;
        if (x != last_x || y != last_y)
          TermOutMove(x, y);
        pen = cell >> 21;
        if (pen != last_pen) {
          TermOutPen(TermCellFg(cell), TermCellBg(cell), TermCellAttr(cell));
          last_pen = pen;
        }
        TermOutChar(TermCellChar(cell));
        last_x = x + 1;
        last_y = y;
        if (last_x >= term_width)
          last_x = -2;
      }
    }
  }
  TermOutText("\x1B[0m");
  TermOutMove(term_cursor_x, term_cursor_y);
  if (term_cursor_visible)
    TermOutText("\x1B[?25h");
  if (changed || term_cursor_x != term_committed_x ||
    term_cursor_y != term_committed_y ||
    term_cursor_visible != term_committed_visible) {
      TermNativeWrite(term_out, term_out_length);
      term_committed_x = term_cursor_x;
      term_committed_y = term_cursor_y;
      term_committed_visible = term_cursor_visible;
    }
}

public Bool TermPollEvent(CTermEvent *event, I64 timeout_ms=-1)
{
  Bool got;

  if (!event || !term_started)
    return FALSE;
  MemSet(event, 0, sizeof(CTermEvent));
  got = TermNativePoll(event, timeout_ms);
  if (got && event->type == TERM_EVENT_RESIZE) {
    TermSyncSize;
    event->width = term_width;
    event->height = term_height;
  }
  return got;
}

// Wait for a key press, skipping other events; 0 on timeout or interrupt.
public I64 TermReadKey(I64 timeout_ms=-1)
{
  CTermEvent event;

  while (TermPollEvent(&event, timeout_ms))
    if (event.type == TERM_EVENT_KEY)
      return event.key;
  return 0;
}

// Cooked line input: the terminal handles editing until Enter.  Raw mode is
// suspended for the duration.  Returns the length, or -1 on end of input.
public I64 TermReadLine(U8 *buffer, I64 capacity)
{
  if (!buffer || capacity < 1)
    return -1;
  return TermNativeReadLine(buffer, capacity);
}

// One cooked byte from standard input, -1 on end of input.  Unlike the
// event API this needs no TermInit, so pipes and files work too.
public I64 TermReadByte()
{
  return TermNativeReadByte;
}

// Raw bytes straight to the terminal, bypassing the cell grid.
public U0 TermWrite(U8 *bytes, I64 count)
{
  if (bytes && count > 0)
    TermNativeWrite(bytes, count);
}

// A legacy Win32 console that cannot render ANSI escape sequences.
public Bool TermLegacy()
{
  return TermNativeLegacy;
}

#endif
