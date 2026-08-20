// Dispatch and the event loop: kind switches for measure/layout/draw/keys,
// focus traversal, mouse routing, timers, and the modal helper.

// Per-kind behavior, one row per HTK_* kind: measure into pw/ph, lay out
// the kids, draw, handle a key.  A zero entry leaves pw/ph alone (a canvas
// keeps its creation size), draws nothing, or declines the key.
#define HTK_KINDS 31
I64 htk_measure[HTK_KINDS], htk_layout[HTK_KINDS];
I64 htk_draw[HTK_KINDS], htk_key[HTK_KINDS];

U0 HtkOps(I64 kind, I64 measure, I64 layout, I64 draw, I64 key)
{
  htk_measure[kind] = measure;
  htk_layout[kind] = layout;
  htk_draw[kind] = draw;
  htk_key[kind] = key;
}

U0 HtkOpsInit()
{
  HtkOps(HTK_BOX, &HtkBoxMeasure, &HtkBoxLayout, &HtkKidsDraw, 0);
  HtkOps(HTK_TOOLBAR, &HtkBoxMeasure, &HtkBoxLayout, &HtkToolbarDraw, 0);
  HtkOps(HTK_GRID, &HtkGridMeasure, &HtkGridLayout, &HtkKidsDraw, 0);
  HtkOps(HTK_SPLIT, &HtkSplitMeasure, &HtkSplitLayout, &HtkSplitDraw, 0);
  HtkOps(HTK_SCROLL, &HtkScrollMeasure, &HtkScrollLayout, &HtkScrollDraw,
    &HtkScrollKey);
  HtkOps(HTK_GROUP, &HtkGroupMeasure, &HtkGroupLayout, &HtkGroupDraw, 0);
  HtkOps(HTK_TAB, &HtkTabMeasure, &HtkTabLayout, &HtkTabDraw, &HtkTabKey);
  HtkOps(HTK_LABEL, &HtkLabelMeasure, 0, &HtkLabelDraw, 0);
  HtkOps(HTK_STATUS, &HtkStatusMeasure, 0, &HtkLabelDraw, 0);
  HtkOps(HTK_SEP, &HtkSepMeasure, 0, &HtkSepDraw, 0);
  HtkOps(HTK_BUTTON, &HtkButtonMeasure, 0, &HtkButtonDraw, &HtkButtonKey);
  HtkOps(HTK_MENUITEM, &HtkButtonMeasure, 0, 0, 0);
  HtkOps(HTK_ENTRY, &HtkEntryMeasure, 0, &HtkEntryDraw, &HtkEntryKey);
  HtkOps(HTK_MULTILINE, &HtkMultilineMeasure, 0, &HtkMultilineDraw,
    &HtkMultilineKey);
  HtkOps(HTK_CHECKBOX, &HtkCheckboxMeasure, 0, &HtkCheckboxDraw,
    &HtkCheckboxKey);
  HtkOps(HTK_RADIO, &HtkRadioMeasure, 0, &HtkRadioDraw, &HtkRadioKey);
  HtkOps(HTK_SLIDER, &HtkSliderMeasure, 0, &HtkSliderDraw, &HtkSliderKey);
  HtkOps(HTK_PROGRESS, &HtkSliderMeasure, 0, &HtkProgressDraw, 0);
  HtkOps(HTK_SPIN, &HtkSpinMeasure, 0, &HtkSpinDraw, &HtkSpinKey);
  HtkOps(HTK_COMBO, &HtkComboMeasure, 0, &HtkComboDraw, &HtkComboKey);
  HtkOps(HTK_TABLE, &HtkTableMeasure, 0, &HtkTableDraw, &HtkTableKey);
  HtkOps(HTK_TREE, &HtkTreeMeasure, 0, &HtkTreeDraw, &HtkTreeKey);
  HtkOps(HTK_CANVAS, 0, 0, &HtkCanvasDraw, 0);
  HtkOps(HTK_TERM, &HtkTermMeasure, 0, &HtkTermDraw, &HtkTermKey);
  HtkOps(HTK_SWITCH, &HtkSwitchMeasure, 0, &HtkSwitchDraw, &HtkSwitchKey);
}

