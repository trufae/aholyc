// Text input: single-line entry (optionally masked) and a plain multiline
// editor.  The cursor is a byte index; movement steps whole UTF-8 runes.

// limit bounds the text length in bytes; 0 means unlimited.
HtkCtl *HtkEntryNew(U8 *text, I64 limit=0)
{
  HtkCtl *c = HtkNew(HTK_ENTRY);

  HtkSetText(c, text);
  c->cursor = StrLen(text);
  c->high = limit;
  c->focusable = TRUE;
  c->expand = TRUE;
  return c;
}

U0 HtkTextInsert(HtkCtl *c, I64 rune)
{
  U8 bytes[8];
  I64 count = Utf8EncodeRune(rune, bytes);
  I64 length = StrLen(c->text);

  if (c->readonly)
    return;
  U8 *grown;

  if (!count)
    return;
  if (c->kind == HTK_ENTRY && c->high && length + count > c->high)
    return;
  grown = MAlloc(length + count + 1);
  MemCpy(grown, c->text, c->cursor);
  MemCpy(grown + c->cursor, bytes, count);
  StrCpy(grown + c->cursor + count, c->text + c->cursor);
  HtkFreeText(c);
  c->text = grown;
  c->cursor += count;
  HtkFire(c);
}

// One rune left of the cursor, as a byte count.
I64 HtkTextStepBack(HtkCtl *c)
{
  I64 back = c->cursor - 1;

  while (back > 0 && (c->text[back] & 0xC0) == 0x80)
    back--;
  if (back < 0)
    back = 0;
  return c->cursor - back;
}

I64 HtkTextStepAhead(HtkCtl *c)
{
  I64 i = c->cursor;
  I64 rune;
  I64 count = Utf8DecodeRune(c->text + i, 4, &rune);

  if (!count && c->text[i])
    count = 1;
  return count;
}

U0 HtkTextDelete(HtkCtl *c, I64 at, I64 count)
{
  I64 length = StrLen(c->text);

  if (c->readonly || at < 0 || count < 1 || at >= length)
    return;
  StrCpy(c->text + at, c->text + at + count);
  if (c->cursor > at)
    c->cursor = at;
  HtkFire(c);
}

// Selection is the byte range between anchor and cursor.
Bool HtkTextSelected(HtkCtl *c, I64 *from, I64 *to)
{
  if (c->anchor < 0 || c->anchor == c->cursor)
    return FALSE;
  *from = c->anchor;
  *to = c->cursor;
  if (*from > *to) {
    *from = c->cursor;
    *to = c->anchor;
  }
  return TRUE;
}

// Remove the selected bytes; TRUE when something was removed.
Bool HtkTextDeleteSelection(HtkCtl *c)
{
  I64 from, to;

  if (!HtkTextSelected(c, &from, &to)) {
    c->anchor = -1;
    return FALSE;
  }
  c->cursor = to;
  HtkTextDelete(c, from, to - from);
  c->cursor = from;
  c->anchor = -1;
  return TRUE;
}

// Shift+movement extends the selection, plain movement drops it.
U0 HtkTextMoveStart(HtkCtl *c, CTermEvent *e)
{
  if (e->mods & TERM_MOD_SHIFT) {
    if (c->anchor < 0)
      c->anchor = c->cursor;
  } else
    c->anchor = -1;
}

// Cursor at display column x of an entry (respecting its scroll offset).
U0 HtkEntryCursorAt(HtkCtl *c, I64 x)
{
  I64 want = x - c->x;
  I64 i = c->top;

  while (want > 0 && c->text[i]) {
    TermRuneNext(c->text, &i);
    want--;
  }
  c->cursor = i;
  htk_dirty = TRUE;
}

// Cursor at cell (x, y) of a multiline: row top+dy, then column dx.
U0 HtkMultilineCursorAt(HtkCtl *c, I64 x, I64 y)
{
  I64 row = c->top + y - c->y, col = x - c->x, i = 0;

  while (row > 0 && c->text[i]) {
    if (c->text[i] == '\n')
      row--;
    i++;
  }
  while (col > 0 && c->text[i] && c->text[i] != '\n') {
    TermRuneNext(c->text, &i);
    col--;
  }
  c->cursor = i;
  htk_dirty = TRUE;
}

U0 HtkEntryMeasure(HtkCtl *c)
{
  c->pw = 16;
  if (c->low > c->pw)
    c->pw = c->low;  // low is the preferred width, when set
  c->ph = 1;
}

