// Shared Vim input for textarea controls. Editors supply their CEdit model;
// ordinary HTK multiline controls temporarily lend their sole text buffer.
#ifndef AHOLYC_LIB_HTK_VIM_HC
#define AHOLYC_LIB_HTK_VIM_HC
#ifdef UI_HTK_VIMODE

U0 HtkVimMode(HtkCtl *c, Bool enabled)
{
  if (!c || !c->vim_editor || c->vim_mode == enabled) return;
  c->vim_mode = enabled;
  c->vim_insert = FALSE;
  c->vim_pending = 0;
  c->vim_vertical = FALSE;
  c->vim_kill = FALSE;
  if (c->text_edit) c->text_edit->typing = FALSE;
  if (c->vim_visual && c->kind == HTK_MULTILINE) {
    c->cursor = c->vim_head; c->anchor = -1;
  }
  htk_dirty = TRUE;
  if (c->vim_changed) c->vim_changed(c);
  c->vim_visual = 0;
}

I64 HtkVimCaret(HtkCtl *c, I64 fallback)
{
  if (c->vim_visual) return c->vim_head;
  return fallback;
}

U0 HtkVimCancel(HtkCtl *c, CEdit *edit)
{
  if (c->vim_visual) edit->cursor = c->vim_head;
  c->vim_visual = 0; c->vim_pending = 0; c->vim_kill = FALSE;
  edit->anchor = -1; edit->typing = FALSE;
  c->vim_at = edit->cursor;
}

U0 HtkVimTree(HtkCtl *c, Bool enabled)
{
  HtkCtl *kid;

  HtkVimMode(c, enabled);
  kid = c->kids;
  while (kid) { HtkVimTree(kid, enabled); kid = kid->sib; }
}

U0 HtkVimSet(Bool enabled)
{
  HtkCtl *window = htk_windows;

  htk_vim_mode = enabled;
  while (window) { HtkVimTree(window, enabled); window = window->sib; }
}

I64 HtkVimLine(CEdit *edit, I64 at, Bool end=FALSE)
{
  if (end) {
    while (at < StrsLen(&edit->text) && edit->text.a[at] != '\n') at++;
  } else {
    while (at > 0 && edit->text.a[at - 1] != '\n') at--;
  }
  return at;
}

I64 HtkVimFirst(CEdit *edit, I64 at)
{
  at = HtkVimLine(edit, at);
  while (at < StrsLen(&edit->text) &&
    (edit->text.a[at] == ' ' || edit->text.a[at] == '\t')) at++;
  return at;
}

// Normal-mode cursors sit on a character, except on an empty line.
I64 HtkVimPosition(CEdit *edit, I64 at)
{
  I64 start = HtkVimLine(edit, at), end = HtkVimLine(edit, at, TRUE);

  if (at == end && end > start) return EditNext(edit, end, -1);
  return at;
}

// Vim includes the character under its caret. CEdit uses an exclusive end.
// Keep the logical caret separate so reversing a selection never moves it
// onto the next line or splits a UTF-8 character.
U0 HtkVimVisualSelect(HtkCtl *c, CEdit *edit)
{
  I64 a, b, length = StrsLen(&edit->text);

  c->vim_start = MaxI64(0, MinI64(length, c->vim_start));
  c->vim_head = MaxI64(0, MinI64(length, c->vim_head));
  while (!EditBoundary(edit, c->vim_start)) c->vim_start--;
  while (!EditBoundary(edit, c->vim_head)) c->vim_head--;
  a = MinI64(c->vim_start, c->vim_head); b = MaxI64(c->vim_start, c->vim_head);
  if (c->vim_visual == 2) {
    a = HtkVimLine(edit, a); b = HtkVimLine(edit, b, TRUE);
    if (b < length) b++;
  } else b = EditNext(edit, b, 1);
  edit->anchor = a; edit->cursor = b;
  if (c->vim_head < c->vim_start) { edit->anchor = b; edit->cursor = a; }
  edit->typing = FALSE; c->vim_at = c->vim_head;
}

