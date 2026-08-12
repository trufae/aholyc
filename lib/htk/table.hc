// Table with pull-model cells: columns are HTK_ITEM kids, the row count is
// high, and cell text comes from fn(table, row, col, data).

HtkCtl *HtkTableNew(I64 cellfn, I64 data)
{
  HtkCtl *c = HtkNew(HTK_TABLE);

  c->fn = cellfn;
  c->data = data;
  c->value = -1;
  c->focusable = TRUE;
  c->expand = TRUE;
  return c;
}

U0 HtkTableColumn(HtkCtl *c, U8 *title)
{
  HtkCtl *col = HtkNew(HTK_ITEM);

  HtkSetText(col, title);
  HtkAdd(c, col);
}

U8 *HtkTableCell(HtkCtl *c, I64 row, I64 col)
{
  I64 fetch = c->fn;

  if (!fetch)
    return "";
  return fetch(c, row, col, c->data)(U8 *);
}

U0 HtkTableMeasure(HtkCtl *c)
{
  c->pw = 8 * HtkKidCount(c);
  if (c->pw < 16)
    c->pw = 16;
  c->ph = 6;
}

U0 HtkTableDraw(HtkCtl *c)
{
  I64 ncols = HtkKidCount(c);
  I64 span, row, col, x, fg, bg;
  HtkCtl *k;

  if (!ncols)
    return;
  span = c->w / ncols;
  if (span < 3)
    span = 3;
  // Header.
  k = c->kids;
  x = c->x;
  HtkRect(c->x, c->y, c->w, 1, ' ', HTK_C_FG, HTK_C_BG);
  while (k) {
    HtkStr(x, c->y, k->text, HTK_C_FG, HTK_C_BG, TERM_BOLD | TERM_UNDERLINE);
    x += span;
    k = k->sib;
  }
  // Keep the selection visible.
  if (c->value >= 0 && c->value < c->top)
    c->top = c->value;
  if (c->value >= c->top + c->h - 1)
    c->top = c->value - c->h + 2;
  for (row = c->top; row < c->high && row - c->top < c->h - 1; row++) {
    fg = HTK_C_FG;
    bg = HTK_C_BG;
    if (row == c->value) {
      bg = HTK_C_FOCUS_BG;
      if (!HtkFocused(c))
        bg = HTK_C_DIM;
    }
    HtkRect(c->x, c->y + 1 + row - c->top, c->w, 1, ' ', fg, bg);
    for (col = 0; col < ncols; col++)
      HtkStr(c->x + col * span, c->y + 1 + row - c->top,
        HtkTableCell(c, row, col), fg, bg);
  }
}

U0 HtkTableSelect(HtkCtl *c, I64 row)
{
  if (row < 0)
    row = 0;
  if (row >= c->high)
    row = c->high - 1;
  if (row == c->value)
    return;
  c->value = row;
  HtkFire(c);
}

Bool HtkTableKey(HtkCtl *c, CTermEvent *e)
{
  I64 page = c->h - 2;

  if (!c->high)
    return FALSE;
  if (page < 1)
    page = 1;
  if (e->key == TERM_KEY_UP)
    HtkTableSelect(c, c->value - 1);
  else if (e->key == TERM_KEY_DOWN)
    HtkTableSelect(c, c->value + 1);
  else if (e->key == TERM_KEY_PGUP)
    HtkTableSelect(c, c->value - page);
  else if (e->key == TERM_KEY_PGDN)
    HtkTableSelect(c, c->value + page);
  else if (e->key == TERM_KEY_HOME)
    HtkTableSelect(c, 0);
  else if (e->key == TERM_KEY_END)
    HtkTableSelect(c, c->high - 1);
  else
    return FALSE;
  return TRUE;
}