U0 HtkMeasureCtl(HtkCtl *c)
{
  U0 (*measure)(HtkCtl *c) = htk_measure[c->kind];

  if (c->hidden) {
    c->pw = 0;
    c->ph = 0;
  } else if (measure)
    measure(c);
}

U0 HtkLayoutCtl(HtkCtl *c)
{
  U0 (*layout)(HtkCtl *c) = htk_layout[c->kind];

  if (!c->hidden && layout)
    layout(c);
}

U0 HtkDrawCtl(HtkCtl *c)
{
  U0 (*draw)(HtkCtl *c) = htk_draw[c->kind];

  if (!c->hidden && draw)
    draw(c);
}

Bool HtkKeyCtl(HtkCtl *c, CTermEvent *e)
{
  Bool (*key)(HtkCtl *c, CTermEvent *e) = htk_key[c->kind];

  if (c->disabled || !key)
    return FALSE;
  return key(c, e);
}

// Deepest visible control containing the point; later siblings win.
HtkCtl *HtkHit(HtkCtl *c, I64 x, I64 y)
{
  HtkCtl *k, *hit, *best = NULL;

  if (c->hidden || x < c->x || y < c->y ||
    x >= c->x + c->w || y >= c->y + c->h)
    return NULL;
  k = c->kids;
  while (k) {
    hit = HtkHit(k, x, y);
    if (hit)
      best = hit;
    k = k->sib;
  }
  if (best)
    return best;
  return c;
}

U0 HtkSetFocus(HtkCtl *c)
{
  if (htk_focus == c)
    return;
  htk_focus = c;
  htk_dirty = TRUE;
}

#define HTK_FOCUS_MAX 128

U0 HtkCollectFocus(HtkCtl *c, HtkCtl **list, I64 *n)
{
  HtkCtl *k;

  if (!c || c->hidden || *n >= HTK_FOCUS_MAX)
    return;
  if (c->focusable && !c->disabled) {
    list[*n] = c;
    (*n)++;
  }
  k = c->kids;
  while (k) {
    if (k->kind != HTK_MENU)
      HtkCollectFocus(k, list, n);
    k = k->sib;
  }
}

U0 HtkFocusMove(I64 dir)
{
  HtkCtl *list[HTK_FOCUS_MAX];
  HtkCtl *top = HtkTop;
  I64 n = 0, i, at = -1;

  if (!top)
    return;
  HtkCollectFocus(HtkWindowContent(top), list, &n);
  if (!n) {
    HtkSetFocus(NULL);
    return;
  }
  for (i = 0; i < n; i++)
    if (list[i] == htk_focus)
      at = i;
  at += dir;
  if (at >= n)
    at = 0;
  if (at < 0)
    at = n - 1;
  HtkSetFocus(list[at]);
}

// Make sure focus points into the active window.
U0 HtkEnsureFocus()
{
  HtkCtl *top = HtkTop;

  if (!top) {
    htk_focus = NULL;
    return;
  }
  if (htk_focus && HtkOwnerWindow(htk_focus) == top && !htk_focus->hidden)
    return;
  htk_focus = NULL;
  HtkFocusMove(1);
}

// Popups form a chain: a submenu is pushed on top of the popup that opened
// it and both stay visible; ->parent points down the chain.
U0 HtkPopupClose()
{
  HtkCtl *below;

  while (htk_popup) {
    below = htk_popup->parent;
    Free(htk_popup);
    htk_popup = below;
  }
  htk_dirty = TRUE;
}

U0 HtkPopupOpen(HtkCtl *popup)
{
  HtkPopupClose;
  popup->parent = NULL;
  htk_popup = popup;
  htk_dirty = TRUE;
}

U0 HtkPopupPush(HtkCtl *popup)
{
  popup->parent = htk_popup;
  htk_popup = popup;
  htk_dirty = TRUE;
}

// Close only the topmost popup (back out of a submenu).
U0 HtkPopupPop()
{
  HtkCtl *below;

  if (!htk_popup)
    return;
  below = htk_popup->parent;
  Free(htk_popup);
  htk_popup = below;
  htk_dirty = TRUE;
}