I64 HtkVimClass(CEdit *edit, I64 at, Bool big=FALSE)
{
  I64 rune = 0;

  Utf8DecodeRune(edit->text.a + at, StrsLen(&edit->text) - at, &rune);
  if (EditSpace(rune)) return 0;
  if (big || rune >= 'a' && rune <= 'z' || rune >= 'A' && rune <= 'Z' ||
    rune >= '0' && rune <= '9' || rune == '_') return 1;
  // Keep non-ASCII text together, but separate common punctuation and symbols.
  if (rune >= 0x80 && !(rune >= 0x2000 && rune <= 0x206F ||
      rune >= 0x2190 && rune <= 0x2BFF || rune >= 0x1F000 && rune <= 0x1FAFF)) return 1;
  return 2;
}

I64 HtkVimWordEnd(CEdit *edit, I64 at, Bool big=FALSE)
{
  I64 kind = HtkVimClass(edit, at, big), end = HtkVimLine(edit, at, TRUE);

  while (at < end && HtkVimClass(edit, at, big) == kind) at = EditNext(edit, at, 1);
  return at;
}

I64 HtkVimWord(CEdit *edit, I64 at, Bool back=FALSE, Bool big=FALSE)
{
  I64 kind, length = StrsLen(&edit->text);

  if (back) {
    at = EditNext(edit, at, -1);
    while (at > 0 && !HtkVimClass(edit, at, big)) {
      if (edit->text.a[at] == '\n' && HtkVimLine(edit, at) == at) return at;
      at = EditNext(edit, at, -1);
    }
    kind = HtkVimClass(edit, at, big);
    while (at > 0 && HtkVimClass(edit, EditNext(edit, at, -1), big) == kind)
      at = EditNext(edit, at, -1);
  } else {
    kind = HtkVimClass(edit, at, big);
    if (kind) at = HtkVimWordEnd(edit, at, big);
    else if (at < length && edit->text.a[at] == '\n') at++;
    while (at < length && !HtkVimClass(edit, at, big)) {
      if (edit->text.a[at] == '\n' && HtkVimLine(edit, at) == at) break;
      at = EditNext(edit, at, 1);
    }
  }
  return at;
}

I64 HtkVimColumn(CEdit *edit, I64 at, I64 column)
{
  I64 rune = 0;

  Utf8DecodeRune(edit->text.a + at, StrsLen(&edit->text) - at, &rune);
  if (rune == '\t') return column + 8 - column % 8;
  return column + Utf8CellWidth(rune);
}

Bool HtkVimMotion(HtkCtl *c, CEdit *edit, I64 key)
{
  I64 at = edit->cursor, start = HtkVimLine(edit, at), end, p, column = 0, next;

  if (key != TERM_KEY_UP && key != TERM_KEY_DOWN && key != TERM_KEY_LEFT &&
    key != TERM_KEY_RIGHT && key != TERM_KEY_HOME && key != TERM_KEY_END) return FALSE;
  edit->typing = FALSE; edit->anchor = -1;
  if (key == TERM_KEY_UP || key == TERM_KEY_DOWN) {
    if (!c->vim_vertical) {
      for (p = start; p < at; p = EditNext(edit, p, 1)) column = HtkVimColumn(edit, p, column);
      c->vim_column = column;
    }
    c->vim_vertical = TRUE;
    if (key == TERM_KEY_UP) {
      if (!start) return TRUE;
      at = HtkVimLine(edit, start - 1);
    } else {
      end = HtkVimLine(edit, at, TRUE);
      if (end == StrsLen(&edit->text)) return TRUE;
      at = end + 1;
    }
    end = HtkVimLine(edit, at, TRUE); column = 0;
    while (at < end && column < c->vim_column) {
      next = HtkVimColumn(edit, at, column);
      if (next > c->vim_column) break;
      column = next; at = EditNext(edit, at, 1);
    }
  } else if (key == TERM_KEY_LEFT || key == TERM_KEY_RIGHT) {
    if (c->vim_insert) at = EditNext(edit, at, 1 - 2 * (key == TERM_KEY_LEFT));
    else if (key == TERM_KEY_LEFT) at = MaxI64(start, EditNext(edit, at, -1));
    else if (at < HtkVimLine(edit, at, TRUE)) at = EditNext(edit, at, 1);
  } else if (key == TERM_KEY_HOME || key == TERM_KEY_END)
    at = HtkVimLine(edit, at, key == TERM_KEY_END);
  else return FALSE;
  if (!c->vim_insert) at = HtkVimPosition(edit, at);
  edit->cursor = at; edit->anchor = -1; edit->typing = FALSE;
  return TRUE;
}

