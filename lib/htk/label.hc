// Static text (multi-line via \n) and the horizontal separator.

U0 HtkLabelMeasure(HtkCtl *c)
{
  I64 i = 0, line = 0, best = 0, lines = 1;

  while (c->text[i]) {
    if (c->text[i] == '\n') {
      lines++;
      line = 0;
      i++;
    } else {
      TermRuneNext(c->text, &i);
      line++;
    }
    if (line > best)
      best = line;
  }
  c->pw = best;
  c->ph = lines;
}

U0 HtkLabelDraw(HtkCtl *c)
{
  I64 i = 0, y = c->y;
  I64 bg = HTK_C_BG;
  I64 fg = HtkInk(c, HTK_C_FG);
  I64 bar = HtkBarKind(c);

  if (c->kind == HTK_STATUS) {  // docked bar: inverse strip like the frame
    HtkRect(c->x, c->y, c->w, c->h, ' ', HTK_C_TITLE, HTK_C_DIM);
    HtkStr(c->x + 1, c->y, c->text, HTK_C_TITLE, HTK_C_DIM);
    return;
  }
  if (bar == HTK_TOOLBAR) {
    bg = HTK_C_TOOL_BG; fg = HtkInk(c, HTK_C_TOOL_FG);
    HtkRect(c->x, c->y, c->w, c->h, ' ', fg, bg);
  } else if (bar == HTK_STATUS) {
    bg = HTK_C_DIM; fg = HTK_C_TITLE;
    HtkRect(c->x, c->y, c->w, c->h, ' ', fg, bg);
  }
  while (c->text[i] && y < c->y + c->h) {
    HtkStr(c->x, y, c->text + i, fg, bg);
    while (c->text[i] && c->text[i] != '\n')
      i++;
    if (c->text[i])
      i++;
    y++;
  }
}

U0 HtkSepMeasure(HtkCtl *c)
{
  c->pw = 1;
  c->ph = 1;
}

U0 HtkSepDraw(HtkCtl *c)
{
  I64 i, fg = HTK_C_DIM, bg = HTK_C_BG;

  if (HtkBarKind(c) == HTK_TOOLBAR) { fg = HTK_C_TOOL_FG; bg = HTK_C_TOOL_BG; }
  else if (HtkBarKind(c) == HTK_STATUS) { fg = HTK_C_TITLE; bg = HTK_C_DIM; }

  for (i = c->x; i < c->x + c->w; i++)
    HtkChr(i, c->y, HTK_R_H, fg, bg);
}
