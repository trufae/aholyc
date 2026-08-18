// Terminal emulator control: a shell ($SHELL on Unix, %COMSPEC%/cmd.exe on
// Windows through ConPTY) inside a window. A small xterm subset is
// understood (cursor motion, erasing, insert/delete, scroll regions, SGR
// with 16/256/true colors); keys, Tab and ^C go to the shell while the
// control has focus. Not built with HTK_NODESK.

#define HTK_TERM_PARAMS 16

class CHtkTerm
{
  I64 fd, pid;             // posix: pty master, child pid
  I64 hpc, hin, hout, hproc; // windows: pseudo console, pipes, process
  I64 cols, rows;
  U64 *cells;              // rows*cols, packed like lib/term cells
  I64 cx, cy;              // cursor
  I64 saved_x, saved_y;
  I64 top, bottom;         // scroll region, inclusive rows
  I64 fg, bg, attr;        // current pen
  I64 state;               // parser: 0 text, 1 ESC, 2 CSI, 3 OSC
  I64 params[HTK_TERM_PARAMS];
  I64 nparams;
  Bool private;            // CSI ? ...
  Bool osc_esc;            // saw ESC inside OSC (waiting for the \\)
  U8 utf8[8];              // pending multibyte sequence
  I64 utf8_len;
  Bool cursor_hidden;
  Bool exited;
};

// pty backend (pty_posix.hc / pty_windows.hc, included after this file)
Bool HtkPtySpawn(CHtkTerm *t, I64 cols, I64 rows);
I64 HtkPtyRead(CHtkTerm *t, U8 *buffer, I64 capacity);
U0 HtkPtyWrite(CHtkTerm *t, U8 *bytes, I64 count);
U0 HtkPtyResize(CHtkTerm *t, I64 cols, I64 rows);
Bool HtkPtyAlive(CHtkTerm *t);
U0 HtkPtyClose(CHtkTerm *t);

// --- screen buffer ----------------------------------------------------------

U64 HtkTermBlank(CHtkTerm *t)
{
  return ' ' | (t->fg & 0x3FFFF) << 28 | (t->bg & 0x3FFFF) << 46;
}

U0 HtkTermClearRows(CHtkTerm *t, I64 from, I64 to)
{
  I64 i;
  U64 blank = HtkTermBlank(t);

  for (i = from * t->cols; i < (to + 1) * t->cols; i++)
    t->cells[i] = blank;
}

U0 HtkTermClearRange(CHtkTerm *t, I64 row, I64 from, I64 to)
{
  I64 i;
  U64 blank = HtkTermBlank(t);

  for (i = from; i <= to && i < t->cols; i++)
    t->cells[row * t->cols + i] = blank;
}

// Scroll the region [top, bottom] up (lines > 0) or down (lines < 0).
U0 HtkTermScroll(CHtkTerm *t, I64 lines)
{
  I64 n = t->bottom - t->top + 1, count = lines;

  if (count < 0)
    count = -count;
  if (count > n)
    count = n;
  if (lines > 0) {
    MemCpy(t->cells + t->top * t->cols, t->cells + (t->top + count) * t->cols,
      (n - count) * t->cols * sizeof(U64));
    HtkTermClearRows(t, t->bottom - count + 1, t->bottom);
  } else if (lines < 0) {
    MemCpy(t->cells + (t->top + count) * t->cols, t->cells + t->top * t->cols,
      (n - count) * t->cols * sizeof(U64));
    HtkTermClearRows(t, t->top, t->top + count - 1);
  }
}

