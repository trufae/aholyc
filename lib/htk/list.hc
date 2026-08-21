// Floating pick list: the shared engine behind combo dropdowns and menus.
// The popup does not own the items; it renders the HTK_ITEM/HTK_MENUITEM kids
// of its owner (link) and reports the chosen index back.

HtkCtl *HtkPickNew(HtkCtl *owner, I64 x, I64 y)
{
  HtkCtl *p = HtkNew(HTK_POPUP);
  HtkCtl *k = owner->kids;
  I64 n = 0, best = 8;

  p->link = owner;
  while (k) {
    if (HtkRunes(k->text) > best)
      best = HtkRunes(k->text);
    n++;
    k = k->sib;
  }
  p->w = best + 4;
  p->h = n + 2;
  p->x = x;
  p->y = y;
  if (p->x + p->w > TermWidth)
    p->x = TermWidth - p->w;
  if (p->y + p->h > TermHeight)
    p->y = y - p->h - 1;
  if (p->x < 0)
    p->x = 0;
  if (p->y < 0)
    p->y = 0;
  p->value = 0;
  if (owner->kind == HTK_COMBO && owner->value >= 0)
    p->value = owner->value;
  return p;
}

U0 HtkPickDraw(HtkCtl *p)
{
  HtkCtl *k = p->link->kids;
  I64 i = 0, bg, fg;

  HtkRect(p->x, p->y, p->w, p->h, ' ', HTK_C_FG, HTK_C_BG);
  HtkFrame(p->x, p->y, p->w, p->h, FALSE, HTK_C_FG, HTK_C_BG);
  // Popups intentionally have no shadows: menus should not darken controls
  // behind them.  Window frames remain the only shadow-casting layer.
  while (k) {
    fg = HTK_C_FG;
    bg = HTK_C_BG;
    if (k->kind == HTK_SEP) {
      HtkRect(p->x + 1, p->y + 1 + i, p->w - 2, 1, HTK_R_H,
        HTK_C_DIM, bg);
    } else if (i == p->value) {
      fg = TERM_BRIGHT_WHITE;
      bg = HTK_C_BTN_BG;
      if (k->disabled)
        fg = HTK_C_DIM;
      HtkRect(p->x + 1, p->y + 1 + i, p->w - 2, 1, ' ', fg, bg);
      HtkStr(p->x + 2, p->y + 1 + i, k->text, fg, bg);
      if (k->kind == HTK_MENU)  // submenu marker
        HtkChr(p->x + p->w - 2, p->y + 1 + i, HTK_R_RIGHT, fg, bg);
    } else {
      if (k->disabled)
        fg = HTK_C_DIM;
      HtkRect(p->x + 1, p->y + 1 + i, p->w - 2, 1, ' ', fg, bg);
      HtkStr(p->x + 2, p->y + 1 + i, k->text, fg, bg);
    }
    k = k->sib;
    i++;
  }
}

// Push the submenu of the selected item on top of the popup, beside it.
U0 HtkPickDescend(HtkCtl *p)
{
  HtkCtl *sub = HtkKidAt(p->link, p->value);

  if (sub && sub->kids)
    HtkPopupPush(HtkPickNew(sub, p->x + p->w - 1, p->y + p->value));
}

U0 HtkPickChoose(HtkCtl *p)
{
  HtkCtl *owner = p->link;
  HtkCtl *item = HtkKidAt(owner, p->value);
  I64 value = p->value;

  if (item && item->kind == HTK_MENU) {
    HtkPickDescend(p);
    return;
  }
  HtkPopupClose;
  if (!item || item->disabled)
    return;
  if (owner->kind == HTK_COMBO) {
    // HtkPopupClose frees p, so retain the selected index before closing it.
    owner->value = value;
    HtkFire(owner);
  } else
    HtkFire(item);
}

// Left/Right in a menubar dropdown: hop to the neighbouring menu (wrapping).
U0 HtkPickSideways(HtkCtl *p, I64 step)
{
  HtkCtl *menu = p->link;
  HtkCtl *k = menu->parent->kids;
  HtkCtl *prev = NULL, *first = NULL, *last = NULL, *next = NULL;

  while (k) {
    if (k->kind == HTK_MENU) {
      if (!first)
        first = k;
      if (k == menu)
        prev = last;
      else if (last == menu)
        next = k;
      last = k;
    }
    k = k->sib;
  }
  if (step > 0)
    menu = next;
  else
    menu = prev;
  if (!menu && step > 0)
    menu = first;
  else if (!menu)
    menu = last;
  HtkPopupClose;
  if (menu && menu->kids)
    HtkPopupOpen(HtkPickNew(menu, menu->x, menu->y + 1));
}

Bool HtkPickKey(HtkCtl *p, CTermEvent *e)
{
  I64 count = HtkKidCount(p->link), old;
  HtkCtl *item;

  if (e->key == TERM_KEY_UP || e->key == 'k') {
    old = p->value;
    item = NULL;
    while (p->value > 0) {
      p->value--;
      item = HtkKidAt(p->link, p->value);
      if (item && item->kind != HTK_SEP)
        break;
    }
    if (!item || item->kind == HTK_SEP)
      p->value = old;
  } else if (e->key == TERM_KEY_DOWN || e->key == 'j') {
    old = p->value;
    item = NULL;
    while (p->value < count - 1) {
      p->value++;
      item = HtkKidAt(p->link, p->value);
      if (item && item->kind != HTK_SEP)
        break;
    }
    if (!item || item->kind == HTK_SEP)
      p->value = old;
  }
  else if (e->key == TERM_KEY_ENTER || e->key == ' ')
    HtkPickChoose(p);
  else if ((e->key == TERM_KEY_RIGHT || e->key == 'l') &&
    HtkKidAt(p->link, p->value) &&
    HtkKidAt(p->link, p->value)->kind == HTK_MENU)
    HtkPickDescend(p);
  else if ((e->key == TERM_KEY_LEFT || e->key == TERM_KEY_RIGHT ||
    e->key == 'h' || e->key == 'l') &&
    p->link->kind == HTK_MENU && p->link->parent &&
    p->link->parent->kind == HTK_WINDOW) {
      if (e->key == TERM_KEY_RIGHT || e->key == 'l')
        HtkPickSideways(p, 1);
      else
        HtkPickSideways(p, -1);
    }
  else if (e->key == TERM_KEY_ESCAPE ||
    (e->key == TERM_KEY_LEFT || e->key == 'h') && p->parent)
    HtkPopupPop;  // one level; the root pops to nothing
  else
    return FALSE;
  htk_dirty = TRUE;
  return TRUE;
}

U0 HtkPickMouse(HtkCtl *p, CTermEvent *e)
{
  I64 row = e->y - p->y - 1;

  if (row < 0 || row >= HtkKidCount(p->link))
    return;
  p->value = row;
  if (e->pressed && !e->motion && e->button == TERM_MOUSE_LEFT)
    HtkPickChoose(p);
  htk_dirty = TRUE;
}
