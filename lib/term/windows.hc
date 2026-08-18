// Win32 console backend.
//
// Windows 10+ consoles accept the same ANSI escapes as POSIX terminals once
// ENABLE_VIRTUAL_TERMINAL_PROCESSING sticks; when it does not, this backend
// reports itself as legacy and the frontend hands it cell spans to blit with
// WriteConsoleOutputW instead of an escape stream.  Input always comes from
// ReadConsoleInputW records, which cover keys, mouse, and resizes without
// any escape parsing.

#define TERM_WIN_STDIN         -10
#define TERM_WIN_STDOUT        -11
#define TERM_WIN_VT            0x4
#define TERM_WIN_PROCESSED_IN  0x1
#define TERM_WIN_LINE_INPUT    0x2
#define TERM_WIN_ECHO_INPUT    0x4
#define TERM_WIN_WINDOW_INPUT  0x8
#define TERM_WIN_MOUSE_INPUT   0x10
#define TERM_WIN_INSERT_MODE   0x20
#define TERM_WIN_QUICK_EDIT    0x40
#define TERM_WIN_EXTENDED      0x80
#define TERM_WIN_UTF8          65001
#define TERM_WIN_WAIT_SLICE    100

extern U8 *GetStdHandle(I64 which);
extern I64 GetConsoleMode(U8 *handle, U32 *mode);
extern I64 SetConsoleMode(U8 *handle, U32 mode);
I64 TermWinCtrl(U32 kind); // console control handler, defined below
extern I64 SetConsoleCtrlHandler(TermWinCtrl *handler, I64 add);
extern I64 GetConsoleScreenBufferInfo(U8 *handle, U8 *info);
extern I64 SetConsoleCursorPosition(U8 *handle, U32 position);
extern I64 GetConsoleCursorInfo(U8 *handle, U8 *info);
extern I64 SetConsoleCursorInfo(U8 *handle, U8 *info);
extern I64 SetConsoleTextAttribute(U8 *handle, U16 attribute);
extern I64 WriteConsoleA(U8 *handle, U8 *text, U32 count, U32 *written,
  U8 *reserved);
extern I64 WriteConsoleOutputW(U8 *handle, U8 *cells, U32 size, U32 origin,
  U8 *region);
extern I64 FillConsoleOutputCharacterW(U8 *handle, U16 ch, U32 count,
  U32 origin, U32 *written);
extern I64 FillConsoleOutputAttribute(U8 *handle, U16 attribute, U32 count,
  U32 origin, U32 *written);
extern I64 ReadConsoleW(U8 *handle, U8 *buffer, U32 count, U32 *got,
  U8 *control);
extern I64 ReadConsoleInputW(U8 *handle, U8 *record, U32 count, U32 *got);
extern U32 WaitForSingleObject(U8 *handle, U32 milliseconds);
extern I64 SetConsoleOutputCP(U32 codepage);
extern U32 GetConsoleOutputCP();
extern U64 GetTickCount64();

I64 TermNativeMs()
{
  return GetTickCount64;
}

class CTermWinInfo
{
  I16 size_x;
  I16 size_y;
  I16 cursor_x;
  I16 cursor_y;
  U16 attributes;
  I16 left;
  I16 top;
  I16 right;
  I16 bottom;
  I16 maximum_x;
  I16 maximum_y;
};

class CTermWinCursor
{
  U32 size;
  I32 visible;
};

class CTermWinKey
{
  U16 kind;
  $$ = 4;
  I32 down;
  U16 repeats;
  U16 virtual_key;
  U16 scan_code;
  U16 unicode;
  U32 control;
};

class CTermWinMouse
{
  U16 kind;
  $$ = 4;
  I16 x;
  I16 y;
  U32 buttons;
  U32 control;
  U32 flags;
};

U8 *term_win_in;
U8 *term_win_out;
U32 term_win_saved_in_mode;
U32 term_win_saved_out_mode;
U32 term_win_saved_cp;
U16 term_win_saved_attr;
Bool term_win_legacy;
Bool term_win_raw;
Bool term_win_mouse_on;
U32 term_win_buttons;
U8 *term_win_blit;
I64 term_win_blit_cells;

// ANSI color index to Win32 attribute nibble: red and blue bits swap.
U8 term_win_colors[8];

I64 TermWinCtrl(U32 kind)
{
  if (kind <= 1) {
    term_interrupted = TRUE;
    return TRUE;
  }
  return FALSE;
}

