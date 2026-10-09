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
  I64 fg = HtkInk(c, HTK_C_BTN_FG);
  I64 pad;

  if (c->parent && c->parent->kind == HTK_TOOLBAR) {
    bg = HTK_C_TOOL_BG;
    fg = HtkInk(c, HTK_C_TOOL_FG);
  }
  bg = HtkBg(c, bg);
  if (HtkFocused(c)) fg = HtkInk(c, HTK_C_FG);
  if (fg == bg) fg = HTK_C_BTN_FG;
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

// Compact square-bracket action; value highlights a selected format/mode.
HtkCtl *HtkToolButtonNew(U8 *text)
{
  HtkCtl *c = HtkButtonNew(text);

  c->kind = HTK_TOOLBUTTON;
  return c;
}

U0 HtkToolButtonMeasure(HtkCtl *c)
{
  c->pw = HtkRunes(c->text) + 2;
  c->ph = 1;
}

U0 HtkToolButtonDraw(HtkCtl *c)
{
  I64 bg = HtkBg(c, HTK_C_BG), attr = 0;
  I64 fg = HtkInk(c, HTK_C_FG);

  if (c->parent && c->parent->kind == HTK_TOOLBAR) {
    bg = HtkBg(c, HTK_C_TOOL_BG);
    fg = HtkInk(c, HTK_C_TOOL_FG);
  } else if (c->parent && c->parent->kind == HTK_STATUS) {
    bg = HtkBg(c, HTK_C_DIM);
    fg = HtkInk(c, HTK_C_TITLE);
  }
  if (c->value || HtkFocused(c)) {
    bg = HTK_C_SEL_BG;
    fg = HTK_C_SEL_FG;
    attr = TERM_BOLD;
  }
  if (fg == bg) fg = HTK_C_SEL_FG;
  HtkRect(c->x, c->y, c->w, 1, ' ', fg, bg);
  HtkChr(c->x, c->y, '[', fg, bg);
  HtkStr(c->x + 1, c->y, c->text, fg, bg, attr);
  HtkChr(c->x + c->w - 1, c->y, ']', fg, bg);
}
