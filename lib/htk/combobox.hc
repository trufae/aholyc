// Dropdown selector: a field showing the current choice, opening a pick
// list underneath.  Items are HTK_ITEM kids, value is the selected index.

HtkCtl *HtkComboNew()
{
  HtkCtl *c = HtkNew(HTK_COMBO);

  c->focusable = TRUE;
  c->value = -1;
  return c;
}

#define HtkComboAdd HtkAddItem

U0 HtkComboMeasure(HtkCtl *c)
{
  c->pw = HtkItemsWidth(c);
  if (c->pw < 8)
    c->pw = 8;
  c->ph = 1;
}

U0 HtkComboDraw(HtkCtl *c)
{
  HtkCtl *item = HtkKidAt(c, c->value);
  I64 bg = HtkBg(c, HTK_C_FIELD_BG);
  HtkRect(c->x, c->y, c->w, 1, ' ', HTK_C_FIELD_FG, bg);
  if (item)
    HtkStr(c->x + 1, c->y, item->text, HtkInk(c, HTK_C_FIELD_FG), bg);
  HtkChr(c->x + c->w - 2, c->y, HTK_R_DOWN, HtkInk(c, HTK_C_FIELD_FG), bg);
}

U0 HtkComboOpen(HtkCtl *c)
{
  if (c->kids)
    HtkPopupOpen(HtkPickNew(c, c->x, c->y + 1));
}

Bool HtkComboKey(HtkCtl *c, CTermEvent *e)
{
  if (e->key == TERM_KEY_ENTER || e->key == ' ' ||
    e->key == TERM_KEY_DOWN) {
    HtkComboOpen(c);
    return TRUE;
  }
  return FALSE;
}
