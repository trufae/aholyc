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
  HtkShade(p->x + 2, p->y + p->h, p->w, 1);
  HtkShade(p->x + p->w, p->y + 1, 2, p->h);
  while (k) {
    fg = HTK_C_FG;
    bg = HTK_C_BG;
    if (i == p->value) {
      fg = TERM_BRIGHT_WHITE;
      bg = HTK_C_BTN_BG;
    }
    if (k->disabled)
      fg = HTK_C_DIM;
    HtkRect(p->x + 1, p->y + 1 + i, p->w - 2, 1, ' ', fg, bg);
    HtkStr(p->x + 2, p->y + 1 + i, k->text, fg, bg);
    k = k->sib;
    i++;
  }
}

U0 HtkPickChoose(HtkCtl *p)
{
  HtkCtl *owner = p->link;
  HtkCtl *item = HtkKidAt(owner, p->value);

  HtkPopupClose;
  if (!item || item->disabled)
    return;
  if (owner->kind == HTK_COMBO) {
    owner->value = p->value;
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
  I64 count = HtkKidCount(p->link);

  if (e->key == TERM_KEY_UP && p->value > 0)
    p->value--;
  else if (e->key == TERM_KEY_DOWN && p->value < count - 1)
    p->value++;
  else if (e->key == TERM_KEY_ENTER || e->key == ' ')
    HtkPickChoose(p);
  else if ((e->key == TERM_KEY_LEFT || e->key == TERM_KEY_RIGHT) &&
    p->link->kind == HTK_MENU) {
      if (e->key == TERM_KEY_RIGHT)
        HtkPickSideways(p, 1);
      else
        HtkPickSideways(p, -1);
    }
  else if (e->key == TERM_KEY_ESCAPE)
    HtkPopupClose;
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