U0 HtkEntryDraw(HtkCtl *c)
{
  I64 i = c->top, x = c->x, rune, at = c->x;
  I64 sel_from = -1, sel_to = -1;
  Bool focused = HtkFocused(c), selected;

  // Keep the cursor inside the view.
  if (c->cursor < c->top)
    c->top = c->cursor;
  if (c->top > StrLen(c->text))
    c->top = 0;
  HtkRect(c->x, c->y, c->w, 1, ' ', HTK_C_FIELD_FG, HTK_C_FIELD_BG);
  i = c->top;
  HtkTextSelected(c, &sel_from, &sel_to);
  while (c->text[i] && x < c->x + c->w) {
    if (i == c->cursor)
      at = x;
    selected = i >= sel_from && i < sel_to;
    rune = TermRuneNext(c->text, &i);
    if (c->secret)
      rune = '*';
    if (selected)
      HtkChr(x, c->y, rune, HTK_C_SEL_FG, HTK_C_SEL_BG);
    else
      HtkChr(x, c->y, rune, HtkInk(c, HTK_C_FIELD_FG), HTK_C_FIELD_BG);
    x++;
  }
  if (c->cursor >= i)
    at = x;
  if (at >= c->x + c->w) {
    // Cursor ran off the right edge: scroll one step and retry next frame.
    c->top += HtkTextStepBack(c);
    htk_dirty = TRUE;
    at = c->x + c->w - 1;
  }
  if (focused && !c->disabled) {
    TermGotoXY(at, c->y);
    TermShowCursor(TRUE);
  }
}

Bool HtkEntryKey(HtkCtl *c, CTermEvent *e)
{
  I64 key = e->key, from, saved, step;

  if (key == 'a' && e->mods & TERM_MOD_CTRL) {
    HtkTextMoveStart(c, e);
    c->cursor = 0;
  } else if (key == 'e' && e->mods & TERM_MOD_CTRL) {
    HtkTextMoveStart(c, e);
    c->cursor = StrLen(c->text);
  } else if (key == 'w' && e->mods & TERM_MOD_CTRL) {
    if (!HtkTextDeleteSelection(c)) {
      from = c->cursor;
      // Skip whitespace, then the preceding word.  Step by runes so UTF-8
      // text is never cut in the middle of a sequence.
      while (from > 0) {
        saved = c->cursor;
        c->cursor = from;
        step = HtkTextStepBack(c);
        c->cursor = saved;
        if (c->text[from - step] > ' ')
          break;
        from -= step;
      }
      while (from > 0) {
        saved = c->cursor;
        c->cursor = from;
        step = HtkTextStepBack(c);
        c->cursor = saved;
        if (c->text[from - step] <= ' ')
          break;
        from -= step;
      }
      HtkTextDelete(c, from, c->cursor - from);
      c->cursor = from;
    }
  } else if (key == TERM_KEY_LEFT) {
    HtkTextMoveStart(c, e);
    c->cursor -= HtkTextStepBack(c);
  } else if (key == TERM_KEY_RIGHT) {
    HtkTextMoveStart(c, e);
    c->cursor += HtkTextStepAhead(c);
  } else if (key == TERM_KEY_HOME) {
    HtkTextMoveStart(c, e);
    c->cursor = 0;
  } else if (key == TERM_KEY_END) {
    HtkTextMoveStart(c, e);
    c->cursor = StrLen(c->text);
  } else if (key == TERM_KEY_BACKSPACE) {
    if (!HtkTextDeleteSelection(c))
      HtkTextDelete(c, c->cursor - HtkTextStepBack(c), HtkTextStepBack(c));
  } else if (key == TERM_KEY_DELETE) {
    if (!HtkTextDeleteSelection(c))
      HtkTextDelete(c, c->cursor, HtkTextStepAhead(c));
  } else if (key == TERM_KEY_ENTER && c->submit)
    c->submit(c);
  else if (key >= ' ' && key < 0x110000 && !e->mods) {
    HtkTextDeleteSelection(c);  // typing replaces the selection
    HtkTextInsert(c, key);
  } else
    return FALSE;
  htk_dirty = TRUE;
  return TRUE;
}

// Multiline: lines separated by \n in one buffer.

HtkCtl *HtkMultilineNew(U8 *text)
{
  HtkCtl *c = HtkNew(HTK_MULTILINE);

  HtkSetText(c, text);
  c->focusable = TRUE;
  c->expand = TRUE;
  return c;
}

U0 HtkMultilineSetOptions(HtkCtl *c, I64 options)
{
  if (!c || c->kind != HTK_MULTILINE)
    return;
  c->line_numbers = options & HTK_MULTILINE_LINE_NUMBERS;
  c->wrap = options & HTK_MULTILINE_WRAP;
  c->scrollbar = options & HTK_MULTILINE_SCROLLBAR;
  htk_dirty = TRUE;
}

U0 HtkMultilineMeasure(HtkCtl *c)
{
  c->pw = 24;
  c->ph = 5;
}

I64 HtkLineStart(U8 *text, I64 at)
{
  while (at > 0 && text[at - 1] != '\n')
    at--;
  return at;
}

