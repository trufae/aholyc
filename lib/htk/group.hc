// Framed containers: titled group, toolbar strip, statusbar.

HtkCtl *HtkGroupNew(U8 *title)
{
  HtkCtl *c = HtkNew(HTK_GROUP);

  HtkSetText(c, title);
  return c;
}

U0 HtkGroupMeasure(HtkCtl *c)
{
  c->pw = HtkRunes(c->text) + 4;
  c->ph = 2;
  if (c->kids) {
    HtkMeasureCtl(c->kids);
    if (c->kids->pw + 2 > c->pw)
      c->pw = c->kids->pw + 2;
    c->ph = c->kids->ph + 2;
  }
}

U0 HtkGroupLayout(HtkCtl *c)
{
  if (!c->kids)
    return;
  c->kids->x = c->x + 1;
  c->kids->y = c->y + 1;
  c->kids->w = c->w - 2;
  c->kids->h = c->h - 2;
  HtkLayoutCtl(c->kids);
}

U0 HtkGroupDraw(HtkCtl *c)
{
  HtkFrame(c->x, c->y, c->w, c->h, FALSE, HTK_C_DIM, HTK_C_BG);
  if (c->text[0]) {
    HtkChr(c->x + 1, c->y, ' ', HTK_C_FG, HTK_C_BG);
    HtkStr(c->x + 2, c->y, c->text, HTK_C_FG, HTK_C_BG);
    HtkChr(c->x + 2 + HtkRunes(c->text), c->y, ' ', HTK_C_FG, HTK_C_BG);
  }
  if (c->kids)
    HtkDrawCtl(c->kids);
}

#define HtkToolbarNew HtkNew(HTK_TOOLBAR)

U0 HtkToolbarDraw(HtkCtl *c)
{
  HtkRect(c->x, c->y, c->w, c->h, ' ', HTK_C_FG, HTK_C_BG);
  HtkKidsDraw(c);
}

U0 HtkStatusMeasure(HtkCtl *c)
{
  HtkLabelMeasure(c);
  c->pw += 2;
}

HtkCtl *HtkStatusbarNew(U8 *text)
{
  HtkCtl *c = HtkNew(HTK_STATUS);

  HtkSetText(c, text);
  c->expand = FALSE;
  return c;
}
