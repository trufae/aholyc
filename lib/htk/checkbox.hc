// Checkbox "[x]" and the vertical radio group "( )/(•)"; radio options are
// HTK_ITEM kids and value is the selected index.

HtkCtl *HtkCheckboxNew(U8 *text, Bool checked)
{
  HtkCtl *c = HtkNew(HTK_CHECKBOX);

  HtkSetText(c, text);
  c->value = checked;
  c->focusable = TRUE;
  return c;
}

U0 HtkCheckboxMeasure(HtkCtl *c)
{
  c->pw = HtkRunes(c->text) + 4;
  c->ph = 1;
}

U0 HtkCheckboxDraw(HtkCtl *c)
{
  I64 bg = HTK_C_BG;
  U8 *mark = "[ ]";

  if (HtkFocused(c))
    bg = HTK_C_FOCUS_BG;
  if (c->value)
    mark = "[x]";
  HtkRect(c->x, c->y, c->w, 1, ' ', HTK_C_FG, bg);
  HtkStr(c->x, c->y, mark, HtkInk(c, HTK_C_FG), bg);
  HtkStr(c->x + 4, c->y, c->text, HtkInk(c, HTK_C_FG), bg);
}

Bool HtkCheckboxKey(HtkCtl *c, CTermEvent *e)
{
  if (e->key == ' ' || e->key == TERM_KEY_ENTER) {
    c->value = !c->value;
    HtkFire(c);
    return TRUE;
  }
  return FALSE;
}

HtkCtl *HtkRadioNew()
{
  HtkCtl *c = HtkNew(HTK_RADIO);

  c->focusable = TRUE;
  c->value = -1;
  return c;
}

U0 HtkRadioAdd(HtkCtl *c, U8 *text)
{
  HtkCtl *item = HtkNew(HTK_ITEM);

  HtkSetText(item, text);
  HtkAdd(c, item);
  if (c->value < 0)
    c->value = 0;
}

U0 HtkRadioMeasure(HtkCtl *c)
{
  HtkCtl *k = c->kids;

  c->pw = 0;
  c->ph = 0;
  while (k) {
    if (HtkRunes(k->text) + 4 > c->pw)
      c->pw = HtkRunes(k->text) + 4;
    c->ph++;
    k = k->sib;
  }
}

U0 HtkRadioDraw(HtkCtl *c)
{
  HtkCtl *k = c->kids;
  I64 i = 0, bg;

  while (k && i < c->h) {
    bg = HTK_C_BG;
    if (HtkFocused(c) && i == c->value)
      bg = HTK_C_FOCUS_BG;
    HtkRect(c->x, c->y + i, c->w, 1, ' ', HTK_C_FG, bg);
    HtkStr(c->x, c->y + i, "( )", HtkInk(c, HTK_C_FG), bg);
    if (i == c->value)
      HtkChr(c->x + 1, c->y + i, HTK_R_DOT, HtkInk(c, HTK_C_FG), bg);
    HtkStr(c->x + 4, c->y + i, k->text, HtkInk(c, HTK_C_FG), bg);
    k = k->sib;
    i++;
  }
}

Bool HtkRadioKey(HtkCtl *c, CTermEvent *e)
{
  I64 count = HtkKidCount(c);

  if (!count)
    return FALSE;
  if (e->key == TERM_KEY_UP && c->value > 0)
    c->value--;
  else if (e->key == TERM_KEY_DOWN && c->value < count - 1)
    c->value++;
  else
    return FALSE;
  HtkFire(c);
  return TRUE;
}
