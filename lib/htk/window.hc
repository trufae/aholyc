// Window manager: double-line framed windows with shadows on a ▒ desktop,
// draggable by their title bar, with [_] minimize, [□] maximize/restore and
// [■] close boxes at the right of the title, plus classic tile/cascade
// arrangement of the whole stack. Minimized windows become buttons on a
// one-row taskbar along the bottom of the terminal.

extern I64 time(I64 *now);

I64 HtkWindowLimit(I64 value, I64 min, I64 max)
{
  if (value < min)
    value = min;
  if (max > 0 && value > max)
    value = max;
  return value;
}

I64 HtkWindowControlCount(HtkCtl *w)
{
  I64 count = 0;

  if (w->controls & HTK_WINDOW_MINIMIZE)
    count++;
  if (w->controls & HTK_WINDOW_MAXIMIZE)
    count++;
  if (w->controls & HTK_WINDOW_CLOSE)
    count++;
  return count;
}
extern I32 *localtime(I64 *now);

// "HH:MM" from the C runtime clock; struct tm starts sec, min, hour.
U0 HtkClockText(U8 *out)
{
  I64 now = time(NULL);
  I32 *tm = localtime(&now);

  StrPrint(out, "%02d:%02d", tm[2], tm[1]);
}

HtkCtl *HtkWindowNew(U8 *title, I64 w, I64 h)
{
  HtkCtl *win = HtkNew(HTK_WINDOW);
  HtkCtl *prior = htk_windows;
  I64 n = 0;

  w = HtkWindowLimit(w, 12, 0);
  h = HtkWindowLimit(h, 4, 0);
  HtkSetText(win, title);
  win->controls = HTK_WINDOW_DEFAULT_CONTROLS;
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
  HtkListAppend(&htk_windows, win);
  HtkWindowRaise(win);  // insert below any existing always-on-top windows
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
  HtkCtl **at;

  if (!w)
    return;
  HtkListUnlink(&htk_windows, w);
  if (w->always_on_top)
    HtkListAppend(&htk_windows, w);
  else {
    at = &htk_windows;
    while (*at && !(*at)->always_on_top)
      at = &(*at)->sib;
    w->sib = *at;
    *at = w;
  }
  htk_dirty = TRUE;
}

// Cycle visible windows in z-order.  Raising the chosen window also gives it
// normal keyboard focus, matching Alt-Tab desktop behavior.
U0 HtkWindowCycle(I64 direction)
{
  HtkCtl *w = htk_windows, *top = HtkTop;
  HtkCtl *first = NULL, *last = NULL, *prev = NULL, *next = NULL, *target;

  if (htk_modal) {
    HtkWindowRaise(htk_modal);
    HtkEnsureFocus;
    return;
  }
  while (w) {
    if (!w->minimized) {
      if (!first)
        first = w;
      if (w == top)
        prev = last;
      else if (last == top)
        next = w;
      last = w;
    }
    w = w->sib;
  }
  if (direction < 0) {
    target = prev;
    if (!target)
      target = last;
  } else {
    target = next;
    if (!target)
      target = first;
  }
  if (target) {
    HtkWindowRaise(target);
    htk_focus = NULL;
    HtkEnsureFocus;
  }
}

U0 HtkWindowSetAlwaysOnTop(HtkCtl *w, Bool on)
{
  if (!w || w->always_on_top == on)
    return;
  w->always_on_top = on;
  HtkWindowRaise(w);
}

U0 HtkWindowSetControls(HtkCtl *w, I64 controls)
{
  if (!w || w->kind != HTK_WINDOW)
    return;
  w->controls = controls & HTK_WINDOW_DEFAULT_CONTROLS;
  htk_dirty = TRUE;
}

// Set the interactive bounds of a window.  A zero maximum means no upper
// limit; HTK always retains a 12x4 frame as the absolute minimum.
U0 HtkWindowSetSizeLimits(HtkCtl *w, I64 min_w=12, I64 min_h=4,
  I64 max_w=0, I64 max_h=0)
{
  if (!w || w->kind != HTK_WINDOW)
    return;
  if (min_w < 12)
    min_w = 12;
  if (min_h < 4)
    min_h = 4;
  if (max_w > 0 && max_w < min_w)
    max_w = min_w;
  if (max_h > 0 && max_h < min_h)
    max_h = min_h;
  w->min_w = min_w;
  w->min_h = min_h;
  w->max_w = max_w;
  w->max_h = max_h;
  if (!w->maximized) {
    w->w = HtkWindowLimit(w->w, min_w, max_w);
    w->h = HtkWindowLimit(w->h, min_h, max_h);
  }
  htk_dirty = TRUE;
}

