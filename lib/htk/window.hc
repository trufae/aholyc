// Window manager: double-line framed windows with shadows on a ▒ desktop,
// draggable by their title bar, with [_] minimize, [□] maximize/restore and
// [■] close boxes at the right of the title, plus classic tile/cascade
// arrangement of the whole stack. Minimized windows become buttons on a
// one-row taskbar along the bottom of the terminal.

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
  if (htk_popup && HtkOwnerWindow(HtkPopupRoot->link) == w)
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

U0 HtkWindowMinimize(HtkCtl *w)
{
  if (!w || w->minimized)
    return;
  if (htk_popup && HtkOwnerWindow(HtkPopupRoot->link) == w)
    HtkPopupClose;
  w->minimized = TRUE;
  if (htk_focus && HtkOwnerWindow(htk_focus) == w)
    htk_focus = NULL;
  htk_dirty = TRUE;
}

U0 HtkWindowRestore(HtkCtl *w)
{
  if (!w)
    return;
  w->minimized = FALSE;
  HtkWindowRaise(w);
  htk_dirty = TRUE;
}

// Toggle between the saved rect and the whole desktop above the taskbar.
U0 HtkWindowMaximize(HtkCtl *w)
{
  if (!w)
    return;
  if (w->maximized) {
    w->x = w->rx;
    w->y = w->ry;
    w->w = w->rw;
    w->h = w->rh;
  } else {
    w->rx = w->x;
    w->ry = w->y;
    w->rw = w->w;
    w->rh = w->h;
  }
  w->maximized = !w->maximized;
  htk_dirty = TRUE;
}

// Snap the window to one half of the desktop: HTK_TILE_* side.
U0 HtkWindowTile(HtkCtl *w, I64 side)
{
  I64 desk = TermHeight - HtkTaskbarHeight;

  if (!w)
    return;
  w->maximized = FALSE;
  w->x = 0;
  w->y = 0;
  w->w = TermWidth;
  w->h = desk;
  if (side == HTK_TILE_LEFT || side == HTK_TILE_RIGHT)
    w->w = TermWidth / 2;
  else
    w->h = desk / 2;
  if (side == HTK_TILE_RIGHT)
    w->x = TermWidth - w->w;
  if (side == HTK_TILE_BOTTOM)
    w->y = desk - w->h;
  htk_dirty = TRUE;
}

// Title bar context menu, shared by every window: the items carry the
// target window in ->link while the popup is open.
HtkCtl *htk_wm_menu;
HtkCtl *htk_wm_maximize;

U0 HtkWmMinimize(HtkCtl *item)
{
  HtkWindowMinimize(item->link);
}

U0 HtkWmMaximize(HtkCtl *item)
{
  HtkWindowMaximize(item->link);
}

U0 HtkWmClose(HtkCtl *item)
{
  HtkWindowClose(item->link);
}

U0 HtkWmTile(HtkCtl *item)
{
  HtkWindowTile(item->link, item->value);
}

HtkCtl *HtkWmItem(HtkCtl *menu, U8 *label, U0 (*fn)(HtkCtl *c), I64 value=0)
{
  HtkCtl *item = HtkMenuItem(menu, label);

  item->changed = fn;
  item->value = value;
  return item;
}

U0 HtkWindowMenuOpen(HtkCtl *w, I64 x, I64 y)
{
  HtkCtl *tile, *k;

  if (!htk_wm_menu) {
    htk_wm_menu = HtkContextMenuNew;
    HtkWmItem(htk_wm_menu, "Minimize", &HtkWmMinimize);
    htk_wm_maximize = HtkWmItem(htk_wm_menu, "Maximize", &HtkWmMaximize);
    tile = HtkSubMenu(htk_wm_menu, "Tile");
    HtkWmItem(tile, "Left", &HtkWmTile, HTK_TILE_LEFT);
    HtkWmItem(tile, "Right", &HtkWmTile, HTK_TILE_RIGHT);
    HtkWmItem(tile, "Top", &HtkWmTile, HTK_TILE_TOP);
    HtkWmItem(tile, "Bottom", &HtkWmTile, HTK_TILE_BOTTOM);
    HtkWmItem(htk_wm_menu, "Close", &HtkWmClose);
  }
  if (w->maximized)
    HtkSetText(htk_wm_maximize, "Restore");
  else
    HtkSetText(htk_wm_maximize, "Maximize");
  k = htk_wm_menu->kids;
  while (k) {
    k->link = w;
    if (k->kind == HTK_MENU) {
      HtkCtl *t = k->kids;
      while (t) {
        t->link = w;
        t = t->sib;
      }
    }
    k = k->sib;
  }
  HtkMenuOpenAt(htk_wm_menu, x, y);
}