U0 HtkTermResize(CHtkTerm *t, I64 cols, I64 rows)
{
  U64 *cells;
  I64 y, keep;

  if (cols < 2)
    cols = 2;
  if (rows < 1)
    rows = 1;
  if (cols == t->cols && rows == t->rows && t->cells)
    return;
  cells = MAlloc(cols * rows * sizeof(U64));
  for (y = 0; y < cols * rows; y++)
    cells[y] = ' ' | (TERM_WHITE & 0x3FFFF) << 28 | (TERM_BLACK & 0x3FFFF) << 46;
  if (t->cells) {
    keep = t->cols;
    if (cols < keep)
      keep = cols;
    for (y = 0; y < rows && y < t->rows; y++)
      MemCpy(cells + y * cols, t->cells + y * t->cols, keep * sizeof(U64));
    Free(t->cells);
  }
  t->cells = cells;
  t->cols = cols;
  t->rows = rows;
  t->top = 0;
  t->bottom = rows - 1;
  if (t->cx >= cols)
    t->cx = cols - 1;
  if (t->cy >= rows)
    t->cy = rows - 1;
  HtkPtyResize(t, cols, rows);
}

// --- output interpretation ----------------------------------------------------

U0 HtkTermPut(CHtkTerm *t, I64 rune)
{
  if (t->cx >= t->cols) {  // deferred wrap
    t->cx = 0;
    if (t->cy == t->bottom)
      HtkTermScroll(t, 1);
    else if (t->cy < t->rows - 1)
      t->cy++;
  }
  t->cells[t->cy * t->cols + t->cx] = rune & 0x1FFFFF |
    (t->attr & 0x7F) << 21 | (t->fg & 0x3FFFF) << 28 | (t->bg & 0x3FFFF) << 46;
  t->cx++;
}

U0 HtkTermNewline(CHtkTerm *t)
{
  if (t->cy == t->bottom)
    HtkTermScroll(t, 1);
  else if (t->cy < t->rows - 1)
    t->cy++;
}

I64 HtkTermParam(CHtkTerm *t, I64 index, I64 fallback)
{
  if (index >= t->nparams || !t->params[index])
    return fallback;
  return t->params[index];
}

// SGR: colors and attributes, including 38/48;5;n and 38/48;2;r;g;b.
U0 HtkTermSgr(CHtkTerm *t)
{
  I64 i = 0, p, color;

  if (!t->nparams)
    t->nparams = 1;  // bare "m" means reset
  while (i < t->nparams) {
    p = t->params[i++];
    if (!p) {
      t->fg = TERM_WHITE;
      t->bg = TERM_BLACK;
      t->attr = 0;
    } else if (p == 1)
      t->attr |= TERM_BOLD;
    else if (p == 2)
      t->attr |= TERM_DIM;
    else if (p == 3)
      t->attr |= TERM_ITALIC;
    else if (p == 4)
      t->attr |= TERM_UNDERLINE;
    else if (p == 5)
      t->attr |= TERM_BLINK;
    else if (p == 7)
      t->attr |= TERM_REVERSE;
    else if (p == 9)
      t->attr |= TERM_STRIKE;
    else if (p == 22)
      t->attr &= ~(TERM_BOLD | TERM_DIM);
    else if (p == 23)
      t->attr &= ~TERM_ITALIC;
    else if (p == 24)
      t->attr &= ~TERM_UNDERLINE;
    else if (p == 25)
      t->attr &= ~TERM_BLINK;
    else if (p == 27)
      t->attr &= ~TERM_REVERSE;
    else if (p == 29)
      t->attr &= ~TERM_STRIKE;
    else if (p >= 30 && p <= 37)
      t->fg = p - 30;
    else if (p == 39)
      t->fg = TERM_WHITE;
    else if (p >= 40 && p <= 47)
      t->bg = p - 40;
    else if (p == 49)
      t->bg = TERM_BLACK;
    else if (p >= 90 && p <= 97)
      t->fg = p - 90 + 8;
    else if (p >= 100 && p <= 107)
      t->bg = p - 100 + 8;
    else if ((p == 38 || p == 48) && i < t->nparams) {
      color = -1;
      if (t->params[i] == 5 && i + 1 < t->nparams) {
        color = TermColor256(t->params[i + 1]);
        i += 2;
      } else if (t->params[i] == 2 && i + 3 < t->nparams) {
        color = TermColorRgb(t->params[i + 1], t->params[i + 2],
          t->params[i + 3]);
        i += 4;
      } else
        i = t->nparams;
      if (color >= 0) {
        if (p == 38)
          t->fg = color;
        else
          t->bg = color;
      }
    }
  }
}

