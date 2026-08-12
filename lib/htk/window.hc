// Window manager: double-line framed windows with shadows on a ▒ desktop,
// draggable by their title bar, closable at the [■] box, plus classic
// tile/cascade arrangement of the whole stack.

HtkCtl *HtkWindowNew(U8 *title, I64 w, I64 h)
{
  HtkCtl *win = HtkNew(HTK_WINDOW);
  HtkCtl *prior = htk_windows;
  I64 n = 0;

  HtkSetText(win, title);
  while (prior) {
    n++;
    prior = prior->sib;
  }
  if (w > TermWidth)
    w = TermWidth;
  if (h > TermHeight)
    h = TermHeight;
  win->w = w;
  win->h = h;
  win->x = (TermWidth - w) / 2 + n * 2;
  win->y = (TermHeight - h) / 2 + n;
  if (win->x + w > TermWidth)
    win->x = TermWidth - w;
  if (win->y + h > TermHeight)
    win->y = TermHeight - h;
  if (!htk_windows)
    htk_windows = win;
  else {
    prior = htk_windows;
    while (prior->sib)
      prior = prior->sib;
    prior->sib = win;
  }
  htk_dirty = TRUE;
  return win;
}

HtkCtl *HtkWindowContent(HtkCtl *w)
{
  HtkCtl *k = w->kids;

  while (k && k->kind == HTK_MENU)
    k = k->sib;
  return k;
}

HtkCtl *HtkOwnerWindow(HtkCtl *c)
{
  while (c && c->parent)
    c = c->parent;
  return c;
}

U0 HtkWindowRaise(HtkCtl *w)
{
  HtkCtl *k = htk_windows;

  if (!w || w == HtkTop)
    return;
  if (htk_windows == w)
    htk_windows = w->sib;
  else {
    while (k && k->sib != w)
      k = k->sib;
    if (!k)
      return;
    k->sib = w->sib;
  }
  k = htk_windows;
  if (!k)
    htk_windows = w;
  else {
    while (k->sib)
      k = k->sib;
    k->sib = w;
  }
  w->sib = NULL;
  htk_dirty = TRUE;
}

U0 HtkWindowClose(HtkCtl *w)
{
  HtkCtl *k = htk_windows;

  if (!w || w->closed)
    return;
  if (htk_popup && HtkOwnerWindow(htk_popup->link) == w)
    HtkPopupClose;
  w->closed = TRUE;
  if (htk_windows == w)
    htk_windows = w->sib;
  else {
    while (k && k->sib != w)
      k = k->sib;
    if (k)
      k->sib = w->sib;
  }
  w->sib = NULL;
  if (htk_focus && HtkOwnerWindow(htk_focus) == w)
    htk_focus = NULL;
  htk_dirty = TRUE;
}

U0 HtkWindowLayout(HtkCtl *w)
{
  HtkCtl *content = HtkWindowContent(w);
  I64 bar = 0;

  if (w->x < 0)
    w->x = 0;
  if (w->y < 0)
    w->y = 0;
  if (w->x + w->w > TermWidth)
    w->x = TermWidth - w->w;
  if (w->y + w->h > TermHeight)
    w->y = TermHeight - w->h;
  if (!content)
    return;
  if (HtkWindowHasMenu(w))
    bar = 1;
  HtkMeasureCtl(content);
  content->x = w->x + 2;
  content->y = w->y + 1 + bar;
  content->w = w->w - 4;
  content->h = w->h - 2 - bar;
  HtkLayoutCtl(content);
}

U0 HtkWindowDraw(HtkCtl *w)
{
  HtkCtl *content = HtkWindowContent(w);
  Bool active = w == HtkTop;
  I64 frame = HTK_C_DIM;
  I64 mid;

  if (active)
    frame = HTK_C_FRAME;
  HtkRect(w->x, w->y, w->w, w->h, ' ', HTK_C_FG, HTK_C_BG);
  HtkFrame(w->x, w->y, w->w, w->h, active, frame, HTK_C_BG);
  mid = w->x + (w->w - HtkRunes(w->text) - 2) / 2;
  HtkChr(mid, w->y, ' ', HTK_C_FG, HTK_C_BG);
  HtkStr(mid + 1, w->y, w->text, HTK_C_FG, HTK_C_BG, TERM_BOLD);
  HtkChr(mid + 1 + HtkRunes(w->text), w->y, ' ', HTK_C_FG, HTK_C_BG);
  HtkStr(w->x + 2, w->y, "[", frame, HTK_C_BG);
  HtkChr(w->x + 3, w->y, HTK_R_CLOSE, HTK_C_BTN_BG, HTK_C_BG);
  HtkStr(w->x + 4, w->y, "]", frame, HTK_C_BG);
  HtkShade(w->x + 2, w->y + w->h, w->w, 1);
  HtkShade(w->x + w->w, w->y + 1, 2, w->h);
  // Everything inside stays inside: clip to the interior.
  HtkClipSet(w->x + 1, w->y + 1, w->w - 2, w->h - 2);
  if (HtkWindowHasMenu(w))
    HtkMenubarDraw(w);
  if (content)
    HtkDrawCtl(content);
}

U0 HtkDesktopDraw()
{
  HtkRect(0, 0, TermWidth, TermHeight, HTK_R_MED, HTK_C_DESK_FG, HTK_C_DESK_BG);
}

// Arrange every window edge to edge in a near-square grid.
U0 HtkTile()
{
  HtkCtl *w = htk_windows;
  I64 n = 0, cols = 1, rows, i = 0, cw, rh;

  while (w) {
    n++;
    w = w->sib;
  }
  if (!n)
    return;
  while (cols * cols < n)
    cols++;
  rows = (n + cols - 1) / cols;
  cw = TermWidth / cols;
  rh = TermHeight / rows;
  w = htk_windows;
  while (w) {
    w->x = i % cols * cw;
    w->y = i / cols * rh;
    w->w = cw;
    w->h = rh;
    i++;
    w = w->sib;
  }
  htk_dirty = TRUE;
}

U0 HtkCascade()
{
  HtkCtl *w = htk_windows;
  I64 i = 0;

  while (w) {
    w->x = 2 + i * 3;
    w->y = 1 + i;
    w->w = TermWidth * 3 / 4;
    w->h = TermHeight * 3 / 4;
    i++;
    w = w->sib;
  }
  htk_dirty = TRUE;
}
