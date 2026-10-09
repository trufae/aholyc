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
  // Optional view observer. Called after each splice, including undo/redo;
  // observers may adjust their positions but must not edit the document.
  U0 (*spliced)(CEdit *edit, I64 a, I64 b, I64 size);
  I64 user;
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

// Unicode whitespace shared by word motions and source statistics.
Bool EditSpace(I64 rune)
{
  return rune <= ' ' || rune == 0x85 || rune == 0xA0 || rune == 0x1680 ||
    rune >= 0x2000 && rune <= 0x200A || rune == 0x2028 || rune == 0x2029 ||
    rune == 0x202F || rune == 0x205F || rune == 0x3000;
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
  if (edit->spliced) edit->spliced(edit, a, b, n);
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

Bool EditFind(CEdit *edit, CStrs *query)
{
  U8 *found;
  I64 size = StrsLen(query), length = StrsLen(&edit->text);

  if (size < 1) return FALSE;
  found = MemMem(edit->text.a + edit->cursor, length - edit->cursor, query->a, size);
  if (!found) found = MemMem(edit->text.a, length, query->a, size);
  if (!found) return FALSE;
  edit->typing = FALSE;
  edit->anchor = found - edit->text.a;
  edit->cursor = edit->anchor + size;
  return TRUE;
}

// Replace non-overlapping, literal matches as one undo step.
I64 EditReplaceAll(CEdit *edit, CStrs *query, CStrs *replacement)
{
  CStrBuf out;
  U8 *p = edit->text.a, *found;
  I64 size = StrsLen(query), count = 0;

  if (edit->readonly || size < 1) return 0;
  StrBufInit(&out);
  while (p < edit->text.b) {
    found = MemMem(p, edit->text.b - p, query->a, size);
    if (!found) break;
    StrBufPutN(&out, p, found - p);
    StrBufPutStrs(&out, replacement);
    p = found + size;
    count++;
  }
  StrBufPutN(&out, p, edit->text.b - p);
  if (count && !EditReplace(edit, 0, StrsLen(&edit->text), &out)) count = 0;
  StrBufFini(&out);
  return count;
}

// Merge touching deltas, preserving the cursor and revision before the group.
// This also groups a change/open command with its subsequent Insert-mode text.
Bool EditGroup(CEdit *edit)
{
  CEditChange *change = edit->undo, *previous;
  CStrBuf before, after;
  I64 a, end, previous_end, change_end;

  if (!change || !change->next) return FALSE;
  previous = change->next;
  previous_end = previous->at + StrsLen(&previous->after);
  change_end = change->at + StrsLen(&change->before);
  if (change->at > previous_end || change_end < previous->at) return FALSE;
  a = MinI64(previous->at, change->at);
  end = MaxI64(previous_end, change_end);
  StrBufInit(&before); StrBufInit(&after);
  if (change->at < previous->at)
    StrBufPutN(&before, change->before.a, previous->at - change->at);
  StrBufPutStrs(&before, &previous->before);
  if (change_end > previous_end)
    StrBufPutN(&before, change->before.a + previous_end - change->at, change_end - previous_end);
  StrBufPutN(&after, edit->text.a + a,
    end - a + StrsLen(&change->after) - StrsLen(&change->before));
  StrBufClear(&previous->before); StrBufPutStrs(&previous->before, &before);
  StrBufClear(&previous->after); StrBufPutStrs(&previous->after, &after);
  previous->at = a;
  StrBufFini(&before); StrBufFini(&after);
  edit->undo = previous;
  change->next = NULL;
  EditChangesFree(change);
  return TRUE;
}

// Ordinary typing groups until a space, navigation, command or save boundary.
Bool EditType(CEdit *edit, CStrs *text)
{
  Bool join = edit->typing && edit->anchor < 0 && edit->revision != edit->saved;

  if (!EditInsert(edit, text)) return FALSE;
  if (join) EditGroup(edit);
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