Bool HtkVimJoin(CEdit *edit)
{
  I64 start = HtkVimLine(edit, edit->cursor), a = HtkVimLine(edit, start, TRUE), b;
  I64 spaces = 0, last;
  CStrs text;

  if (edit->readonly || a == StrsLen(&edit->text)) return FALSE;
  b = a + 1;
  while (b < StrsLen(&edit->text) && (edit->text.a[b] == ' ' || edit->text.a[b] == '\t')) b++;
  if (a > start && b < StrsLen(&edit->text) && edit->text.a[b] != '\n') {
    last = edit->text.a[a - 1];
    if (last != ' ' && last != '\t' && edit->text.a[b] != ')') {
      spaces = 1;
      if (last == '.' || last == '?' || last == '!') spaces = 2;
    }
  }
  StrsInitN(&text, "  ", spaces);
  if (!EditReplace(edit, a, b, &text)) return FALSE;
  edit->cursor = HtkVimPosition(edit, a);
  return TRUE;
}

Bool HtkVimPageKey(CTermEvent *e)
{
  return !e->mods && (e->key == TERM_KEY_PGUP || e->key == TERM_KEY_PGDN) ||
    e->mods == TERM_MOD_CTRL && (e->key == 'f' || e->key == 'b');
}

// Application menus must let these bindings reach the focused Vim editor.
Bool HtkVimControl(HtkCtl *c, CTermEvent *e)
{
  if (!c->vim_mode || e->mods != TERM_MOD_CTRL) return FALSE;
  if (e->key == 'f' || e->key == 'b') return TRUE;
  return c->vim_insert && (e->key == 'a' || e->key == 'e' || e->key == 'p' ||
    e->key == 'n' || e->key == 'd' || e->key == 'h' || e->key == 'k' ||
    e->key == 'u' || e->key == 'w' || e->key == 'y' || e->key == 't');
}

// Match the multiline control's soft-wrap grid, including its gutter.
U0 HtkVimWrappedPage(HtkCtl *c, CEdit *edit, I64 direction)
{
  I64 i, lines = 1, width = c->w - c->scrollbar, digits = 1;
  I64 row = 0, col = 0, x = 0, y = 0, target, distance = I64_MAX;
  I64 step = MaxI64(1, c->h - 2), length = StrsLen(&edit->text);

  for (i = 0; i < length; i++) if (edit->text.a[i] == '\n') lines++;
  while (lines >= 10) { lines /= 10; digits++; }
  if (c->line_numbers) width -= digits + 1;
  width = MaxI64(1, width);
  for (i = 0; i <= length; i = EditNext(edit, i, 1)) {
    if (i == edit->cursor) { x = col; y = row; }
    if (i == length) break;
    if (edit->text.a[i] == '\n') { row++; col = 0; }
    else if (++col == width) { row++; col = 0; }
  }
  target = MaxI64(0, MinI64(row, y + direction * step));
  c->top = MaxI64(0, MinI64(MaxI64(0, row + 1 - MaxI64(1, c->h)), c->top + direction * step));
  row = 0; col = 0;
  for (i = 0; i <= length; i = EditNext(edit, i, 1)) {
    if (row == target && AbsI64(col - x) < distance) {
      distance = AbsI64(col - x); edit->cursor = i;
    }
    if (i == length) break;
    if (edit->text.a[i] == '\n') { row++; col = 0; }
    else if (++col == width) { row++; col = 0; }
  }
  c->vim_vertical = FALSE;
}

