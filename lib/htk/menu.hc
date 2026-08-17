// Menu bar and dropdown menus.  Menus are HTK_MENU kids of a window, drawn
// on the row under the frame top; items are HTK_MENUITEM kids of the menu.

HtkCtl *HtkMenuNew(HtkCtl *window, U8 *title)
{
  HtkCtl *m = HtkNew(HTK_MENU);

  HtkSetText(m, title);
  HtkAdd(window, m);
  return m;
}

HtkCtl *HtkMenuItem(HtkCtl *menu, U8 *label)
{
  HtkCtl *item = HtkNew(HTK_MENUITEM);

  HtkSetText(item, label);
  HtkAdd(menu, item);
  return item;
}

// A menu that lives outside the menubar: pop it up with HtkMenuOpenAt or
// attach it to a control's ->menu for right clicks.
HtkCtl *HtkContextMenuNew()
{
  return HtkNew(HTK_MENU);
}

// Nested menu: an HTK_MENU kid shown with a ▸ marker that opens beside.
HtkCtl *HtkSubMenu(HtkCtl *menu, U8 *title)
{
  HtkCtl *sub = HtkNew(HTK_MENU);

  HtkSetText(sub, title);
  HtkAdd(menu, sub);
  return sub;
}

U0 HtkMenuOpenAt(HtkCtl *m, I64 x, I64 y)
{
  if (m && m->kids)
    HtkPopupOpen(HtkPickNew(m, x, y));
}

Bool HtkWindowHasMenu(HtkCtl *w)
{
  HtkCtl *k = w->kids;

  while (k) {
    if (k->kind == HTK_MENU)
      return TRUE;
    k = k->sib;
  }
  return FALSE;
}

// Lay the titles across the menubar row; returns the menu under column x.
HtkCtl *HtkMenubarHit(HtkCtl *w, I64 x)
{
  HtkCtl *k = w->kids;
  I64 at = w->x + 2;

  while (k) {
    if (k->kind == HTK_MENU) {
      k->x = at;
      k->y = w->y + 1;
      k->w = HtkRunes(k->text) + 2;
      k->h = 1;
      if (x >= at && x < at + k->w)
        return k;
      at += k->w;
    }
    k = k->sib;
  }
  return NULL;
}

U0 HtkMenubarDraw(HtkCtl *w)
{
  HtkCtl *k = w->kids;
  I64 at = w->x + 2;

  HtkRect(w->x + 1, w->y + 1, w->w - 2, 1, ' ', HTK_C_FG, HTK_C_BG);
  while (k) {
    if (k->kind == HTK_MENU) {
      k->x = at;
      k->y = w->y + 1;
      k->w = HtkRunes(k->text) + 2;
      k->h = 1;
      if (htk_popup && HtkPopupRoot->link == k)
        HtkRect(at, w->y + 1, k->w, 1, ' ', TERM_BRIGHT_WHITE, HTK_C_BTN_BG);
      if (htk_popup && HtkPopupRoot->link == k)
        HtkStr(at + 1, w->y + 1, k->text, TERM_BRIGHT_WHITE, HTK_C_BTN_BG);
      else
        HtkStr(at + 1, w->y + 1, k->text, HtkInk(k, HTK_C_FG), HTK_C_BG);
      at += k->w;
    }
    k = k->sib;
  }
}

U0 HtkMenuOpen(HtkCtl *m)
{
  if (m->kids)
    HtkPopupOpen(HtkPickNew(m, m->x, m->y + 1));
}