// Drag one corner to (x, y); the opposite corner stays put and the window
// never shrinks below 12x4.
U0 HtkWindowResizeCorner(HtkCtl *w, I64 corner, I64 x, I64 y)
{
  I64 right = w->x + w->w - 1, bottom = w->y + w->h - 1;

  if (corner == HTK_CORNER_TL || corner == HTK_CORNER_BL) {
    if (x > right - 11)
      x = right - 11;
    w->x = x;
    w->w = right - x + 1;
  } else {
    w->w = x - w->x + 1;
    if (w->w < 12)
      w->w = 12;
  }
  if (corner == HTK_CORNER_TL || corner == HTK_CORNER_TR) {
    if (y > bottom - 3)
      y = bottom - 3;
    w->y = y;
    w->h = bottom - y + 1;
  } else {
    w->h = y - w->y + 1;
    if (w->h < 4)
      w->h = 4;
  }
  htk_dirty = TRUE;
}

U0 HtkWindowLayout(HtkCtl *w)
{
  HtkCtl *content = HtkWindowContent(w);
  I64 desk = TermHeight - HtkTaskbarHeight;
  I64 bar = 0;

  if (w->maximized) {  // follows terminal resizes and the taskbar
    w->x = 0;
    w->y = 0;
    w->w = TermWidth;
    w->h = desk;
  }
  // Windows may hang off any edge; only the title row must stay reachable:
  // on a desktop row, with at least the [_][□][■] boxes and a grab handle
  // on screen.
  if (w->x < 12 - w->w)
    w->x = 12 - w->w;
  if (w->x > TermWidth - 12)
    w->x = TermWidth - 12;
  if (w->y > desk - 1)
    w->y = desk - 1;
  if (w->y < 0)
    w->y = 0;
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
  mid = w->x + (w->w - 10 - HtkRunes(w->text) - 2) / 2;
  if (mid < w->x + 1)
    mid = w->x + 1;
  HtkChr(mid, w->y, ' ', HTK_C_FG, HTK_C_BG);
  HtkStr(mid + 1, w->y, w->text, HTK_C_FG, HTK_C_BG, TERM_BOLD);
  HtkChr(mid + 1 + HtkRunes(w->text), w->y, ' ', HTK_C_FG, HTK_C_BG);
  // Title boxes, Windows order: minimize, maximize/restore, close.
  mid = w->x + w->w - 10;
  HtkStr(mid, w->y, "[_][", frame, HTK_C_BG);
  if (w->maximized)
    HtkChr(mid + 4, w->y, HTK_R_RESTORE, HTK_C_ACCENT, HTK_C_BG);
  else
    HtkChr(mid + 4, w->y, HTK_R_MAX, HTK_C_ACCENT, HTK_C_BG);
  HtkStr(mid + 5, w->y, "][", frame, HTK_C_BG);
  HtkChr(mid + 7, w->y, HTK_R_CLOSE, HTK_C_BTN_BG, HTK_C_BG);
  HtkStr(mid + 8, w->y, "]", frame, HTK_C_BG);
  if (!w->maximized) {
    HtkShade(w->x + 2, w->y + w->h, w->w, 1);
    HtkShade(w->x + w->w, w->y + 1, 2, w->h);
  }
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

// Bottom row: one [ title ] button per minimized window; returns the window
// under column x when hit-testing (x >= 0), NULL when only drawing.
HtkCtl *HtkTaskbar(I64 x, Bool draw)
{
  HtkCtl *w = htk_windows;
  I64 at = 0, y = TermHeight - 1, width;

  if (!HtkTaskbarHeight)
    return NULL;
  if (draw)
    HtkRect(0, y, TermWidth, 1, ' ', HTK_C_FG, HTK_C_BG);
  while (w) {
    if (w->minimized) {
      width = HtkRunes(w->text) + 4;
      if (x >= at && x < at + width)
        return w;
      if (draw) {
        HtkStr(at, y, "[ ", HTK_C_DIM, HTK_C_BG);
        HtkStr(at + 2, y, w->text, HTK_C_FG, HTK_C_BG, TERM_BOLD);
        HtkStr(at + 2 + HtkRunes(w->text), y, " ]", HTK_C_DIM, HTK_C_BG);
      }
      at += width + 1;
    }
    w = w->sib;
  }
  return NULL;
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
  rh = (TermHeight - HtkTaskbarHeight) / rows;
  w = htk_windows;
  while (w) {
    w->maximized = FALSE;
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
    w->maximized = FALSE;
    w->x = 2 + i * 3;
    w->y = 1 + i;
    w->w = TermWidth * 3 / 4;
    w->h = TermHeight * 3 / 4;
    i++;
    w = w->sib;
  }
  htk_dirty = TRUE;
}