U0 HtkVimPage(HtkCtl *c, CEdit *edit, I64 direction)
{
  I64 i, rows = 1, step = MaxI64(1, c->h - 2), key = TERM_KEY_DOWN;

  edit->anchor = -1; edit->typing = FALSE; c->vim_pending = 0;
  if (c->vim_page) c->vim_page(c, edit, direction);
  else if (c->wrap) HtkVimWrappedPage(c, edit, direction);
  else {
    if (direction < 0) key = TERM_KEY_UP;
    for (i = 0; i < step; i++) HtkVimMotion(c, edit, key);
    for (i = 0; i < StrsLen(&edit->text); i++) if (edit->text.a[i] == '\n') rows++;
    c->top = MaxI64(0, MinI64(MaxI64(0, rows - MaxI64(1, c->h)), c->top + direction * step));
  }
  if (!c->vim_insert) edit->cursor = HtkVimPosition(edit, edit->cursor);
  c->vim_at = edit->cursor;
}

Bool HtkVimInsertControl(HtkCtl *c, CEdit *edit, CTermEvent *e)
{
  I64 key = e->key, a, b, at = edit->cursor, start = HtkVimLine(edit, at);
  Bool back = key == 'u' || key == 'w';
  CStrs text, clipboard;
  CStrBuf copy;
  CTermEvent deletion;

  if (!c->vim_insert || !HtkVimControl(c, e)) return FALSE;
  if (key == 'a' || key == 'e' || key == 'p' || key == 'n') {
    if (key == 'a') key = TERM_KEY_HOME;
    else if (key == 'e') key = TERM_KEY_END;
    else if (key == 'p') key = TERM_KEY_UP;
    else key = TERM_KEY_DOWN;
    HtkVimMotion(c, edit, key);
    return TRUE;
  }
  if (edit->readonly) { c->vim_kill = FALSE; edit->typing = FALSE; return TRUE; }
  if (key == 'd' || key == 'h') {
    deletion = *e; deletion.mods = 0;
    deletion.key = TERM_KEY_DELETE;
    if (key == 'h') deletion.key = TERM_KEY_BACKSPACE;
    return HtkVimKey(c, edit, &deletion);
  }
  edit->typing = FALSE;
  if (key == 'y') {
    HtkClipboardGet(&text); EditInsert(edit, &text);
    return TRUE;
  }
  if (key == 't') {
    // At EOL transpose the last two characters; never transpose a newline.
    if (at == HtkVimLine(edit, at, TRUE)) at = EditNext(edit, at, -1);
    if (at <= start || edit->anchor >= 0 && edit->anchor != edit->cursor) return TRUE;
    a = EditNext(edit, at, -1); b = EditNext(edit, at, 1);
    StrBufInit(&copy);
    StrBufPutN(&copy, edit->text.a + at, b - at);
    StrBufPutN(&copy, edit->text.a + a, at - a);
    EditReplace(edit, a, b, &copy); StrBufFini(&copy);
    return TRUE;
  }
  if (key != 'k' && !back) return FALSE;
  EditSelection(edit, &a, &b);
  if (a == b) {
    if (key == 'k') {
      b = HtkVimLine(edit, at, TRUE);
      if (b == a && b < StrsLen(&edit->text)) b++;
    } else if (key == 'u') a = start;
    else a = HtkVimWord(edit, at, TRUE);
  }
  if (a == b) return TRUE;
  StrBufInit(&copy); HtkClipboardGet(&clipboard);
  if (c->vim_kill && !back) StrBufPutStrs(&copy, &clipboard);
  StrBufPutN(&copy, edit->text.a + a, b - a);
  if (c->vim_kill && back) StrBufPutStrs(&copy, &clipboard);
  StrsInitN(&text, "", 0);
  if (EditReplace(edit, a, b, &text)) {
    HtkClipboardSetStrs(&copy); c->vim_kill = TRUE;
  }
  StrBufFini(&copy);
  return TRUE;
}