U0 TermWinApplyMode()
{
  U32 mode = TERM_WIN_PROCESSED_IN | TERM_WIN_WINDOW_INPUT |
    TERM_WIN_EXTENDED;

  if (!term_win_raw)
    mode |= TERM_WIN_LINE_INPUT | TERM_WIN_ECHO_INPUT | TERM_WIN_INSERT_MODE;
  if (term_win_mouse_on)
    mode |= TERM_WIN_MOUSE_INPUT;
  else
    mode |= TERM_WIN_QUICK_EDIT;
  SetConsoleMode(term_win_in, mode);
}

Bool TermNativeInit()
{
  CTermWinInfo info;

  term_win_in = GetStdHandle(TERM_WIN_STDIN);
  term_win_out = GetStdHandle(TERM_WIN_STDOUT);
  if (!GetConsoleMode(term_win_in, &term_win_saved_in_mode)(I32) ||
    !GetConsoleMode(term_win_out, &term_win_saved_out_mode)(I32))
    return FALSE;
  term_win_legacy = !SetConsoleMode(term_win_out,
    term_win_saved_out_mode | TERM_WIN_VT)(I32);
  term_win_saved_cp = GetConsoleOutputCP;
  if (!term_win_legacy)
    SetConsoleOutputCP(TERM_WIN_UTF8);
  term_win_saved_attr = 7;
  if (GetConsoleScreenBufferInfo(term_win_out, &info)(I32))
    term_win_saved_attr = info.attributes;
  term_win_colors[0] = 0;
  term_win_colors[1] = 4;
  term_win_colors[2] = 2;
  term_win_colors[3] = 6;
  term_win_colors[4] = 1;
  term_win_colors[5] = 5;
  term_win_colors[6] = 3;
  term_win_colors[7] = 7;
  term_win_raw = FALSE;
  term_win_mouse_on = FALSE;
  term_win_buttons = 0;
  term_win_blit = NULL;
  term_win_blit_cells = 0;
  SetConsoleCtrlHandler(&TermWinCtrl, TRUE);
  TermWinApplyMode;
  return TRUE;
}

U0 TermNativeFini()
{
  SetConsoleCtrlHandler(&TermWinCtrl, FALSE);
  SetConsoleMode(term_win_in, term_win_saved_in_mode);
  SetConsoleMode(term_win_out, term_win_saved_out_mode);
  if (!term_win_legacy)
    SetConsoleOutputCP(term_win_saved_cp);
  Free(term_win_blit);
  term_win_blit = NULL;
  term_win_blit_cells = 0;
}

Bool TermNativeSize(I64 *width, I64 *height)
{
  CTermWinInfo info;

  if (!GetConsoleScreenBufferInfo(term_win_out, &info)(I32))
    return FALSE;
  *width = info.right - info.left + 1;
  *height = info.bottom - info.top + 1;
  return TRUE;
}

Bool TermNativeRawOn()
{
  term_win_raw = TRUE;
  TermWinApplyMode;
  return TRUE;
}

Bool TermNativeRawOff()
{
  term_win_raw = FALSE;
  TermWinApplyMode;
  return TRUE;
}

U0 TermNativeMouse(Bool enable)
{
  term_win_mouse_on = enable;
  TermWinApplyMode;
}

U0 TermNativeWrite(U8 *bytes, I64 count)
{
  U32 written;

  while (count > 0) {
    if (!WriteConsoleA(term_win_out, bytes, count, &written, NULL)(I32))
      return;
    bytes += written;
    count -= written;
  }
}

Bool TermNativeLegacy()
{
  return term_win_legacy;
}

I64 TermWinAttr(U64 cell)
{
  I64 fg = TermCellFg(cell);
  I64 bg = TermCellBg(cell);
  I64 attr = TermCellAttr(cell);
  I64 fore, back, swap;

  if (fg > 16)  // extended colors degrade to the nearest basic one
    fg = TermRgbToBasic(TermColorToRgb(fg));
  if (bg > 16)
    bg = TermRgbToBasic(TermColorToRgb(bg));
  if (fg > 15)
    fore = term_win_saved_attr & 15;
  else
    fore = term_win_colors[fg & 7] | fg & 8;
  if (bg > 15)
    back = term_win_saved_attr >> 4 & 15;
  else
    back = term_win_colors[bg & 7] | bg & 8;
  if (attr & TERM_BOLD)
    fore |= 8;
  if (attr & TERM_REVERSE) {
    swap = fore;
    fore = back;
    back = swap;
  }
  fore |= back << 4;
  if (attr & TERM_UNDERLINE)
    fore |= 0x8000;  // COMMON_LVB_UNDERSCORE
  return fore;
}

