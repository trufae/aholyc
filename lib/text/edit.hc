#ifndef AHOLYC_LIB_TEXT_EDIT_HC
#define AHOLYC_LIB_TEXT_EDIT_HC

#include "strbuf.hc"
#include "utf8.HC"

// Byte-indexed UTF-8 editing. All document/clipboard inputs are bounded slices.
class CEditChange
{
  CEditChange *next;
  CStrBuf before, after;
  I64 at, cursor, anchor, revision;
};

class CEdit
{
  CStrBuf text;
  CEditChange *undo;
  CEditChange *redo;
  I64 cursor, anchor, revision, serial, saved;
  Bool readonly, typing;
};

U0 EditChangesFree(CEditChange *change)
{
  CEditChange *next;

  while (change) {
    next = change->next;
    StrBufFini(&change->before);
    StrBufFini(&change->after);
    Free(change);
    change = next;
  }
}

U0 EditInit(CEdit *edit)
{
  MemSet(edit, 0, sizeof(CEdit));
  StrBufInit(&edit->text);
  edit->anchor = -1;
}

U0 EditFini(CEdit *edit)
{
  EditChangesFree(edit->undo);
  EditChangesFree(edit->redo);
  StrBufFini(&edit->text);
}

Bool EditBoundary(CEdit *edit, I64 at)
{
  return at >= 0 && at <= StrsLen(&edit->text) &&
    (at == StrsLen(&edit->text) || (edit->text.a[at] & 0xC0) != 0x80);
}

I64 EditNext(CEdit *edit, I64 at, I64 direction)
{
  I64 length = StrsLen(&edit->text), rune, n;

  if (direction < 0) {
    if (at > 0)
      at--;
    while (at > 0 && (edit->text.a[at] & 0xC0) == 0x80)
      at--;
  } else if (at < length) {
    n = Utf8DecodeRune(edit->text.a + at, length - at, &rune);
    at += MaxI64(1, n);
  }
  return at;
}

U0 EditSelection(CEdit *edit, I64 *a, I64 *b)
{
  *a = edit->cursor;
  *b = edit->cursor;
  if (edit->anchor >= 0) {
    *a = MinI64(edit->anchor, edit->cursor);
    *b = MaxI64(edit->anchor, edit->cursor);
  }
}

// Internal splice: insert must not alias edit->text. History owns that copy.
U0 EditSplice(CEdit *edit, I64 a, I64 b, CStrs *insert)
{
  I64 length = StrsLen(&edit->text), n = StrsLen(insert), delta = n - (b - a);
  I64 i;

  if (delta > 0) {
    StrBufReserve(&edit->text, delta);
    for (i = length; i > b; i--)
      edit->text.a[i - 1 + delta] = edit->text.a[i - 1];
  } else {
    for (i = b; i < length; i++)
      edit->text.a[i + delta] = edit->text.a[i];
  }
  MemCpy(edit->text.a + a, insert->a, n);
  edit->text.b = edit->text.a + length + delta;
  *edit->text.b = 0; // CStrBuf interop only; never used to find the document end.
  edit->cursor = a + n;
  edit->anchor = -1;
}

Bool EditReplace(CEdit *edit, I64 a, I64 b, CStrs *insert)
{
  CEditChange *change, *tail;
  I64 n = 1;

  if (edit->readonly || a > b || !EditBoundary(edit, a) ||
    !EditBoundary(edit, b) || !StrsValid(insert))
    return FALSE;
  if (b - a == StrsLen(insert) && !MemCmp(edit->text.a + a, insert->a, b - a))
    return FALSE;
  edit->typing = FALSE;
  change = CAlloc(sizeof(CEditChange));
  StrBufInit(&change->before);
  StrBufInit(&change->after);
  StrBufPutN(&change->before, edit->text.a + a, b - a);
  StrBufPutStrs(&change->after, insert);
  change->at = a;
  change->cursor = edit->cursor;
  change->anchor = edit->anchor;
  change->revision = edit->revision;
  EditSplice(edit, a, b, &change->after);
  edit->revision = ++edit->serial;
  change->next = edit->undo;
  edit->undo = change;
  EditChangesFree(edit->redo);
  edit->redo = NULL;
  // Keep at most 128 edit deltas, rather than copies of whole documents.
  tail = change;
  while (tail->next && n++ < 128)
    tail = tail->next;
  EditChangesFree(tail->next);
  tail->next = NULL;
  return TRUE;
}

