// Modal dialogs: message box, prompt, and a path-entry file picker.

Bool htk_dialog_ok;

U0 HtkDialogYes(HtkCtl *b)
{
  htk_dialog_ok = TRUE;
  HtkWindowClose(HtkOwnerWindow(b));
}

U0 HtkDialogNo(HtkCtl *b)
{
  htk_dialog_ok = FALSE;
  HtkWindowClose(HtkOwnerWindow(b));
}

// A dismissable window sized to its content, centered on screen.
HtkCtl *HtkDialogNew(U8 *title, HtkCtl *content)
{
  HtkCtl *w;
  I64 need_w, need_h;

  HtkMeasureCtl(content);
  need_w = content->pw + 6;
  if (HtkRunes(title) + 8 > need_w)
    need_w = HtkRunes(title) + 8;
  need_h = content->ph + 2;
  w = HtkWindowNew(title, need_w, need_h);
  w->low = TRUE;  // ESC dismisses
  HtkAdd(w, content);
  return w;
}

U0 HtkMsgBox(U8 *title, U8 *body)
{
  HtkCtl *box = HtkNew(HTK_BOX);
  HtkCtl *ok = HtkButtonNew("  OK  ");
  HtkCtl *w;

  box->vertical = TRUE;
  HtkAdd(box, HtkNew(HTK_LABEL));
  HtkSetText(box->kids, body);
  HtkAdd(box, HtkNew(HTK_SEP));
  ok->changed = &HtkDialogYes;
  HtkAdd(box, ok);
  w = HtkDialogNew(title, box);
  w->link = ok;
  HtkSetFocus(ok);
  HtkModal(w);
}

// MAlloc'd entry text, or NULL when cancelled.
U8 *HtkPrompt(U8 *title, U8 *body, U8 *init)
{
  HtkCtl *box = HtkNew(HTK_BOX);
  HtkCtl *entry = HtkEntryNew(init);
  HtkCtl *row = HtkNew(HTK_BOX);
  HtkCtl *ok = HtkButtonNew("  OK  ");
  HtkCtl *cancel = HtkButtonNew("Cancel");
  HtkCtl *w;
  U8 *result = NULL;

  box->vertical = TRUE;
  HtkAdd(box, HtkNew(HTK_LABEL));
  HtkSetText(box->kids, body);
  entry->low = 30;
  HtkAdd(box, entry);
  ok->changed = &HtkDialogYes;
  cancel->changed = &HtkDialogNo;
  HtkAdd(row, ok);
  HtkAdd(row, cancel);
  HtkAdd(box, row);
  w = HtkDialogNew(title, box);
  w->link = ok;
  htk_dialog_ok = FALSE;
  HtkSetFocus(entry);
  HtkModal(w);
  if (htk_dialog_ok)
    result = StrNew(entry->text);
  return result;
}

U8 *HtkOpenFile()
{
  U8 *path = HtkPrompt("Open", "File path:", "");

  if (path && !path[0]) {
    Free(path);
    path = NULL;
  }
  return path;
}