U0 HtkTermCsi(CHtkTerm *t, I64 final)
{
  I64 n = HtkTermParam(t, 0, 1), m = HtkTermParam(t, 1, 1), i, y;

  if (t->private) {  // DEC private modes: only the cursor matters here
    if ((final == 'h' || final == 'l') && HtkTermParam(t, 0, 0) == 25)
      t->cursor_hidden = final == 'l';
    return;
  }
  switch (final) {
    case 'A':
      t->cy -= n;
      if (t->cy < 0)
        t->cy = 0;
      break;
    case 'B':
      t->cy += n;
      if (t->cy >= t->rows)
        t->cy = t->rows - 1;
      break;
    case 'C':
      t->cx += n;
      if (t->cx >= t->cols)
        t->cx = t->cols - 1;
      break;
    case 'D':
      t->cx -= n;
      if (t->cx < 0)
        t->cx = 0;
      break;
    case 'G':
      t->cx = n - 1;
      break;
    case 'd':
      t->cy = n - 1;
      break;
    case 'H':
    case 'f':
      t->cy = n - 1;
      t->cx = m - 1;
      break;
    case 'J':
      n = HtkTermParam(t, 0, 0);
      if (n == 0) {
        HtkTermClearRange(t, t->cy, t->cx, t->cols - 1);
        if (t->cy < t->rows - 1)
          HtkTermClearRows(t, t->cy + 1, t->rows - 1);
      } else if (n == 1) {
        if (t->cy > 0)
          HtkTermClearRows(t, 0, t->cy - 1);
        HtkTermClearRange(t, t->cy, 0, t->cx);
      } else
        HtkTermClearRows(t, 0, t->rows - 1);
      break;
    case 'K':
      n = HtkTermParam(t, 0, 0);
      if (n == 0)
        HtkTermClearRange(t, t->cy, t->cx, t->cols - 1);
      else if (n == 1)
        HtkTermClearRange(t, t->cy, 0, t->cx);
      else
        HtkTermClearRange(t, t->cy, 0, t->cols - 1);
      break;
    case 'L':  // insert lines at the cursor: scroll the rest down
      if (t->cy >= t->top && t->cy <= t->bottom) {
        y = t->top;
        t->top = t->cy;
        HtkTermScroll(t, -n);
        t->top = y;
      }
      break;
    case 'M':
      if (t->cy >= t->top && t->cy <= t->bottom) {
        y = t->top;
        t->top = t->cy;
        HtkTermScroll(t, n);
        t->top = y;
      }
      break;
    case 'P':  // delete chars
      for (i = t->cx; i < t->cols; i++) {
        if (i + n < t->cols)
          t->cells[t->cy * t->cols + i] = t->cells[t->cy * t->cols + i + n];
        else
          t->cells[t->cy * t->cols + i] = HtkTermBlank(t);
      }
      break;
    case '@':  // insert blanks
      for (i = t->cols - 1; i >= t->cx; i--) {
        if (i - n >= t->cx)
          t->cells[t->cy * t->cols + i] = t->cells[t->cy * t->cols + i - n];
        else
          t->cells[t->cy * t->cols + i] = HtkTermBlank(t);
      }
      break;
    case 'X':
      HtkTermClearRange(t, t->cy, t->cx, t->cx + n - 1);
      break;
    case 'S':
      HtkTermScroll(t, n);
      break;
    case 'T':
      HtkTermScroll(t, -n);
      break;
    case 'r':
      t->top = HtkTermParam(t, 0, 1) - 1;
      t->bottom = HtkTermParam(t, 1, t->rows) - 1;
      if (t->top < 0)
        t->top = 0;
      if (t->bottom >= t->rows)
        t->bottom = t->rows - 1;
      if (t->top >= t->bottom) {
        t->top = 0;
        t->bottom = t->rows - 1;
      }
      t->cx = 0;
      t->cy = t->top;
      break;
    case 's':
      t->saved_x = t->cx;
      t->saved_y = t->cy;
      break;
    case 'u':
      t->cx = t->saved_x;
      t->cy = t->saved_y;
      break;
    case 'm':
      HtkTermSgr(t);
      break;
  }
  if (t->cx < 0)
    t->cx = 0;
  if (t->cx >= t->cols)
    t->cx = t->cols - 1;
  if (t->cy < 0)
    t->cy = 0;
  if (t->cy >= t->rows)
    t->cy = t->rows - 1;
}

