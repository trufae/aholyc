// Modal dialogs: message box, prompt, and a path-entry file picker.

Bool htk_dialog_ok;

// Button handler: the button's value is the verdict.
U0 HtkDialogEnd(HtkCtl *b)
{
  htk_dialog_ok = b->value;
  HtkWindowClose(HtkOwnerWindow(b));
}

HtkCtl *HtkDialogButton(U8 *text, Bool ok)
{
  HtkCtl *b = HtkButtonNew(text);

  b->value = ok;
  b->changed = &HtkDialogEnd;
  return b;
}

// Vertical box holding the body text.
HtkCtl *HtkDialogBody(U8 *body)
{
  HtkCtl *box = HtkNew(HTK_BOX);

  box->vertical = TRUE;
  HtkAdd(box, HtkNew(HTK_LABEL));
  HtkSetText(box->kids, body);
  return box;
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
  HtkCtl *box = HtkDialogBody(body);
  HtkCtl *ok = HtkDialogButton("  OK  ", TRUE);
  HtkCtl *w;

  HtkAdd(box, HtkNew(HTK_SEP));
  HtkAdd(box, ok);
  w = HtkDialogNew(title, box);
  w->link = ok;
  HtkSetFocus(ok);
  HtkModal(w);
}

// MAlloc'd entry text, or NULL when cancelled.
U8 *HtkPrompt(U8 *title, U8 *body, U8 *init)
{
  HtkCtl *box = HtkDialogBody(body);
  HtkCtl *entry = HtkEntryNew(init);
  HtkCtl *row = HtkNew(HTK_BOX);
  HtkCtl *ok = HtkDialogButton("  OK  ", TRUE);
  HtkCtl *w;
  U8 *result = NULL;

  entry->low = 30;
  HtkAdd(box, entry);
  HtkAdd(row, ok);
  HtkAdd(row, HtkDialogButton("Cancel", FALSE));
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
