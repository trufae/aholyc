// Push button: a green Borland slab.  Toolbar buttons are flat and gray.

HtkCtl *HtkButtonNew(U8 *text)
{
  HtkCtl *c = HtkNew(HTK_BUTTON);

  HtkSetText(c, text);
  c->focusable = TRUE;
  return c;
}

U0 HtkButtonMeasure(HtkCtl *c)
{
  c->pw = HtkRunes(c->text) + 4;
  c->ph = 1;
}

U0 HtkButtonDraw(HtkCtl *c)
{
  I64 bg = HTK_C_BTN_BG;
  I64 fg = HtkInk(c, HTK_C_FG);
  I64 pad;

  if (c->parent && c->parent->kind == HTK_TOOLBAR)
    bg = HTK_C_BG;
  bg = HtkBg(c, bg);
  HtkRect(c->x, c->y, c->w, 1, ' ', fg, bg);
  pad = (c->w - HtkRunes(c->text)) / 2;
  if (pad < 0)
    pad = 0;
  if (HtkFocused(c))
    HtkStr(c->x + pad, c->y, c->text, fg, bg, TERM_BOLD);
  else
    HtkStr(c->x + pad, c->y, c->text, fg, bg);
}

Bool HtkButtonKey(HtkCtl *c, CTermEvent *e)
{
  if (e->key == TERM_KEY_ENTER || e->key == ' ') {
    HtkFire(c);
    return TRUE;
  }
  return FALSE;
}