U0 HtkTermByte(CHtkTerm *t, I64 byte)
{
  I64 rune, need;

  if (t->state == 1) {  // after ESC
    t->state = 0;
    if (byte == '[') {
      t->state = 2;
      t->nparams = 0;
      t->params[0] = 0;
      t->private = FALSE;
    } else if (byte == ']') {
      t->state = 3;
      t->osc_esc = FALSE;
    } else if (byte == '7') {
      t->saved_x = t->cx;
      t->saved_y = t->cy;
    } else if (byte == '8') {
      t->cx = t->saved_x;
      t->cy = t->saved_y;
    } else if (byte == 'M') {  // reverse index
      if (t->cy == t->top)
        HtkTermScroll(t, -1);
      else if (t->cy > 0)
        t->cy--;
    } else if (byte == 'D')
      HtkTermNewline(t);
    else if (byte == 'E') {
      t->cx = 0;
      HtkTermNewline(t);
    } else if (byte == 'c') {
      HtkTermClearRows(t, 0, t->rows - 1);
      t->cx = 0;
      t->cy = 0;
    } else if (byte == '(' || byte == ')' || byte == '#')
      t->state = 4;  // one more byte to swallow (charset, DEC align)
    return;
  }
  if (t->state == 4) {
    t->state = 0;
    return;
  }
  if (t->state == 2) {  // CSI parameters and final byte
    if (byte >= '0' && byte <= '9') {
      if (t->nparams == 0)
        t->nparams = 1;
      t->params[t->nparams - 1] = t->params[t->nparams - 1] * 10 + byte - '0';
    } else if (byte == ';') {
      if (t->nparams == 0)
        t->nparams = 1;
      if (t->nparams < HTK_TERM_PARAMS)
        t->params[t->nparams++] = 0;
    } else if (byte == '?' || byte == '>' || byte == '=' || byte == '!')
      t->private = TRUE;
    else if (byte >= 0x40 && byte <= 0x7E) {
      t->state = 0;
      HtkTermCsi(t, byte);
    } else if (byte < 0x20)
      HtkTermByte(t, byte);  // C0 controls act even inside a sequence
    return;
  }
  if (t->state == 3) {  // OSC: title and friends, ended by BEL or ESC \\
    if (byte == 7 || (t->osc_esc && byte == '\\'))
      t->state = 0;
    t->osc_esc = byte == 0x1B;
    return;
  }
  // Plain text, controls and UTF-8 assembly.
  if (t->utf8_len) {
    if ((byte & 0xC0) == 0x80) {
      t->utf8[t->utf8_len++] = byte;
      need = 2;
      if ((t->utf8[0] & 0xF0) == 0xE0)
        need = 3;
      else if ((t->utf8[0] & 0xF8) == 0xF0)
        need = 4;
      if (t->utf8_len >= need) {
        if (Utf8DecodeRune(t->utf8, t->utf8_len, &rune))
          HtkTermPut(t, rune);
        t->utf8_len = 0;
      }
      return;
    }
    t->utf8_len = 0;  // broken sequence: drop it, handle this byte
  }
  if (byte >= 0xC0) {
    t->utf8[0] = byte;
    t->utf8_len = 1;
  } else if (byte == 0x1B)
    t->state = 1;
  else if (byte == '\n' || byte == 0x0B || byte == 0x0C)
    HtkTermNewline(t);
  else if (byte == '\r')
    t->cx = 0;
  else if (byte == 8) {
    if (t->cx > 0)
      t->cx--;
  } else if (byte == '\t') {
    t->cx = (t->cx / 8 + 1) * 8;
    if (t->cx >= t->cols)
      t->cx = t->cols - 1;
  } else if (byte >= 0x20 && byte < 0x7F)
    HtkTermPut(t, byte);
}

