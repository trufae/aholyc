// Clipboard helpers.  There is always an in-process clipboard; defining
// HTK_NATIVE_CLIPBOARD additionally emits an OSC 52 clipboard-set sequence
// for terminals that permit access to their host OS clipboard.

U8 *htk_clipboard;

U0 HtkClipboardSet(U8 *text)
{
  if (htk_clipboard)
    Free(htk_clipboard);
  htk_clipboard = StrNew(text);
#ifdef HTK_NATIVE_CLIPBOARD
  if (!TermLegacy) {
    I64 length;
    U8 *encoded = Base64EncodeAlloc(htk_clipboard, StrLen(htk_clipboard),
      &length);

    if (encoded) {
      TermWrite("\x1B]52;c;", 7);  // OSC 52: system clipboard
      TermWrite(encoded, length);
      TermWrite("\x07", 1);
      Free(encoded);
    }
  }
#endif
}

U8 *HtkClipboardText()
{
  if (!htk_clipboard)
    return "";
  return htk_clipboard;
}

Bool HtkTableCopy(HtkCtl *c)
{
  I64 col, ncols = HtkKidCount(c), length = 2, at = 0;
  U8 *text;

  if (c->value < 0 || c->value >= c->high || !ncols)
    return FALSE;
  for (col = 0; col < ncols; col++)
    length += StrLen(HtkTableCell(c, c->value, col)) + 1;
  text = MAlloc(length);
  for (col = 0; col < ncols; col++) {
    U8 *cell = HtkTableCell(c, c->value, col);
    I64 cell_length = StrLen(cell);

    MemCpy(text + at, cell, cell_length);
    at += cell_length;
    if (col + 1 < ncols)
      text[at++] = '\t';
    else
      text[at++] = '\n';
  }
  text[at] = 0;
  HtkClipboardSet(text);
  Free(text);
  return TRUE;
}

// Copy the selected entry range, multiline range, or the selected table row
// (as TSV).  Returns whether text was actually copied.
Bool HtkCopySelection(HtkCtl *c)
{
  I64 from, to;
  U8 *text;

  if (!c)
    return FALSE;
  if (c->kind == HTK_TABLE)
    return HtkTableCopy(c);
  if ((c->kind != HTK_ENTRY && c->kind != HTK_MULTILINE) ||
    !HtkTextSelected(c, &from, &to))
    return FALSE;
  text = MAlloc(to - from + 1);
  MemCpy(text, c->text + from, to - from);
  text[to - from] = 0;
  HtkClipboardSet(text);
  Free(text);
  return TRUE;
}

U0 HtkCtrlCSet(I64 mode)
{
  if (mode < HTK_CTRLC_DEFAULT || mode > HTK_CTRLC_CALLBACK)
    mode = HTK_CTRLC_DEFAULT;
  htk_ctrl_c_mode = mode;
}

// fn(data) runs on HTK's event-loop thread after ^C is observed, never from
// the SIGINT handler itself, so it may safely open dialogs or change widgets.
U0 HtkCtrlCHandler(I64 fn, I64 data=0)
{
  htk_ctrl_c_fn = fn;
  htk_ctrl_c_data = data;
}

// SIGINT is observed by the event loop, not handled here; queue the callback
// so a handler may safely enter a nested modal loop after HtkMain has resumed.
U0 HtkCtrlCCall(I64 unused, I64 unused2)
{
  htk_ctrl_c_pending = FALSE;
  htk_ctrl_c_active = TRUE;
  if (htk_ctrl_c_fn)
    htk_ctrl_c_fn(htk_ctrl_c_data);
  htk_ctrl_c_active = FALSE;
}