HtkCtl *HtkPopupRoot()
{
  HtkCtl *p = htk_popup;

  while (p && p->parent)
    p = p->parent;
  return p;
}

U0 HtkPopupDrawChain(HtkCtl *p)
{
  if (p->parent)
    HtkPopupDrawChain(p->parent);
  HtkPickDraw(p);
}

U0 HtkHookAdd(I64 delay_ms, I64 repeat_ms, I64 fn, I64 a, I64 b)
{
  HtkHook *h = CAlloc(sizeof(HtkHook));

  h->due = TermMs + delay_ms;
  h->ms = repeat_ms;
  h->fn = fn;
  h->a = a;
  h->b = b;
  h->next = htk_hooks;
  htk_hooks = h;
}

U0 HtkRunHooks()
{
  HtkHook *h = htk_hooks;
  HtkHook **prev = &htk_hooks;
  I64 now = TermMs;
  I64 call;

  while (h) {
    if (h->due <= now) {
      call = h->fn;
      if (h->ms) {
        h->due = now + h->ms;
        if (call)
          call(h->a, h->b);
        prev = &h->next;
        h = h->next;
      } else {
        // Unlink before the call: the callback may HtkHookAdd (re-arm),
        // which prepends to the list this node may head.
        *prev = h->next;
        if (call)
          call(h->a, h->b);
        Free(h);
        h = *prev;
      }
    } else {
      prev = &h->next;
      h = h->next;
    }
  }
}

I64 HtkNextTimeout()
{
  HtkHook *h = htk_hooks;
  I64 now = TermMs;
  I64 best = -1;

  while (h) {
    if (best < 0 || h->due - now < best) {
      best = h->due - now;
      if (best < 0)
        best = 0;
    }
    h = h->next;
  }
  return best;
}

U0 HtkRedraw()
{
  HtkCtl *w = htk_windows;

  HtkEnsureFocus;
  TermShowCursor(FALSE);
  HtkClipAll;
  HtkDesktopDraw;
  while (w) {
    if (!w->minimized) {
      HtkClipAll;
      HtkWindowLayout(w);
      htk_paint_dim = htk_dim_inactive && w != HtkTop;
      HtkWindowDraw(w);
      htk_paint_dim = FALSE;
    }
    w = w->sib;
  }
  HtkClipAll;
  HtkTaskbar(-1, TRUE);
  if (htk_popup)
    HtkPopupDrawChain(htk_popup);
  TermCommit;
}

U0 HtkCanvasMouse(HtkCtl *c, CTermEvent *e)
{
  if (!c)
    return;
  c->mouse_x = e->x - c->x;
  c->mouse_y = e->y - c->y;
  c->mouse_button = e->button;
  c->mouse_pressed = e->pressed;
  c->mouse_motion = e->motion;
  if (c->mouse_x < 0)
    c->mouse_x = 0;
  if (c->mouse_y < 0)
    c->mouse_y = 0;
  if (c->mouse_x >= c->w)
    c->mouse_x = c->w - 1;
  if (c->mouse_y >= c->h)
    c->mouse_y = c->h - 1;
  HtkFire(c);
}