// --- pty backend -----------------------------------------------------------------
// HtkPtySpawn/Read/Write/Resize/Alive/Close come from pty_posix.hc or
// pty_windows.hc (selected in htk.hc before this file).

// Drain pending output; TRUE when the screen changed.
Bool HtkTermPump(CHtkTerm *t)
{
  U8 buffer[4096];
  I64 n, i;
  Bool changed = FALSE;

  if (t->exited)
    return FALSE;
  while (TRUE) {
    n = HtkPtyRead(t, buffer, sizeof(buffer));
    if (n <= 0)
      break;
    for (i = 0; i < n; i++)
      HtkTermByte(t, buffer[i]);
    changed = TRUE;
  }
  if (!HtkPtyAlive(t)) {
    t->exited = TRUE;
    changed = TRUE;
  }
  return changed;
}

U0 HtkTermSend(CHtkTerm *t, U8 *bytes, I64 count)
{
  if (!t->exited)
    HtkPtyWrite(t, bytes, count);
}

U0 HtkTermFree(CHtkTerm *t)
{
  HtkPtyClose(t);
  Free(t->cells);
  Free(t);
}

// --- the control ---------------------------------------------------------------

CHtkTerm *HtkTermOf(HtkCtl *c)
{
  return c->data(CHtkTerm *);
}

U0 HtkTermTick(I64 a, I64 b)
{
  HtkCtl *c = a;
  CHtkTerm *t = HtkTermOf(c);

  if (HtkTermPump(t))
    htk_dirty = TRUE;
  if (t->exited)
    return;
  HtkHookAdd(20, 0, &HtkTermTick, c, 0);  // re-arm while the shell lives
}

HtkCtl *HtkTerminalNew(I64 cols=80, I64 rows=24)
{
  HtkCtl *c = HtkNew(HTK_TERM);
  CHtkTerm *t = CAlloc(sizeof(CHtkTerm));

  t->fd = -1;
  t->fg = TERM_WHITE;
  t->bg = TERM_BLACK;
  HtkTermResize(t, cols, rows);
  c->data = t;
  c->pw = cols;
  c->ph = rows;
  c->focusable = TRUE;
  c->expand = TRUE;
  if (HtkPtySpawn(t, cols, rows))
    HtkHookAdd(20, 0, &HtkTermTick, c, 0);
  else
    t->exited = TRUE;
  return c;
}

U0 HtkTermMeasure(HtkCtl *c)
{
  c->pw = 20;
  c->ph = 5;
}

U0 HtkTermDraw(HtkCtl *c)
{
  CHtkTerm *t = HtkTermOf(c);
  I64 x, y, fg, bg, attr;
  U64 cell;

  HtkTermResize(t, c->w, c->h);
  for (y = 0; y < t->rows; y++)
    for (x = 0; x < t->cols; x++) {
      cell = t->cells[y * t->cols + x];
      fg = TermCellFg(cell);
      bg = TermCellBg(cell);
      attr = TermCellAttr(cell);
      if (attr & TERM_REVERSE) {
        fg = TermCellBg(cell);
        bg = TermCellFg(cell);
      }
      HtkChr(c->x + x, c->y + y, TermCellChar(cell), fg, bg,
        attr & ~TERM_REVERSE);
    }
  if (t->exited)
    HtkStr(c->x, c->y + t->rows - 1, "[exited]", TERM_BRIGHT_WHITE, TERM_RED);
  if (HtkFocused(c) && !t->cursor_hidden && !t->exited) {
    x = t->cx;
    if (x >= t->cols)
      x = t->cols - 1;
    TermGotoXY(c->x + x, c->y + t->cy);
    TermShowCursor(TRUE);
  }
}