U0 HtkMultilineDraw(HtkCtl *c)
{
  I64 i = 0, row = 0, col = 0, x, y, line = 1, lines = 1;
  I64 crow = 0, ccol = 0, total = 1, width, gutter = 0, digits = 1;
  I64 sel_from = -1, sel_to = -1;
  Bool continuation = FALSE;
  U8 number[16];

  HtkTextSelected(c, &sel_from, &sel_to);
  for (i = 0; c->text[i]; i++)
    if (c->text[i] == '\n')
      lines++;
  while (lines >= 10) {
    digits++;
    lines /= 10;
  }
  if (c->line_numbers)
    gutter = digits + 1;
  width = c->w - gutter - c->scrollbar;
  if (width < 1)
    width = 1;

  // Locate cursor and total visual rows, including soft wraps.
  i = 0;
  while (i < c->cursor && c->text[i]) {
    if (c->text[i] == '\n') {
      crow++;
      ccol = 0;
      i++;
    } else {
      TermRuneNext(c->text, &i);
      ccol++;
      if (c->wrap && ccol >= width) {
        crow++;
        ccol = 0;
      }
    }
  }
  i = 0;
  col = 0;
  while (c->text[i]) {
    if (c->text[i] == '\n') {
      total++;
      col = 0;
      i++;
    } else {
      TermRuneNext(c->text, &i);
      col++;
      if (c->wrap && col >= width) {
        total++;
        col = 0;
      }
    }
  }
  if (!c->scroll_hold)
    HtkScrollIntoView(c, crow, c->h);
  HtkRect(c->x, c->y, c->w, c->h, ' ', HTK_C_FIELD_FG, HTK_C_FIELD_BG);
  i = 0;
  row = 0;
  col = 0;
  x = c->x;
  y = c->y;
  continuation = FALSE;
  while (TRUE) {
    if (row >= c->top && row < c->top + c->h && col == 0 && c->line_numbers &&
      !continuation) {
      StrPrint(number, "%d", line);
      HtkStr(c->x + digits - StrLen(number), c->y + row - c->top, number,
        HTK_C_DIM, HTK_C_FIELD_BG);
    }
    if (!c->text[i])
      break;
    if (c->text[i] == '\n') {
      row++;
      line++;
      col = 0;
      x = c->x;
      continuation = FALSE;
      i++;
    } else {
      Bool selected = i >= sel_from && i < sel_to;
      I64 rune = TermRuneNext(c->text, &i);
      if (row >= c->top && row < c->top + c->h && col < width) {
        if (selected)
          HtkChr(c->x + gutter + col, c->y + row - c->top, rune,
            HTK_C_SEL_FG, HTK_C_SEL_BG);
        else
          HtkChr(c->x + gutter + col, c->y + row - c->top, rune,
            HtkInk(c, HTK_C_FIELD_FG), HTK_C_FIELD_BG);
      }
      x++;
      col++;
      if (c->wrap && col >= width) {
        row++;
        col = 0;
        continuation = TRUE;
      }
    }
    if (c->text[i] && row - c->top >= c->h)
      break;
  }
  if (c->scrollbar && total > c->h) {
    I64 span = total - c->h;
    I64 thumb_h = c->h * c->h / total;
    I64 thumb;
    if (thumb_h < 1)
      thumb_h = 1;
    // Map 0..span onto 0..(height-thumb), so the last row is exactly flush
    // with the bottom regardless of integer rounding.
    thumb = c->top * (c->h - thumb_h) / span;
    for (i = 0; i < thumb_h; i++)
      HtkChr(c->x + c->w - 1, c->y + thumb + i, HTK_R_BLOCK,
        HTK_C_DIM, HTK_C_FIELD_BG);
  }
  c->high = total;  // visual row count, used for scrollbar mouse dragging
  if (HtkFocused(c) && !c->disabled && crow >= c->top &&
    crow < c->top + c->h) {
    x = c->x + gutter + ccol;
    if (x > c->x + gutter + width - 1)
      x = c->x + gutter + width - 1;
    TermGotoXY(x, c->y + crow - c->top);
    TermShowCursor(TRUE);
  }
}

U0 HtkMultilineScrollMouse(HtkCtl *c, I64 y)
{
  I64 span = c->high - c->h, at = y - c->y;

  if (span < 1 || c->h < 2)
    return;
  if (at < 0)
    at = 0;
  if (at >= c->h)
    at = c->h - 1;
  c->top = at * span / (c->h - 1);
  c->scroll_hold = TRUE;
  htk_dirty = TRUE;
}

Bool HtkMultilineKey(HtkCtl *c, CTermEvent *e)
{
  I64 key = e->key;
  I64 start, up;

  c->scroll_hold = FALSE;

  if (key == TERM_KEY_ENTER) {
    HtkTextDeleteSelection(c);
    HtkTextInsert(c, '\n');
  } else if (key == TERM_KEY_UP || key == 'p' && e->mods & TERM_MOD_CTRL) {
    HtkTextMoveStart(c, e);
    start = HtkLineStart(c->text, c->cursor);
    if (!start)
      return TRUE;
    up = HtkLineStart(c->text, start - 1);
    c->cursor = up;
    while (c->cursor < start - 1 && c->cursor - up < c->cursor)
      c->cursor++;
    if (c->cursor > start - 1)
      c->cursor = start - 1;
  } else if (key == TERM_KEY_DOWN || key == 'n' && e->mods & TERM_MOD_CTRL) {
    HtkTextMoveStart(c, e);
    start = c->cursor;
    while (c->text[start] && c->text[start] != '\n')
      start++;
    if (c->text[start])
      c->cursor = start + 1;
  } else
    return HtkEntryKey(c, e);
  htk_dirty = TRUE;
  return TRUE;
}