U0 HtkWindowMouse(HtkCtl *w, CTermEvent *e)
{
  HtkCtl *content = HtkWindowContent(w);
  HtkCtl *hit;
  Bool press = e->pressed && !e->motion && e->button == TERM_MOUSE_LEFT;
  Bool right = e->pressed && !e->motion && e->button == TERM_MOUSE_RIGHT;

  if (right && e->y == w->y) {  // title bar: window manager menu
    HtkWindowMenuOpen(w, e->x, e->y + 1);
    return;
  }
  // Any of the four frame corners (two cells wide) resizes; the rest of the
  // title row drags. Maximized windows do neither.
  if (press && !w->maximized && (e->y == w->y || e->y == w->y + w->h - 1) &&
    (e->x <= w->x + 1 || e->x >= w->x + w->w - 2)) {
      htk_drag = w;
      if (e->y == w->y && e->x <= w->x + 1)
        htk_drag_resize = HTK_CORNER_TL;
      else if (e->y == w->y)
        htk_drag_resize = HTK_CORNER_TR;
      else if (e->x <= w->x + 1)
        htk_drag_resize = HTK_CORNER_BL;
      else
        htk_drag_resize = HTK_CORNER_BR;
      return;
    }
  if (e->y == w->y) {
    I64 box = e->x - (w->x + w->w - 10);  // [_][□][■] at the right
    if (!press)
      return;
    if (box >= 0 && box < 3) {
      HtkWindowMinimize(w);
      return;
    }
    if (box >= 3 && box < 6) {
      HtkWindowMaximize(w);
      return;
    }
    if (box >= 6 && box < 9) {
      HtkWindowClose(w);
      return;
    }
    if (w->maximized)
      return;
    htk_drag = w;
    htk_drag_resize = 0;
    htk_drag_dx = e->x - w->x;
    htk_drag_dy = e->y - w->y;
    return;
  }
  if (HtkWindowHasMenu(w) && e->y == w->y + 1) {
    hit = HtkMenubarHit(w, e->x);
    if (hit && press)
      HtkMenuOpen(hit);
    return;
  }
  if (!content)
    return;
  hit = HtkHit(content, e->x, e->y);
  if (right) {  // nearest context menu up the tree, the window's last
    HtkCtl *owner = hit;
    if (!owner)
      owner = w;
    while (owner && !owner->menu)
      owner = owner->parent;
    if (owner)
      HtkMenuOpenAt(owner->menu, e->x, e->y);
    return;
  }
  if (!hit)
    return;
  if (press && hit->focusable && !hit->disabled)
    HtkSetFocus(hit);
  if (hit->disabled)
    return;
  switch (hit->kind) {
  case HTK_BUTTON:
    if (press)
      HtkFire(hit);
    break;
  case HTK_CHECKBOX:
    if (press) {
      hit->value = !hit->value;
      HtkFire(hit);
    }
    break;
  case HTK_SWITCH:
    if (press)
      HtkSwitchSet(hit, !hit->value);
    break;
  case HTK_RADIO:
    if (press && e->y - hit->y < HtkKidCount(hit)) {
      hit->value = e->y - hit->y;
      HtkFire(hit);
    }
    break;
  case HTK_SLIDER:
    if (press) {
      HtkSliderMouse(hit, e->x);
      htk_drag = hit;
    }
    break;
  case HTK_CANVAS:
    if (e->pressed || e->motion) {
      HtkCanvasMouse(hit, e);
      if (e->pressed && e->button == TERM_MOUSE_LEFT)
        htk_drag = hit;
    }
    break;
  case HTK_SPIN:
    if (press) {
      if (e->x < hit->x + hit->w / 2)
        hit->value--;
      else
        hit->value++;
      if (hit->value < hit->low)
        hit->value = hit->low;
      if (hit->value > hit->high)
        hit->value = hit->high;
      HtkFire(hit);
    }
    break;
  case HTK_COMBO:
    if (press)
      HtkComboOpen(hit);
    break;
  case HTK_ENTRY:
    if (press) {  // click places the cursor; dragging selects from there
      HtkEntryCursorAt(hit, e->x);
      hit->anchor = hit->cursor;
      htk_drag = hit;
    }
    break;
  case HTK_MULTILINE:
    if (press) {
      HtkMultilineCursorAt(hit, e->x, e->y);
      hit->anchor = hit->cursor;
      htk_drag = hit;
    }
    break;
  case HTK_TABLE:
    if (press && e->y > hit->y)
      HtkTableSelect(hit, hit->top + e->y - hit->y - 1);
    break;
  case HTK_TREE:
    if (press)
      HtkTreeClick(hit, hit->top + e->y - hit->y);
    break;
  case HTK_TAB:
    if (press && e->y == hit->y) {
      HtkCtl *page = hit->kids;
      I64 i = 0;
      while (page) {
        if (e->x >= page->x && e->x < page->x + page->w) {
          hit->value = i;
          htk_dirty = TRUE;
        }
        page = page->sib;
        i++;
      }
    }
    break;
  }
  if (e->button == TERM_MOUSE_WHEEL_UP || e->button == TERM_MOUSE_WHEEL_DOWN) {
    HtkCtl *seek = hit;
    I64 step = 1;
    if (e->button == TERM_MOUSE_WHEEL_UP)
      step = -1;
    while (seek && seek->kind != HTK_SCROLL && seek->kind != HTK_TABLE &&
      seek->kind != HTK_TREE)
      seek = seek->parent;
    if (seek) {
      if (seek->kind == HTK_TABLE)
        HtkTableSelect(seek, seek->value + step);
      else if (seek->kind == HTK_TREE)
        HtkTreeSelect(seek, HtkTreeIndexOf(seek, seek->link) + step);
      else {
        seek->top += step * 2;
        if (seek->top < 0)
          seek->top = 0;
        htk_dirty = TRUE;
      }
    }
  }
}

