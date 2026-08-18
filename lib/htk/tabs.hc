// Tab control: HTK_TABPAGE kids carry the label and one content kid; value
// is the active page.  The content sits inside a single-line frame whose
// top row doubles as the tab strip.

HtkCtl *HtkTabNew()
{
  HtkCtl *c = HtkNew(HTK_TAB);

  c->focusable = TRUE;
  c->expand = TRUE;
  return c;
}

U0 HtkTabAdd(HtkCtl *c, U8 *label, HtkCtl *child)
{
  HtkCtl *page = HtkNew(HTK_TABPAGE);

  HtkSetText(page, label);
  HtkAdd(c, page);
  HtkAdd(page, child);
}

U0 HtkTabMeasure(HtkCtl *c)
{
  HtkCtl *page = c->kids;
  I64 strip = 0;

  c->pw = 0;
  c->ph = 0;
  while (page) {
    if (page->kids) {
      HtkMeasureCtl(page->kids);
      if (page->kids->pw > c->pw)
        c->pw = page->kids->pw;
      if (page->kids->ph > c->ph)
        c->ph = page->kids->ph;
    }
    strip += HtkRunes(page->text) + 3;
    page = page->sib;
  }
  if (strip > c->pw)
    c->pw = strip;
  c->pw += 2;
  c->ph += 2;
}

// Only the active page participates in hit testing and focus.
U0 HtkTabPages(HtkCtl *c)
{
  HtkCtl *page = c->kids;
  I64 i = 0;

  while (page) {
    page->hidden = i != c->value;
    page = page->sib;
    i++;
  }
}

U0 HtkTabLayout(HtkCtl *c)
{
  HtkCtl *page = HtkKidAt(c, c->value);

  HtkTabPages(c);
  if (!page || !page->kids)
    return;
  page->kids->x = c->x + 1;
  page->kids->y = c->y + 1;
  page->kids->w = c->w - 2;
  page->kids->h = c->h - 2;
  HtkLayoutCtl(page->kids);
}

U0 HtkTabDraw(HtkCtl *c)
{
  HtkCtl *page = c->kids;
  I64 i = 0, x = c->x + 2, fg, attr;

  HtkFrame(c->x, c->y, c->w, c->h, FALSE, HTK_C_DIM, HTK_C_BG);
  while (page) {
    fg = HTK_C_DIM;
    attr = 0;
    if (i == c->value) {
      fg = HTK_C_FG;
      attr = TERM_BOLD;
      if (HtkFocused(c))
        fg = HTK_C_FIELD_BG;
    }
    page->x = x;
    page->w = HtkRunes(page->text) + 2;
    HtkChr(x, c->y, ' ', fg, HTK_C_BG);
    HtkStr(x + 1, c->y, page->text, fg, HTK_C_BG, attr);
    HtkChr(x + page->w - 1, c->y, ' ', fg, HTK_C_BG);
    x += page->w + 1;
    page = page->sib;
    i++;
  }
  page = HtkKidAt(c, c->value);
  if (page && page->kids)
    HtkDrawCtl(page->kids);
}

Bool HtkTabKey(HtkCtl *c, CTermEvent *e)
{
  I64 count = HtkKidCount(c);

  if (e->key == TERM_KEY_LEFT && c->value > 0)
    c->value--;
  else if (e->key == TERM_KEY_RIGHT && c->value < count - 1)
    c->value++;
  else
    return FALSE;
  htk_dirty = TRUE;
  return TRUE;
}