U0 HtkWindowClose(HtkCtl *w)
{
  if (!w || w->closed)
    return;
  if (htk_popup && HtkOwnerWindow(HtkPopupRoot->link) == w)
    HtkPopupClose;
  w->closed = TRUE;
  HtkTermClosed(w);
  HtkListUnlink(&htk_windows, w);
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
HtkCtl *htk_wm_minimize, *htk_wm_maximize, *htk_wm_always_on_top, *htk_wm_close;

U0 HtkWmMinimize(HtkCtl *item)
{
  HtkCtl *w = item->link;

  if (w->minimized)  // from the window bar the same entry restores
    HtkWindowRestore(w);
  else
    HtkWindowMinimize(w);
}

U0 HtkWmMaximize(HtkCtl *item)
{
  HtkWindowMaximize(item->link);
}

U0 HtkWmAlwaysOnTop(HtkCtl *item)
{
  HtkWindowSetAlwaysOnTop(item->link, !item->link->always_on_top);
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

  if (!w || !(w->controls & HTK_WINDOW_MENU))
    return;
  if (!htk_wm_menu) {
    htk_wm_menu = HtkContextMenuNew;
    htk_wm_minimize = HtkWmItem(htk_wm_menu, "Minimize", &HtkWmMinimize);
    htk_wm_maximize = HtkWmItem(htk_wm_menu, "Maximize", &HtkWmMaximize);
    htk_wm_always_on_top = HtkWmItem(htk_wm_menu, "Always on top",
      &HtkWmAlwaysOnTop);
    tile = HtkSubMenu(htk_wm_menu, "Tile");
    HtkWmItem(tile, "Left", &HtkWmTile, HTK_TILE_LEFT);
    HtkWmItem(tile, "Right", &HtkWmTile, HTK_TILE_RIGHT);
    HtkWmItem(tile, "Top", &HtkWmTile, HTK_TILE_TOP);
    HtkWmItem(tile, "Bottom", &HtkWmTile, HTK_TILE_BOTTOM);
    htk_wm_close = HtkWmItem(htk_wm_menu, "Close", &HtkWmClose);
  }
  if (w->maximized)
    HtkSetText(htk_wm_maximize, "Restore");
  else
    HtkSetText(htk_wm_maximize, "Maximize");
  if (w->minimized)
    HtkSetText(htk_wm_minimize, "Restore");
  else
    HtkSetText(htk_wm_minimize, "Minimize");
  if (w->always_on_top)
    HtkSetText(htk_wm_always_on_top, "SometimesOnTop");
  else
    HtkSetText(htk_wm_always_on_top, "AlwaysOnTop");
  htk_wm_minimize->disabled = !(w->controls & HTK_WINDOW_MINIMIZE);
  htk_wm_maximize->disabled = !(w->controls & HTK_WINDOW_MAXIMIZE);
  htk_wm_close->disabled = !(w->controls & HTK_WINDOW_CLOSE);
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
  I64 min_w = w->min_w, min_h = w->min_h;

  if (min_w < 12)
    min_w = 12;
  if (min_h < 4)
    min_h = 4;

  if (corner == HTK_CORNER_TL || corner == HTK_CORNER_BL ||
    corner == HTK_EDGE_LEFT) {
    w->w = HtkWindowLimit(right - x + 1, min_w, w->max_w);
    w->x = right - w->w + 1;
  } else if (corner == HTK_CORNER_TR || corner == HTK_CORNER_BR ||
    corner == HTK_EDGE_RIGHT) {
    w->w = HtkWindowLimit(x - w->x + 1, min_w, w->max_w);
  }
  if (corner == HTK_CORNER_TL || corner == HTK_CORNER_TR) {
    w->h = HtkWindowLimit(bottom - y + 1, min_h, w->max_h);
    w->y = bottom - w->h + 1;
  } else if (corner == HTK_CORNER_BL || corner == HTK_CORNER_BR ||
    corner == HTK_EDGE_BOTTOM) {
    w->h = HtkWindowLimit(y - w->y + 1, min_h, w->max_h);
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
  I64 mid, controls, at, reserve, title_left;

  if (active)
    frame = HTK_C_FRAME;
  HtkRect(w->x, w->y, w->w, w->h, ' ', HTK_C_FG, HTK_C_BG);
  HtkFrame(w->x, w->y, w->w, w->h, active, frame, HTK_C_BG);
  controls = HtkWindowControlCount(w);
  if (w->controls & HTK_WINDOW_MENU)
    HtkStr(w->x + 2, w->y, "[=]", frame, HTK_C_BG);
  reserve = controls * 3 + 1;
  mid = w->x + (w->w - reserve - HtkRunes(w->text) - 2) / 2;
  title_left = w->x + 1;
  if (w->controls & HTK_WINDOW_MENU)
    title_left = w->x + 5;
  if (mid < title_left)
    mid = title_left;
  HtkChr(mid, w->y, ' ', HTK_C_FG, HTK_C_BG);
  HtkStr(mid + 1, w->y, w->text, HTK_C_FG, HTK_C_BG, TERM_BOLD);
  HtkChr(mid + 1 + HtkRunes(w->text), w->y, ' ', HTK_C_FG, HTK_C_BG);
  // Title boxes, in Windows order: minimize, maximize/restore, close.
  at = w->x + w->w - 1 - controls * 3;
  if (w->controls & HTK_WINDOW_MINIMIZE) {
    HtkStr(at, w->y, "[_]", frame, HTK_C_BG);
    at += 3;
  }
  if (w->controls & HTK_WINDOW_MAXIMIZE) {
    HtkChr(at, w->y, '[', frame, HTK_C_BG);
    if (w->maximized)
      HtkChr(at + 1, w->y, HTK_R_RESTORE, HTK_C_ACCENT, HTK_C_BG);
    else
      HtkChr(at + 1, w->y, HTK_R_MAX, HTK_C_ACCENT, HTK_C_BG);
    HtkChr(at + 2, w->y, ']', frame, HTK_C_BG);
    at += 3;
  }
  if (w->controls & HTK_WINDOW_CLOSE) {
    HtkChr(at, w->y, '[', frame, HTK_C_BG);
    HtkChr(at + 1, w->y, HTK_R_CLOSE, HTK_C_BTN_BG, HTK_C_BG);
    HtkChr(at + 2, w->y, ']', frame, HTK_C_BG);
  }
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

#ifdef HTK_NODESK
#define HTK_BAR_APP 0
#else
#define HTK_BAR_APP 6  // "[App] " at the left of the window bar
#endif

I64 htk_bar_scroll;     // first hidden columns of the button strip
I64 htk_bar_total;      // width of the whole strip, from the last draw
Bool htk_bar_dragging;  // pointer held on the bar (scrolls the strip)
I64 htk_bar_drag_x;
Bool htk_bar_drag_moved;

// Bottom row: [App], one [ title ] button per minimized window (a strip
// that scrolls by dragging), and the clock at the right. Returns the window
// under column x when hit-testing (x >= 0), NULL when only drawing or when
// x is on [App]/clock.
HtkCtl *HtkTaskbar(I64 x, Bool draw)
{
  HtkCtl *w = htk_windows;
  I64 at = HTK_BAR_APP - htk_bar_scroll, y = TermHeight - 1, width;
  I64 right = TermWidth;
  U8 clock[8];

  if (!HtkTaskbarHeight)
    return NULL;
  if (htk_bar_clock)
    right = TermWidth - 7;
  if (draw) {
    HtkRect(0, y, TermWidth, 1, ' ', HTK_C_BAR_FG, HTK_C_BAR_BG);
    if (htk_bar_clock) {
      HtkClockText(clock);
      HtkStr(TermWidth - 6, y, clock, HTK_C_BAR_FG, HTK_C_BAR_BG, TERM_BOLD);
    }
    HtkClipSet(HTK_BAR_APP, y, right - HTK_BAR_APP, 1);
  }
  while (w) {
    if (w->minimized) {
      width = HtkRunes(w->text) + 4;
      if (x >= HTK_BAR_APP && x < right && x >= at && x < at + width)
        return w;
      if (draw) {
        HtkStr(at, y, "[ ", HTK_C_DIM, HTK_C_BAR_BG);
        HtkStr(at + 2, y, w->text, HTK_C_BAR_FG, HTK_C_BAR_BG, TERM_BOLD);
        HtkStr(at + 2 + HtkRunes(w->text), y, " ]", HTK_C_DIM, HTK_C_BAR_BG);
      }
      at += width + 1;
    }
    w = w->sib;
  }
  if (draw) {
    htk_bar_total = at + htk_bar_scroll - HTK_BAR_APP;
    HtkClipAll;
    if (HTK_BAR_APP) {  // drawn last: the strip scrolls underneath
      HtkRect(0, y, HTK_BAR_APP, 1, ' ', TERM_BRIGHT_WHITE, TERM_BLACK);
      HtkStr(0, y, "[", TERM_GRAY, TERM_BLACK);
      HtkStr(1, y, "App", TERM_BRIGHT_WHITE, TERM_BLACK, TERM_BOLD);
      HtkStr(4, y, "] ", TERM_GRAY, TERM_BLACK);
    }
  }
  return NULL;
}

// Scroll the button strip by delta columns, within its bounds.
U0 HtkTaskbarScroll(I64 delta)
{
  I64 visible = TermWidth - HTK_BAR_APP, limit;

  if (htk_bar_clock)
    visible -= 7;
  limit = htk_bar_total - visible;
  if (limit < 0)
    limit = 0;
  htk_bar_scroll += delta;
  if (htk_bar_scroll > limit)
    htk_bar_scroll = limit;
  if (htk_bar_scroll < 0)
    htk_bar_scroll = 0;
  htk_dirty = TRUE;
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
