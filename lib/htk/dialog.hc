// Modal dialogs: message box, prompt, and a path-entry file picker.

Bool htk_dialog_ok;
Bool htk_quit_confirm_active;

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

U0 HtkMsgBoxFor(HtkCtl *owner, U8 *title, U8 *body)
{
  HtkCtl *box = HtkDialogBody(body);
  HtkCtl *ok = HtkDialogButton("  OK  ", TRUE);
  HtkCtl *row = HtkButtonBarNew;
  HtkCtl *sep = HtkNew(HTK_SEP);
  HtkCtl *w;

  sep->bottom = TRUE;
  HtkAdd(box, sep);
  HtkAdd(row, ok);
  HtkAdd(box, row);
  w = HtkDialogNew(title, box);
  w->link = ok;
  HtkSetFocus(ok);
  HtkModalFor(w, owner);
}

U0 HtkMsgBox(U8 *title, U8 *body)
{
  HtkMsgBoxFor(HtkTop, title, body);
}

// Yes/No modal confirmation.  ESC and closing the frame answer No.
Bool HtkConfirmFor(HtkCtl *owner, U8 *title, U8 *body)
{
  HtkCtl *box = HtkDialogBody(body);
  HtkCtl *row = HtkButtonBarNew;
  HtkCtl *yes = HtkDialogButton(" Yes ", TRUE);
  HtkCtl *sep = HtkNew(HTK_SEP);
  HtkCtl *w;

  sep->bottom = TRUE;
  HtkAdd(box, sep);
  HtkAdd(row, yes);
  HtkAdd(row, HtkDialogButton(" No ", FALSE));
  HtkAdd(box, row);
  w = HtkDialogNew(title, box);
  // Root confirmations (the quit prompt) are close-only and have no window
  // manager menu: their Yes/No buttons are the only management actions.
  if (!owner)
    HtkWindowSetControls(w, HTK_WINDOW_CLOSE);
  w->link = yes;
  htk_dialog_ok = FALSE;
  HtkSetFocus(yes);
  HtkModalFor(w, owner);
  return htk_dialog_ok;
}

Bool HtkConfirm(U8 *title, U8 *body)
{
  return HtkConfirmFor(HtkTop, title, body);
}

// Shared root-desktop confirmation used by the desktop Quit command and
// applications that choose to turn Ctrl-C into a confirmation.
U0 HtkConfirmQuit()
{
  if (htk_quit_confirm_active)
    return;
  htk_quit_confirm_active = TRUE;
  if (HtkConfirmFor(NULL, "Quit", "Close all windows?"))
    HtkQuit;
  htk_quit_confirm_active = FALSE;
}

// MAlloc'd entry text, or NULL when cancelled.
U8 *HtkPromptFor(HtkCtl *owner, U8 *title, U8 *body, U8 *init="")
{
  HtkCtl *box = HtkDialogBody(body);
  HtkCtl *entry = HtkEntryNew(init);
  HtkCtl *row = HtkButtonBarNew;
  HtkCtl *ok = HtkDialogButton("  OK  ", TRUE);
  HtkCtl *sep = HtkNew(HTK_SEP);
  HtkCtl *w;
  U8 *result = NULL;

  entry->low = 30;
  HtkAdd(box, entry);
  sep->bottom = TRUE;
  HtkAdd(box, sep);
  HtkAdd(row, ok);
  HtkAdd(row, HtkDialogButton("Cancel", FALSE));
  HtkAdd(box, row);
  w = HtkDialogNew(title, box);
  w->link = ok;
  htk_dialog_ok = FALSE;
  HtkSetFocus(entry);
  HtkModalFor(w, owner);
  if (htk_dialog_ok)
    result = StrNew(entry->text);
  return result;
}

// MAlloc'd entry text, or NULL when cancelled.  Modal to the active window.
U8 *HtkPrompt(U8 *title, U8 *body, U8 *init="")
{
  return HtkPromptFor(HtkTop, title, body, init);
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