Bool HtkVimKey(HtkCtl *c, CEdit *edit, CTermEvent *e)
{
  I64 key = e->key, at = edit->cursor, original = at, a, b, n, length = StrsLen(&edit->text);
  I64 pending = c->vim_pending;
  Bool move = FALSE, ctrl = e->mods & TERM_MOD_CTRL, join;
  CStrs text;
  CStrBuf line;
  U8 bytes[4];

  if (!c->vim_mode) return FALSE;
  if (c->vim_visual) return HtkVimVisualKey(c, edit, e);
  if (at != c->vim_at) { c->vim_vertical = FALSE; c->vim_kill = FALSE; edit->typing = FALSE; }
  if (!c->vim_insert || e->mods != TERM_MOD_CTRL || key != 'k' && key != 'u' && key != 'w')
    c->vim_kill = FALSE;
  if (key != 'j' && key != 'k' && key != TERM_KEY_UP && key != TERM_KEY_DOWN &&
    !HtkVimPageKey(e) && !(c->vim_insert && ctrl && (key == 'p' || key == 'n')))
    c->vim_vertical = FALSE;
  if (HtkVimPageKey(e)) {
    HtkVimPage(c, edit, 1 - 2 * (key == 'b' || key == TERM_KEY_PGUP));
    return TRUE;
  }
  if (key == TERM_KEY_ESCAPE) {
    if (c->vim_insert && at > HtkVimLine(edit, at)) edit->cursor = EditNext(edit, at, -1);
    c->vim_insert = FALSE;
    c->vim_pending = 0;
    edit->anchor = -1;
    edit->typing = FALSE;
    c->vim_at = edit->cursor;
    return TRUE;
  }
  if (e->mods & TERM_MOD_ALT) { c->vim_pending = 0; return FALSE; }
  if (ctrl) {
    c->vim_pending = 0;
    if (HtkVimInsertControl(c, edit, e)) {
      c->vim_at = edit->cursor; return TRUE;
    } else if (key == 'r' || key == 'y' || key == 'z') {
      EditUndo(edit, key != 'z' || e->mods & TERM_MOD_SHIFT);
    } else if (key == 'v') { HtkClipboardGet(&text); EditInsert(edit, &text); }
    else return FALSE;
    if (!c->vim_insert) edit->cursor = HtkVimPosition(edit, edit->cursor);
    c->vim_at = edit->cursor;
    return TRUE;
  }
  if (c->vim_insert) {
    if (e->mods & TERM_MOD_SHIFT && key >= TERM_KEY_UP) { edit->typing = FALSE; return FALSE; }
    if (HtkVimMotion(c, edit, key)) { c->vim_at = edit->cursor; return TRUE; }
    if (key == TERM_KEY_DELETE || key == TERM_KEY_BACKSPACE) {
      join = edit->typing && edit->anchor < 0 && edit->revision != edit->saved;
      EditSelection(edit, &a, &b);
      if (a == b) {
        if (key == TERM_KEY_DELETE) b = EditNext(edit, b, 1);
        else a = EditNext(edit, a, -1);
      }
      StrsInitN(&text, "", 0);
      if (EditReplace(edit, a, b, &text)) {
        if (join) EditGroup(edit);
        edit->typing = TRUE;
      }
    } else if (key == TERM_KEY_ENTER || key >= ' ' && key < 0x110000) {
      if (key == TERM_KEY_ENTER) key = '\n';
      n = Utf8EncodeRune(key, bytes);
      StrsInitN(&text, bytes, n);
      edit->typing = EditType(edit, &text);
    } else { edit->typing = FALSE; return FALSE; }
    c->vim_at = edit->cursor;
    return TRUE;
  }
  edit->typing = FALSE;
  c->vim_pending = 0;
  if (pending) {
    if (pending == 'g' && key == 'g') { at = HtkVimFirst(edit, 0); move = TRUE; }
    else if ((pending == 'd' || pending == 'y') && key == pending) {
      if (pending == 'd' && edit->readonly) return TRUE;
      a = HtkVimLine(edit, at); b = HtkVimLine(edit, at, TRUE);
      if (b < length) b++;
      StrBufInit(&line);
      StrBufPutN(&line, edit->text.a + a, b - a);
      if (!StrsLen(&line) || line.b[-1] != '\n') StrBufPutC(&line, '\n');
      HtkClipboardSetStrs(&line);
      htk_clipboard_lines = TRUE;
      StrBufFini(&line);
      if (pending == 'd') {
        // The last unterminated line owns its preceding separator.
        if (b == length && a > 0 && (b == a || edit->text.a[b - 1] != '\n')) a--;
        StrsInitN(&text, "", 0);
        EditReplace(edit, a, b, &text);
        edit->cursor = HtkVimFirst(edit, edit->cursor);
      }
    } else if ((pending == 'd' || pending == 'c') && (key == 'w' || key == 'W')) {
      if (edit->readonly) return TRUE;
      if (pending == 'c' && HtkVimClass(edit, at)) b = HtkVimWordEnd(edit, at, key == 'W');
      else b = MinI64(HtkVimWord(edit, at, FALSE, key == 'W'), HtkVimLine(edit, at, TRUE));
      StrsInitN(&text, edit->text.a + at, b - at);
      HtkClipboardSetStrs(&text);
      StrsInitN(&text, "", 0);
      join = EditReplace(edit, at, b, &text);
      if (pending == 'c') { c->vim_insert = TRUE; edit->typing = join; }
    }
  } else if (key == 'g' || key == 'd' || key == 'y' || key == 'c') c->vim_pending = key;
  else if (key == 'i' || key == 'a' || key == 'I' || key == 'A' || key == 'o' || key == 'O') {
    if (edit->readonly) return TRUE;
    if (key == 'a' && at < length && edit->text.a[at] != '\n') at = EditNext(edit, at, 1);
    if (key == 'I' || key == 'O') at = HtkVimLine(edit, at);
    if (key == 'I') at = HtkVimFirst(edit, at);
    if (key == 'A' || key == 'o') at = HtkVimLine(edit, at, TRUE);
    edit->cursor = at; edit->anchor = -1;
    if (key == 'o' || key == 'O') {
      StrsInitS(&text, "\n");
      if (key == 'o' && at < length) at++;
      EditReplace(edit, at, at, &text);
      edit->undo->cursor = original;
      if (key == 'O' || at < length) edit->cursor = at;
      edit->typing = TRUE;
    }
    c->vim_insert = TRUE;
  } else if (key == 'v' || key == 'V') {
    c->vim_visual = 1 + (key == 'V');
    c->vim_start = c->vim_head = HtkVimPosition(edit, at);
    HtkVimVisualSelect(c, edit); return TRUE;
  } else if (key == 'h' || key == 'l' || key == TERM_KEY_BACKSPACE) {
    a = TERM_KEY_LEFT;
    if (key == 'l') a = TERM_KEY_RIGHT;
    HtkVimMotion(c, edit, a);
  } else if (key == 'j' || key == 'k') {
    a = TERM_KEY_UP;
    if (key == 'j') a = TERM_KEY_DOWN;
    HtkVimMotion(c, edit, a);
  }
  else if (key == TERM_KEY_ENTER) {
    b = HtkVimLine(edit, at, TRUE);
    if (b < length) at = HtkVimFirst(edit, b + 1);
    move = TRUE;
  } else if (key == 'w' || key == 'b' || key == 'W' || key == 'B') {
    at = HtkVimWord(edit, at, key == 'b' || key == 'B', key == 'W' || key == 'B'); move = TRUE;
  }
  else if (key == '0' || key == '$') {
    at = HtkVimLine(edit, at, key == '$'); move = TRUE;
    if (key == '$') { c->vim_column = I64_MAX; c->vim_vertical = TRUE; }
  }
  else if (key == '^') { at = HtkVimFirst(edit, at); move = TRUE; }
  else if (key == 'G') { at = HtkVimFirst(edit, length); move = TRUE; }
  else if (key == 'J') HtkVimJoin(edit);
  else if (key == 'u') EditUndo(edit);
  else if (key == 'x' || key == TERM_KEY_DELETE) {
    EditSelection(edit, &a, &b);
    if (a == b && a < length && edit->text.a[a] != '\n') b = EditNext(edit, b, 1);
    StrsInitN(&text, edit->text.a + a, b - a);
    if (a != b && !edit->readonly) HtkClipboardSetStrs(&text);
    StrsInitN(&text, "", 0);
    EditReplace(edit, a, b, &text);
  } else if (key == 'p' || key == 'P') {
    if (edit->readonly) return TRUE;
    HtkClipboardGet(&text);
    if (htk_clipboard_lines) {
      if (key == 'P') at = HtkVimLine(edit, at);
      else { at = HtkVimLine(edit, at, TRUE); if (at < length) at++; }
      StrBufInit(&line);
      if (key == 'p' && at == length && at > 0 && edit->text.a[at - 1] != '\n') StrBufPutC(&line, '\n');
      a = at + StrsLen(&line);
      StrBufPutStrs(&line, &text);
      EditReplace(edit, at, at, &line);
      StrBufFini(&line);
      edit->cursor = HtkVimFirst(edit, a);
    } else {
      if (key == 'p' && at < length && edit->text.a[at] != '\n') at = EditNext(edit, at, 1);
      EditReplace(edit, at, at, &text);
      if (StrsLen(&text)) edit->cursor = EditNext(edit, edit->cursor, -1);
    }
  } else if (e->mods & TERM_MOD_SHIFT && key >= TERM_KEY_UP) return FALSE;
  else if (HtkVimMotion(c, edit, key)) {}
  else if (key >= TERM_KEY_UP) return FALSE;
  // Unrecognized printable normal-mode keys are consumed, never inserted.
  if (move) { edit->cursor = at; edit->anchor = -1; }
  if (!c->vim_insert) edit->cursor = HtkVimPosition(edit, edit->cursor);
  c->vim_at = edit->cursor;
  return TRUE;
}