Bool EditInsert(CEdit *edit, CStrs *text)
{
  I64 a, b;

  EditSelection(edit, &a, &b);
  return EditReplace(edit, a, b, text);
}

// Coalesce adjacent typing until a space, navigation, command or save boundary.
Bool EditType(CEdit *edit, CStrs *text)
{
  Bool join = edit->typing && edit->anchor < 0 && edit->revision != edit->saved;
  CEditChange *change, *previous;

  if (!EditInsert(edit, text)) return FALSE;
  change = edit->undo;
  previous = change->next;
  if (join && previous && StrsEmpty(&change->before) && StrsEmpty(&previous->before) &&
    change->at == previous->at + StrsLen(&previous->after)) {
      StrBufPutStrs(&previous->after, &change->after);
      edit->undo = previous;
      change->next = NULL;
      EditChangesFree(change);
    }
  edit->typing = StrsLen(text) && text->b[-1] > ' ';
  return TRUE;
}

Bool EditUndo(CEdit *edit, Bool redo=FALSE)
{
  CEditChange **from = &edit->undo, **to = &edit->redo, *change;
  CStrBuf *remove, *insert;
  I64 cursor = edit->cursor, anchor = edit->anchor, revision = edit->revision;

  if (edit->readonly)
    return FALSE;
  if (redo) {
    from = &edit->redo;
    to = &edit->undo;
  }
  edit->typing = FALSE;
  change = *from;
  if (!change)
    return FALSE;
  remove = &change->after;
  insert = &change->before;
  if (redo) {
    remove = &change->before;
    insert = &change->after;
  }
  EditSplice(edit, change->at, change->at + StrsLen(remove), insert);
  edit->cursor = change->cursor;
  edit->anchor = change->anchor;
  edit->revision = change->revision;
  change->cursor = cursor;
  change->anchor = anchor;
  change->revision = revision;
  *from = change->next;
  change->next = *to;
  *to = change;
  return TRUE;
}

Bool EditWrapped(CEdit *edit, CStrs *prefix, CStrs *suffix)
{
  I64 a, b, plen = StrsLen(prefix), slen = StrsLen(suffix);

  EditSelection(edit, &a, &b);
  Bool toggle = a >= plen && StrsLen(&edit->text) - b >= slen &&
    !MemCmp(edit->text.a + a - plen, prefix->a, plen) &&
    !MemCmp(edit->text.a + b, suffix->a, slen);
  if (toggle && plen == 1 && slen == 1 && *prefix->a == *suffix->a &&
    (*prefix->a == '*' || *prefix->a == '_')) {
      I64 left = a, right = b;
      while (left > 0 && edit->text.a[left - 1] == *prefix->a) left--;
      while (right < StrsLen(&edit->text) && edit->text.a[right] == *suffix->a) right++;
      toggle = ((a - left) & 1) && ((right - b) & 1);
    }
  return toggle;
}

Bool EditWrap(CEdit *edit, CStrs *prefix, CStrs *suffix)
{
  CStrBuf out;
  I64 a, b, start, plen = StrsLen(prefix), slen = StrsLen(suffix);
  Bool toggle = EditWrapped(edit, prefix, suffix), changed;

  EditSelection(edit, &a, &b);
  StrBufInit(&out);
  if (!toggle)
    StrBufPutStrs(&out, prefix);
  StrBufPutN(&out, edit->text.a + a, b - a);
  if (!toggle)
    StrBufPutStrs(&out, suffix);
  start = a + plen;
  if (toggle)
    start = a - plen;
  if (toggle)
    changed = EditReplace(edit, a - plen, b + slen, &out);
  else
    changed = EditReplace(edit, a, b, &out);
  if (changed) {
    edit->anchor = start;
    edit->cursor = start + b - a;
  }
  StrBufFini(&out);
  return changed;
}

#endif