U0 HtkMouse(CTermEvent *e)
{
  HtkCtl *w;
  HtkCtl *at = NULL;

  // A release (or wheel) always ends the active drag.
  if (!e->pressed) {
    if (htk_drag && htk_drag->kind == HTK_CANVAS)
      HtkCanvasMouse(htk_drag, e);
    if (htk_drag && (htk_drag->kind == HTK_ENTRY ||
      htk_drag->kind == HTK_MULTILINE) && htk_drag->anchor == htk_drag->cursor)
      htk_drag->anchor = -1;  // a plain click selects nothing
    htk_drag = NULL;
    htk_drag_resize = 0;
  }
  if (htk_drag && e->pressed) {
    if (htk_drag->kind == HTK_WINDOW) {
      if (htk_drag_resize)
        HtkWindowResizeCorner(htk_drag, htk_drag_resize, e->x, e->y);
      else {
        htk_drag->x = e->x - htk_drag_dx;
        htk_drag->y = e->y - htk_drag_dy;
      }
      htk_dirty = TRUE;
    } else if (htk_drag->kind == HTK_SLIDER)
      HtkSliderMouse(htk_drag, e->x);
    else if (htk_drag->kind == HTK_CANVAS)
      HtkCanvasMouse(htk_drag, e);
    else if (htk_drag->kind == HTK_ENTRY)
      HtkEntryCursorAt(htk_drag, e->x);  // extends the selection
    else if (htk_drag->kind == HTK_MULTILINE)
      HtkMultilineCursorAt(htk_drag, e->x, e->y);
    return;
  }
  if (htk_popup) {
    // Topmost popup under the pointer wins; clicking a lower one in the
    // chain folds the submenus above it first.
    HtkCtl *p = htk_popup;
    while (p && !(e->x >= p->x && e->x < p->x + p->w &&
      e->y >= p->y && e->y < p->y + p->h))
      p = p->parent;
    if (p) {
      if (p != htk_popup && !(e->pressed && !e->motion))
        return;  // releases and hovers never fold an open submenu
      while (htk_popup != p)
        HtkPopupPop;
      HtkPickMouse(p, e);
      return;
    }
    if (e->pressed && !e->motion)
      HtkPopupClose;
    return;
  }
  // Window bar: [App] opens the menu, a click on a button restores that
  // window, a right click opens its window menu, dragging scrolls the strip.
  if (htk_bar_dragging) {
    if (e->pressed && e->motion) {
      if (e->x != htk_bar_drag_x) {
        HtkTaskbarScroll(htk_bar_drag_x - e->x);
        htk_bar_drag_x = e->x;
        htk_bar_drag_moved = TRUE;
      }
      return;
    }
    if (!e->pressed) {
      htk_bar_dragging = FALSE;
      if (!htk_bar_drag_moved)
        HtkWindowRestore(HtkTaskbar(e->x, FALSE));  // it was a plain click
      return;
    }
  }
  if (e->pressed && !e->motion && HtkTaskbarHeight &&
    e->y == TermHeight - 1) {
      if (HTK_BAR_APP && e->x < HTK_BAR_APP)
        HtkAppMenuOpen(0, TermHeight - 1);
      else if (e->button == TERM_MOUSE_RIGHT) {
        w = HtkTaskbar(e->x, FALSE);
        if (w)
          HtkWindowMenuOpen(w, e->x, TermHeight - 1);
      } else if (e->button == TERM_MOUSE_LEFT) {
        htk_bar_dragging = TRUE;
        htk_bar_drag_x = e->x;
        htk_bar_drag_moved = FALSE;
      } else if (e->button == TERM_MOUSE_WHEEL_UP)
        HtkTaskbarScroll(-4);
      else if (e->button == TERM_MOUSE_WHEEL_DOWN)
        HtkTaskbarScroll(4);
      return;
    }
  w = htk_windows;
  while (w) {
    if (!w->minimized && e->x >= w->x && e->x < w->x + w->w &&
      e->y >= w->y && e->y < w->y + w->h)
      at = w;
    w = w->sib;
  }
  if (!at) {
    if (e->pressed && !e->motion && e->button == TERM_MOUSE_RIGHT)
      HtkAppMenuOpen(e->x, e->y);  // desktop context menu
    return;
  }
  // A press on a background window raises it and still counts: the title
  // starts dragging right away and controls react without a second click.
  if (at != HtkTop && e->pressed && !e->motion)
    HtkWindowRaise(at);
  HtkWindowMouse(at, e);
}