U0 TermNativeBlit(I64 x, I64 y, U64 *cells, I64 count)
{
  U16 *pairs;
  U8 region[8];
  I16 *edges = region;
  I64 i, rune;

  if (count > term_win_blit_cells) {
    Free(term_win_blit);
    term_win_blit_cells = count * 2;
    term_win_blit = MAlloc(term_win_blit_cells * 4);
  }
  pairs = term_win_blit;
  for (i = 0; i < count; i++) {
    rune = TermCellChar(cells[i]);
    if (rune > 0xFFFF)
      rune = '?';
    pairs[i * 2] = rune;
    pairs[i * 2 + 1] = TermWinAttr(cells[i]);
  }
  edges[0] = x;
  edges[1] = y;
  edges[2] = x + count - 1;
  edges[3] = y;
  WriteConsoleOutputW(term_win_out, term_win_blit,
    count & 0xFFFF | 0x10000, 0, region);
}

U0 TermNativeCursor(I64 x, I64 y, Bool visible)
{
  CTermWinCursor cursor;
  CTermWinInfo info;

  if (GetConsoleScreenBufferInfo(term_win_out, &info)(I32)) {
    x += info.left;
    y += info.top;
  }
  SetConsoleCursorPosition(term_win_out, x & 0xFFFF | y << 16);
  if (GetConsoleCursorInfo(term_win_out, &cursor)(I32)) {
    cursor.visible = visible;
    SetConsoleCursorInfo(term_win_out, &cursor);
  }
}

U0 TermNativeAltScreen(Bool enable)
{
  CTermWinInfo info;
  U32 written;
  I64 cells;

  if (!GetConsoleScreenBufferInfo(term_win_out, &info)(I32))
    return;
  cells = info.size_x * info.size_y;
  if (enable) {
    FillConsoleOutputCharacterW(term_win_out, ' ', cells, 0, &written);
    FillConsoleOutputAttribute(term_win_out, term_win_saved_attr, cells, 0,
      &written);
    SetConsoleCursorPosition(term_win_out, 0);
  } else
    SetConsoleTextAttribute(term_win_out, term_win_saved_attr);
}

I64 TermWinVirtualKey(I64 virtual_key)
{
  if (virtual_key == 0x25)
    return TERM_KEY_LEFT;
  if (virtual_key == 0x26)
    return TERM_KEY_UP;
  if (virtual_key == 0x27)
    return TERM_KEY_RIGHT;
  if (virtual_key == 0x28)
    return TERM_KEY_DOWN;
  if (virtual_key == 0x21)
    return TERM_KEY_PGUP;
  if (virtual_key == 0x22)
    return TERM_KEY_PGDN;
  if (virtual_key == 0x23)
    return TERM_KEY_END;
  if (virtual_key == 0x24)
    return TERM_KEY_HOME;
  if (virtual_key == 0x2D)
    return TERM_KEY_INSERT;
  if (virtual_key == 0x2E)
    return TERM_KEY_DELETE;
  if (virtual_key >= 0x70 && virtual_key <= 0x7B)
    return TERM_KEY_F1 + virtual_key - 0x70;
  return 0;
}

I64 TermWinMods(U32 control)
{
  I64 mods = 0;

  if (control & 0x10)
    mods |= TERM_MOD_SHIFT;
  if (control & 3)
    mods |= TERM_MOD_ALT;
  if (control & 0xC)
    mods |= TERM_MOD_CTRL;
  return mods;
}

Bool TermWinKeyEvent(CTermEvent *event, CTermWinKey *key)
{
  I64 code;
  I64 ch = key->unicode;

  if (!key->down)
    return FALSE;
  event->mods = TermWinMods(key->control);
  code = TermWinVirtualKey(key->virtual_key);
  if (!code) {
    if (!ch)
      return FALSE;  // a bare modifier press
    if (ch == '\r' || ch == '\n')
      code = TERM_KEY_ENTER;
    else if (ch == 8 || ch == 127)
      code = TERM_KEY_BACKSPACE;
    else if (ch == '\t')
      code = TERM_KEY_TAB;
    else if (ch == 27)
      code = TERM_KEY_ESCAPE;
    else if (ch < 27)
      code = 'a' + ch - 1;
    else
      code = ch;
  }
  event->type = TERM_EVENT_KEY;
  event->key = code;
  return TRUE;
}