// Translate a lib/term key event into what a terminal would receive.
Bool HtkTermKey(HtkCtl *c, CTermEvent *e)
{
  CHtkTerm *t = HtkTermOf(c);
  U8 out[16];
  I64 n = 0, key = e->key;

  if (t->exited)
    return FALSE;
  if (key >= TERM_KEY_F1 && key <= TERM_KEY_F12) {
    U8 *fkeys[12] = {"\x1BOP", "\x1BOQ", "\x1BOR", "\x1BOS", "\x1B[15~",
        "\x1B[17~", "\x1B[18~", "\x1B[19~", "\x1B[20~", "\x1B[21~", "\x1B[23~",
      "\x1B[24~"};
    HtkTermSend(t, fkeys[key - TERM_KEY_F1], StrLen(fkeys[key - TERM_KEY_F1]));
    return TRUE;
  }
  switch (key) {
    case TERM_KEY_UP:
      HtkTermSend(t, "\x1B[A", 3);
      break;
    case TERM_KEY_DOWN:
      HtkTermSend(t, "\x1B[B", 3);
      break;
    case TERM_KEY_RIGHT:
      HtkTermSend(t, "\x1B[C", 3);
      break;
    case TERM_KEY_LEFT:
      HtkTermSend(t, "\x1B[D", 3);
      break;
    case TERM_KEY_HOME:
      HtkTermSend(t, "\x1B[H", 3);
      break;
    case TERM_KEY_END:
      HtkTermSend(t, "\x1B[F", 3);
      break;
    case TERM_KEY_PGUP:
      HtkTermSend(t, "\x1B[5~", 4);
      break;
    case TERM_KEY_PGDN:
      HtkTermSend(t, "\x1B[6~", 4);
      break;
    case TERM_KEY_INSERT:
      HtkTermSend(t, "\x1B[2~", 4);
      break;
    case TERM_KEY_DELETE:
      HtkTermSend(t, "\x1B[3~", 4);
      break;
    case TERM_KEY_ENTER:
      HtkTermSend(t, "\r", 1);
      break;
    case TERM_KEY_BACKSPACE:
      HtkTermSend(t, "\x7F", 1);
      break;
    case TERM_KEY_TAB:
      HtkTermSend(t, "\t", 1);
      break;
    case TERM_KEY_ESCAPE:
      HtkTermSend(t, "\x1B", 1);
      break;
    default:
      if (key < 0x20 || key >= 0x110000)
        return FALSE;
      if (e->mods & TERM_MOD_CTRL && key < 0x80)
        out[n++] = key & 0x1F;
      else {
        if (e->mods & TERM_MOD_ALT)
          out[n++] = 0x1B;
        n += Utf8EncodeRune(key, out + n);
      }
      HtkTermSend(t, out, n);
  }
  return TRUE;
}

// ^C is trapped by lib/term; hand it to the shell when a terminal has focus.
U0 HtkTermInterrupt()
{
  if (htk_focus && htk_focus->kind == HTK_TERM && TermInterrupted(FALSE)) {
    TermInterrupted(TRUE);
    HtkTermSend(HtkTermOf(htk_focus), "\x03", 1);
  }
}

// Hang up the shells of a window that is closing.
U0 HtkTermClosed(HtkCtl *w)
{
  HtkCtl *k = w->kids;

  while (k) {
    if (k->kind == HTK_TERM && k->data) {
      HtkTermFree(HtkTermOf(k));
      k->data = 0;
    }
    HtkTermClosed(k);
    k = k->sib;
  }
}

// App > Terminal: a window around a fresh shell.
U0 HtkTerminalWindow()
{
  HtkCtl *w = HtkWindowNew("Terminal", 84, 26);
  HtkCtl *term = HtkTerminalNew(80, 24);

  HtkAdd(w, term);
  HtkSetFocus(term);
}