U0 HtkKey(CTermEvent *e)
{
  HtkCtl *top = HtkTop;

  if (htk_popup) {
    HtkPickKey(htk_popup, e);
    return;
  }
  if (e->key == TERM_KEY_TAB &&
    !(htk_focus && htk_focus->kind == HTK_TERM && !(e->mods & TERM_MOD_SHIFT))) {
      if (e->mods & TERM_MOD_SHIFT)  // a terminal keeps plain Tab
        HtkFocusMove(-1);
      else
        HtkFocusMove(1);
      return;
    }
  if (e->key == TERM_KEY_F10 && top) {
    HtkCtl *m = top->kids;
    while (m && m->kind != HTK_MENU)
      m = m->sib;
    if (m) {
      HtkMenubarHit(top, -1);  // refresh menu positions
      HtkMenuOpen(m);
    }
    return;
  }
  if (htk_focus && HtkKeyCtl(htk_focus, e))
    return;
  if (!top)
    return;
  if (e->key == TERM_KEY_ENTER && top->link) {
    HtkFire(top->link);  // window default button
    return;
  }
  if (e->key == TERM_KEY_ESCAPE && top->low)
    HtkWindowClose(top);
}

Bool HtkStep(I64 timeout)
{
  CTermEvent e;

  HtkRunHooks;
  if (htk_dirty) {
    htk_dirty = FALSE;
    HtkRedraw;
  }
  if (!TermPollEvent(&e, timeout))
    return FALSE;
  if (e.type == TERM_EVENT_RESIZE)
    htk_dirty = TRUE;
  else if (e.type == TERM_EVENT_KEY)
    HtkKey(&e);
  else if (e.type == TERM_EVENT_MOUSE)
    HtkMouse(&e);
  return TRUE;
}

Bool HtkInit()
{
  if (htk_started)
    return TRUE;
  if (!TermInit)
    return FALSE;
  HtkThemeDefault;
  TermMouse;
  htk_started = TRUE;
  htk_dirty = TRUE;
  return TRUE;
}

U0 HtkFini()
{
  if (!htk_started)
    return;
  TermFini;
  htk_started = FALSE;
}

U0 HtkQuit()
{
  htk_running = FALSE;
}

I64 HtkStepTimeout()
{
  I64 wait = HtkNextTimeout;

  if (htk_dirty)
    return 0;
  return wait;
}

// ^C ends the loop unless a terminal control has focus and takes it.
Bool HtkInterrupted()
{
  HtkTermInterrupt;
  return TermInterrupted(FALSE);
}

U0 HtkMain()
{
  htk_running = TRUE;
  while (htk_running && htk_windows && !HtkInterrupted)
    HtkStep(HtkStepTimeout);
  htk_running = FALSE;
}

// Nested loop for dialogs: runs until the window is dismissed.
U0 HtkModal(HtkCtl *w)
{
  while (!w->closed && htk_windows && !HtkInterrupted)
    HtkStep(HtkStepTimeout);
}