I64 TermWinButton(U32 buttons)
{
  if (buttons & 1)
    return TERM_MOUSE_LEFT;
  if (buttons & 4)
    return TERM_MOUSE_MIDDLE;
  if (buttons & 2)
    return TERM_MOUSE_RIGHT;
  return TERM_MOUSE_NONE;
}

Bool TermWinMouseEvent(CTermEvent *event, CTermWinMouse *mouse)
{
  U32 held = mouse->buttons & 0xFFFF;
  U32 changed;
  I16 delta;

  event->type = TERM_EVENT_MOUSE;
  event->x = mouse->x;
  event->y = mouse->y;
  event->mods = TermWinMods(mouse->control);
  if (mouse->flags & 4) {  // wheel: delta rides the high word
    delta = mouse->buttons >> 16;
    if (delta > 0)
      event->button = TERM_MOUSE_WHEEL_UP;
    else
      event->button = TERM_MOUSE_WHEEL_DOWN;
    event->pressed = TRUE;
    return TRUE;
  }
  if (mouse->flags & 1) {  // motion
    event->button = TermWinButton(held);
    event->pressed = held != 0;
    event->motion = TRUE;
    return TRUE;
  }
  changed = held ^ term_win_buttons;
  term_win_buttons = held;
  if (!changed)
    return FALSE;
  event->button = TermWinButton(changed);
  event->pressed = (held & changed) != 0;
  return TRUE;
}

Bool TermNativePoll(CTermEvent *event, I64 timeout_ms)
{
  U8 record[32];
  U16 *kind = record;
  U32 got;
  U32 wait;

  while (TRUE) {
    if (term_resize_pending) {
      event->type = TERM_EVENT_RESIZE;
      return TRUE;
    }
    // Wait in slices: the ctrl handler runs on another thread and cannot
    // wake this one, so ^C is noticed between slices.
    wait = TERM_WIN_WAIT_SLICE;
    if (timeout_ms >= 0 && timeout_ms < wait)
      wait = timeout_ms;
    if (WaitForSingleObject(term_win_in, wait)(U32)) {
      if (term_interrupted)
        return FALSE;
      if (timeout_ms >= 0) {
        timeout_ms -= wait;
        if (timeout_ms <= 0)
          return FALSE;
      }
    } else {
      if (!ReadConsoleInputW(term_win_in, record, 1, &got)(I32) || !got)
        return FALSE;
      if (kind[0] == 1) {
        if (TermWinKeyEvent(event, record(CTermWinKey *)))
          return TRUE;
      } else if (kind[0] == 2) {
        if (TermWinMouseEvent(event, record(CTermWinMouse *)))
          return TRUE;
      } else if (kind[0] == 4) {
        term_resize_pending = TRUE;
        event->type = TERM_EVENT_RESIZE;
        return TRUE;
      }
      // Swallowed records retry with the full timeout; close enough.
    }
  }
}

I64 TermNativeReadLine(U8 *buffer, I64 capacity)
{
  U16 wide[512];
  U32 got = 0;
  Bool was_raw = term_win_raw;
  I64 length = 0;
  I64 i = 0;
  I64 rune, count;

  if (was_raw) {
    term_win_raw = FALSE;
    TermWinApplyMode;
  }
  if (!ReadConsoleW(term_win_in, wide, 512, &got, NULL)(I32) || !got) {
    if (was_raw) {
      term_win_raw = TRUE;
      TermWinApplyMode;
    }
    buffer[0] = 0;
    return -1;
  }
  while (i < got) {
    rune = wide[i];
    i++;
    if (rune == '\r' || rune == '\n')
      break;
    if (rune >= 0xD800 && rune < 0xDC00 && i < got) {
      rune = 0x10000 + (rune - 0xD800 << 10) + (wide[i] - 0xDC00);
      i++;
    }
    count = Utf8EncodeRune(rune, buffer + length, capacity - 1 - length);
    if (!count)
      break;
    length += count;
  }
  buffer[length] = 0;
  if (was_raw) {
    term_win_raw = TRUE;
    TermWinApplyMode;
  }
  return length;
}