Bool HtkVimVisualKey(HtkCtl *c, CEdit *edit, CTermEvent *e)
{
  I64 key = e->key, kind = c->vim_visual, a, b, at, length = StrsLen(&edit->text);
  Bool motion, changed;
  CStrs text;
  CStrBuf copy, yank;

  HtkVimVisualSelect(c, edit);
  if (key == TERM_KEY_ESCAPE) { HtkVimCancel(c, edit); return TRUE; }
  if (e->mods & TERM_MOD_ALT) return FALSE;
  if (e->mods & TERM_MOD_CTRL && !HtkVimPageKey(e)) {
    if (key == 'c') key = 'y';
    else if (key == 'x') key = 'd';
    else if (key == 'v') key = 'p';
    else {
      HtkVimCancel(c, edit);
      return HtkVimKey(c, edit, e);
    }
  }
  if (key == 'v' || key == 'V') {
    if (kind == 1 + (key == 'V')) HtkVimCancel(c, edit);
    else { c->vim_visual = 1 + (key == 'V'); HtkVimVisualSelect(c, edit); }
    return TRUE;
  }
  if (key == 'o') {
    at = c->vim_head; c->vim_head = c->vim_start; c->vim_start = at;
    c->vim_pending = 0; c->vim_vertical = FALSE;
    HtkVimVisualSelect(c, edit); return TRUE;
  }
  motion = key == 'h' || key == 'j' || key == 'k' || key == 'l' ||
    key == 'w' || key == 'b' || key == 'W' || key == 'B' || key == '0' ||
    key == '^' || key == '$' || key == 'g' || key == 'G' ||
    key == TERM_KEY_UP || key == TERM_KEY_DOWN || key == TERM_KEY_LEFT ||
    key == TERM_KEY_RIGHT || key == TERM_KEY_HOME || key == TERM_KEY_END ||
    key == TERM_KEY_ENTER || key == TERM_KEY_BACKSPACE || HtkVimPageKey(e);
  if (motion) {
    c->vim_visual = 0; edit->cursor = c->vim_head; edit->anchor = -1;
    c->vim_at = edit->cursor;
    HtkVimKey(c, edit, e);
    c->vim_head = edit->cursor; c->vim_visual = kind;
    HtkVimVisualSelect(c, edit); return TRUE;
  }
  c->vim_pending = 0;
  if (key != 'y' && key != 'd' && key != 'x' && key != 'c' && key != 'p' &&
    key != 'P' && key != TERM_KEY_DELETE) return TRUE;
  if (key != 'y' && edit->readonly) return TRUE;
  EditSelection(edit, &a, &b);
  StrBufInit(&copy);
  if (key == 'p' || key == 'P') {
    HtkClipboardGet(&text); StrBufPutStrs(&copy, &text);
  }
  StrBufInit(&yank); StrBufPutN(&yank, edit->text.a + a, b - a);
  if (kind == 2 && (!StrsLen(&yank) || yank.b[-1] != '\n')) StrBufPutC(&yank, '\n');
  HtkClipboardSetStrs(&yank); htk_clipboard_lines = kind == 2;
  StrBufFini(&yank);
  HtkVimCancel(c, edit);
  edit->cursor = a;
  if (key == 'y') {
    if (kind == 2) edit->cursor = HtkVimFirst(edit, a);
  } else {
    if (key == 'p' || key == 'P') StrsInitN(&text, copy.a, StrsLen(&copy));
    else if (key == 'c' && kind == 2 && b > a && edit->text.a[b - 1] == '\n') StrsInitS(&text, "\n");
    else {
      // Deleting the final unterminated line also removes its separator.
      if (kind == 2 && key != 'c' && b == length && a > 0 &&
        (a == b || edit->text.a[b - 1] != '\n')) a--;
      StrsInitN(&text, "", 0);
    }
    changed = EditReplace(edit, a, b, &text);
    edit->cursor = a;
    if (key == 'c') { c->vim_insert = TRUE; edit->typing = changed; }
    else if (kind == 2) edit->cursor = HtkVimFirst(edit, a);
  }
  if (!c->vim_insert) edit->cursor = HtkVimPosition(edit, edit->cursor);
  c->vim_at = edit->cursor; c->vim_vertical = FALSE;
  StrBufFini(&copy); return TRUE;
}

Bool HtkTextVimKey(HtkCtl *c, CTermEvent *e)
{
  CEdit *edit;
  I64 revision;
  Bool handled;

  if (!c->vim_mode) return FALSE;
  if (!c->text_edit) { c->text_edit = CAlloc(sizeof(CEdit)); EditInit(c->text_edit); }
  edit = c->text_edit;
  if (c->text == htk_empty) c->text = StrNew("");
  edit->text.a = c->text;
  edit->text.b = c->text + StrLen(c->text);
  edit->text.capacity = StrLen(c->text) + 1;
  edit->cursor = c->cursor; edit->anchor = c->anchor; edit->readonly = c->readonly;
  revision = edit->revision;
  handled = HtkVimKey(c, edit, e);
  if (!handled) edit->typing = FALSE;
  c->text = StrBufTake(&edit->text);
  c->cursor = edit->cursor; c->anchor = edit->anchor;
  if (revision != edit->revision) HtkFire(c);
  if (handled) htk_dirty = TRUE;
  return handled;
}
#endif
#endif
