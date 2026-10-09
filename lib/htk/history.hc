#ifndef AHOLYC_LIB_HTK_HISTORY_HC
#define AHOLYC_LIB_HTK_HISTORY_HC

#include "choice.hc"
#include "../text/edit.hc"

U8 *HtkHistoryLabel(CEditChange *change, I64 steps)
{
  CStrBuf label;
  CStrs *text = &change->after;
  I64 i, n, rune;

  StrBufInit(&label);
  if (steps < 0) StrBufPrintf(&label, "Undo %d: ", -steps);
  else StrBufPrintf(&label, "Redo %d: ", steps);
  if (StrsEmpty(text)) { StrBufPutS(&label, "delete "); text = &change->before; }
  for (i = 0; i < StrsLen(text) && i < 64; i += n) {
    n = MaxI64(1, Utf8DecodeRune(text->a + i, StrsLen(text) - i, &rune));
    if (rune < ' ' || rune == 127) StrBufPutC(&label, ' ');
    else StrBufPutN(&label, text->a + i, n);
  }
  U8 *result = StrNew(label.a);
  StrBufFini(&label);
  return result;
}

U0 HtkHistoryFor(HtkCtl *owner, CEdit *edit)
{
  U8 *labels[257];
  I64 steps[257], count = 0, i = 0, picked, direction;
  CEditChange *change = edit->undo;

  while (change && count < 128) {
    steps[count] = --i;
    labels[count++] = HtkHistoryLabel(change, i);
    change = change->next;
  }
  i = 0; change = edit->redo;
  while (change && count < 256) {
    steps[count] = ++i;
    labels[count++] = HtkHistoryLabel(change, i);
    change = change->next;
  }
  if (!count) { HtkNotify("No edit history", 1500); return; }
  picked = HtkListChoiceFor(owner, "History - restore through selected change", labels, count);
  if (picked >= 0) {
    direction = steps[picked] > 0;
    for (i = 0; i < AbsI64(steps[picked]); i++) EditUndo(edit, direction);
  }
  for (i = 0; i < count; i++) Free(labels[i]);
}

#endif
