// Native Intuition + GadTools backend, AmigaOS 3.x (V39 or later).
#include "amiga_api.hc"

class UiAmigaData
{
  U8 *text;
  UiCtl *owner, *parent, *menus, *selected;
  UiAmigaList *list;
  U32 *labels;
  U32 handle, gadgets, visual, menustrip;
  I64 value, min, max, x, y, w, h, deadline, interval;
  Bool vertical, expand, hidden, disabled, dirty, once;
};

UiCtl *ui_amiga_window, *ui_amiga_canvas;
Bool ui_amiga_running, ui_amiga_initialized;
U32 ui_amiga_bases[4];
UiCtl *ui_amiga_modal, *ui_amiga_drag;
U0 UiAmigaMenus(UiCtl *w);
U0 UiAmigaOwn(UiCtl *c, UiCtl *w);
U0 UiAmigaSet(UiCtl *c, U32 tag, I64 value);

UiAmigaData *UiAmiga(UiCtl *c) { return c->native(UiAmigaData *); }

I64 UiAmigaChoose(Bool test, I64 yes, I64 no) { if (test) return yes; return no; }

U0 UiAmigaUnsupported(U8 *feature)
{
  "Amiga UI: %s is not supported by GadTools\n", feature;
  throw('UI');
}

UiCtl *UiAmigaNew(I64 kind, U8 *text="")
{
  UiAmigaData *a = CAlloc(sizeof(UiAmigaData));
  UiCtl *c = UiCtlNew(kind, a);
  a->text = StrNew(text);
  a->owner = ui_amiga_window;
  a->vertical = TRUE;
  a->value = -1;
  return c;
}

U0 UiAmigaDirty(UiCtl *c)
{
  UiCtl *w = UiAmiga(c)->owner;
  if (w)
    UiAmiga(w)->dirty = TRUE;
}

U0 UiInit()
{
  U8 *names[4];
  U32 *bases[4];
  I64 i;
  if (ui_amiga_initialized)
    return;
  names[0] = "intuition.library"; bases[0] = &IntuitionBase;
  names[1] = "graphics.library"; bases[1] = &GfxBase;
  names[2] = "gadtools.library"; bases[2] = &GadToolsBase;
  names[3] = "asl.library"; bases[3] = &AslBase;
  for (i = 0; i < 4; i++) {
    ui_amiga_bases[i] = *bases[i];
    *bases[i] = OpenLibrary(names[i], 39);
    if (!*bases[i]) {
      *bases[i] = ui_amiga_bases[i];
      while (i > 0) {
        i--;
        CloseLibrary(*bases[i]);
        *bases[i] = ui_amiga_bases[i];
      }
      "Amiga UI: requires AmigaOS 3.x libraries\n";
      throw('UI');
    }
  }
  ui_amiga_initialized = TRUE;
}

I64 UiAmigaNow()
{
  U32 seconds, micros;
  CurrentTime(&seconds, &micros);
  return seconds * 1000 + micros / 1000;
}

U0 UiAmigaAttach(UiCtl *parent, UiCtl *c)
{
  if (UiAmiga(c)->parent)
    throw('UI');
  UiAmiga(c)->parent = parent;
  UiAmigaOwn(c, UiAmiga(parent)->owner);
  UiKidAdd(parent, c);
  UiAmigaDirty(parent);
}

U0 UiAmigaOwn(UiCtl *c, UiCtl *w)
{
  UiCtl *k;
  UiAmiga(c)->owner = w;
  for (k = c->kids; k; k = k->sib)
    UiAmigaOwn(k, w);
}

Bool UiAmigaVisible(UiCtl *c)
{
  UiCtl *parent, *k;
  I64 index;
  while (c) {
    if (UiAmiga(c)->hidden) return FALSE;
    parent = UiAmiga(c)->parent;
    if (parent && parent->kind == UI_TAB) {
      index = 0;
      for (k = parent->kids; k && k != c; k = k->sib) index++;
      if (index != UiAmiga(parent)->value) return FALSE;
    }
    c = parent;
  }
  return TRUE;
}

U0 UiAmigaMeasure(UiCtl *c)
{
  UiAmigaData *a = UiAmiga(c), *b;
  UiCtl *k;
  I64 n = 0, widths[64], heights[64], cols = 0, rows = 0;
  if (a->hidden) { a->w = 0; a->h = 0; return; }
  a->w = 80; a->h = 20;
  switch (c->kind) {
    case UI_BOX: case UI_TOOLBAR: case UI_SPLIT: case UI_GROUP:
      a->w = 0; a->h = 0;
      for (k = c->kids; k; k = k->sib) {
        UiAmigaMeasure(k); b = UiAmiga(k);
        if (b->hidden) goto next_box;
        if (a->vertical) { a->w = MaxI64(a->w, b->w); a->h += b->h; }
        else { a->w += b->w; a->h = MaxI64(a->h, b->h); }
        n++;
next_box:
      }
      if (n > 1) {
        if (a->vertical) a->h += (n - 1) * 4;
        else a->w += (n - 1) * 6;
      }
      if (c->kind == UI_GROUP) { a->w += 12; a->h += 24; }
      break;
    case UI_GRID:
      for (k = c->kids; k; k = k->sib) {
        if (k->col < 0 || k->col >= 64 || k->row < 0 || k->row >= 64) throw('UI');
        UiAmigaMeasure(k); b = UiAmiga(k);
        widths[k->col] = MaxI64(widths[k->col], b->w);
        heights[k->row] = MaxI64(heights[k->row], b->h);
        cols = MaxI64(cols, k->col + 1); rows = MaxI64(rows, k->row + 1);
      }
      a->w = 0; a->h = 0;
      for (n = 0; n < cols; n++) a->w += widths[n] + 6;
      for (n = 0; n < rows; n++) a->h += heights[n] + 4;
      break;
    case UI_LABEL: case UI_STATUS: case UI_BUTTON:
      a->w = StrLen(a->text) * 8 + 16;
      if (c->kind != UI_BUTTON) a->h = 14;
      break;
    case UI_ENTRY: a->w = 140; break;
    case UI_CHECKBOX: a->w = StrLen(a->text) * 8 + 34; a->h = 14; break;
    case UI_SLIDER: a->w = 160; a->h = 16; break;
    case UI_PROGRESS: a->w = 160; a->h = 14; break;
    case UI_SEP: a->w = 8; a->h = 4; break;
    case UI_CANVAS: a->w = c->w; a->h = c->h; break;
    case UI_RADIO:
      a->h = 0;
      for (k = c->kids; k; k = k->sib) {
        a->w = MaxI64(a->w, StrLen(UiAmiga(k)->text) * 8 + 30); a->h += 14;
      }
      break;
    case UI_TABLE: case UI_TREE: case UI_MULTILINE: a->w = 240; a->h = 100; break;
    case UI_TAB:
      a->w = 100; a->h = 20;
      for (k = c->kids; k; k = k->sib) {
        UiAmigaMeasure(k); a->w = MaxI64(a->w, UiAmiga(k)->w);
        a->h = MaxI64(a->h, UiAmiga(k)->h + 24);
      }
      break;
  }
}

U0 UiAmigaPlace(UiCtl *c, I64 x, I64 y, I64 w, I64 h)
{
  UiAmigaData *a = UiAmiga(c), *b;
  UiCtl *k;
  I64 total = 0, count = 0, flexible = 0, extra, size, pos;
  I64 widths[64], heights[64], cols = 0, rows = 0, i, xx, yy;
  a->x = x; a->y = y; a->w = MaxI64(w, 1); a->h = MaxI64(h, 1);
  if (c->kind == UI_GROUP) { x += 6; y += 18; w -= 12; h -= 24; }
  if (c->kind == UI_BOX || c->kind == UI_TOOLBAR || c->kind == UI_GROUP || c->kind == UI_SPLIT) {
    for (k = c->kids; k; k = k->sib) {
      b = UiAmiga(k);
      if (!b->hidden) {
        total += UiAmigaChoose(a->vertical, b->h, b->w);
        count++;
        if (b->expand || c->kind == UI_SPLIT) flexible++;
      }
    }
    extra = MaxI64(0, UiAmigaChoose(a->vertical, h, w) - total - MaxI64(0, count - 1) * UiAmigaChoose(a->vertical, 4, 6));
    pos = UiAmigaChoose(a->vertical, y, x);
    for (k = c->kids; k; k = k->sib) {
      b = UiAmiga(k);
      if (b->hidden) goto next_place;
      size = UiAmigaChoose(a->vertical, b->h, b->w);
      if (flexible && (b->expand || c->kind == UI_SPLIT)) size += extra / flexible;
      if (a->vertical) UiAmigaPlace(k, x, pos, w, size);
      else UiAmigaPlace(k, pos, y, size, h);
      pos += size + UiAmigaChoose(a->vertical, 4, 6);
next_place:
    }
  } else if (c->kind == UI_GRID) {
    for (k = c->kids; k; k = k->sib) {
      b = UiAmiga(k);
      widths[k->col] = MaxI64(widths[k->col], b->w);
      heights[k->row] = MaxI64(heights[k->row], b->h);
      cols = MaxI64(cols, k->col + 1); rows = MaxI64(rows, k->row + 1);
    }
    total = 0;
    for (i = 0; i < cols; i++) total += widths[i] + 6;
    extra = MaxI64(0, w - total);
    if (cols) widths[cols - 1] += extra;
    for (k = c->kids; k; k = k->sib) {
      xx = x; yy = y;
      for (i = 0; i < k->col; i++) xx += widths[i] + 6;
      for (i = 0; i < k->row; i++) yy += heights[i] + 4;
      UiAmigaPlace(k, xx, yy, widths[k->col], heights[k->row]);
    }
  } else if (c->kind == UI_TAB) {
    i = 0;
    for (k = c->kids; k; k = k->sib) {
      if (i == a->value) UiAmigaPlace(k, x, y + 24, w, h - 24);
      i++;
    }
  }
}

U0 UiAmigaListFree(UiAmigaData *a)
{
  UiAmigaNode *n, *next;
  if (a->list) {
    n = a->list->head(UiAmigaNode *);
    while (n->next) {
      next = n->next(UiAmigaNode *); Free(n->text); Free(n); n = next;
    }
    Free(a->list); a->list = NULL;
  }
  Free(a->labels); a->labels = NULL;
}

U0 UiAmigaListAdd(UiAmigaData *a, U8 *text, UiCtl *control=NULL)
{
  UiAmigaNode *n = CAlloc(sizeof(UiAmigaNode));
  n->text = StrNew(text); n->name = n->text; n->control = control;
  n->next = &a->list->tail; n->previous = a->list->previous;
  *(n->previous(U32 *)) = n;
  a->list->previous = n;
}

U0 UiAmigaTreeList(UiAmigaData *a, UiCtl *parent, I64 depth=0)
{
  UiCtl *k;
  U8 *text, *indent = MAlloc(depth * 2 + 1);
  MemSet(indent, ' ', depth * 2); indent[depth * 2] = 0;
  for (k = parent->kids; k; k = k->sib) {
    text = MStrPrint("%s%s", indent, UiAmiga(k)->text);
    UiAmigaListAdd(a, text, k); Free(text);
    UiAmigaTreeList(a, k, depth + 1);
  }
  Free(indent);
}

U0 UiAmigaListBuild(UiCtl *c)
{
  UiAmigaData *a = UiAmiga(c);
  UiCtl *k;
  I64 i, count = 0, row, col;
  U8 *text, *next, *p, *q;
  UiAmigaListFree(a);
  if (c->kind == UI_COMBO || c->kind == UI_RADIO || c->kind == UI_TAB) {
    for (k = c->kids; k; k = k->sib) count++;
    a->labels = CAlloc((count + 1) * 4);
    i = 0;
    for (k = c->kids; k; k = k->sib) a->labels[i++] = UiAmiga(k)->text;
    return;
  }
  a->list = CAlloc(sizeof(UiAmigaList));
  a->list->head = &a->list->tail; a->list->previous = &a->list->head;
  if (c->kind == UI_TREE) UiAmigaTreeList(a, c);
  else if (c->kind == UI_TABLE) {
    for (row = 0; row < c->row; row++) {
      text = StrNew(""); col = 0;
      for (k = c->kids; k; k = k->sib) {
        next = MStrPrint("%s%s%s", text, UiAmigaChoose(col, "  |  ", ""), UiTableCell(c, row, col));
        Free(text); text = next; col++;
      }
      UiAmigaListAdd(a, text); Free(text);
    }
  } else {
    p = a->text;
    while (*p) {
      q = p; while (*q && *q != '\n') q++;
      text = MAlloc(q - p + 1); MemCpy(text, p, q - p); text[q - p] = 0;
      UiAmigaListAdd(a, text); Free(text);
      p = q; if (*p) p++;
    }
  }
}

U8 *UiAmigaBuild(UiCtl *c, U8 *previous, UiAmigaData *window)
{
  UiAmigaData *a = UiAmiga(c);
  UiAmigaWindow *win = window->handle(UiAmigaWindow *);
  UiAmigaScreen *screen = win->screen(UiAmigaScreen *);
  UiAmigaNewGadget ng;
  UiAmigaTag tags[12];
  UiCtl *k;
  I64 kind = -1, n = 0, i = 0;
  if (a->hidden) return previous;
  switch (c->kind) {
    case UI_LABEL: case UI_STATUS: kind = 13; tags[n].tag = UA_GT + 11; tags[n++].value = a->text; break;
    case UI_BUTTON: kind = 1; break;
    case UI_ENTRY: kind = 12;
      tags[n].tag = UA_GT + 45; tags[n++].value = a->text;
      tags[n].tag = UA_GT + 46; tags[n++].value = 4096; break;
    case UI_CHECKBOX: kind = 2; tags[n].tag = UA_GT + 4; tags[n++].value = a->value; break;
    case UI_SLIDER: kind = 11;
      tags[n].tag = UA_GT + 38; tags[n++].value = a->min;
      tags[n].tag = UA_GT + 39; tags[n++].value = a->max;
      tags[n].tag = UA_GT + 40; tags[n++].value = a->value; break;
    case UI_SPIN: kind = 3; tags[n].tag = UA_GT + 47; tags[n++].value = a->value; break;
    case UI_COMBO: case UI_RADIO: case UI_TAB:
      UiAmigaListBuild(c); kind = 7;
      if (!a->labels[0]) return previous;
      if (c->kind == UI_RADIO) {
        kind = 5; tags[n].tag = UA_GT + 61; tags[n++].value = 6;
      }
      tags[n].tag = UA_GT + UiAmigaChoose(kind == 5, 9, 14); tags[n++].value = a->labels;
      tags[n].tag = UA_GT + UiAmigaChoose(kind == 5, 10, 15); tags[n++].value = MaxI64(0, a->value); break;
    case UI_TABLE: case UI_TREE: case UI_MULTILINE:
      UiAmigaListBuild(c); kind = 4;
      tags[n].tag = UA_GT + 6; tags[n++].value = a->list;
      tags[n].tag = UA_GT + 54; tags[n++].value = a->value;
      tags[n].tag = UA_GT + 53; tags[n++].value = NULL;
      tags[n].tag = UA_GT + 7; tags[n++].value = c->kind == UI_MULTILINE; break;
  }
  if (kind >= 0) {
    ng.x = a->x; ng.y = a->y; ng.w = a->w; ng.h = a->h;
    if (c->kind == UI_TAB) ng.h = 20;
    if (c->kind == UI_TABLE) { ng.y += 14; ng.h = MaxI64(20, ng.h - 14); }
    ng.font = screen->font; ng.visual = window->visual; ng.user = c;
    ng.flags = 16;
    if (c->kind == UI_CHECKBOX) { ng.flags = 2; ng.w = 26; ng.h = 11; }
    if (c->kind == UI_BUTTON || c->kind == UI_CHECKBOX) ng.text = a->text;
    tags[n].tag = UA_DISABLED; tags[n++].value = a->disabled;
    a->handle = CreateGadgetA(kind, previous, &ng, tags);
    if (!a->handle) throw('UI');
    previous = a->handle;
  }
  if (c->kind == UI_BOX || c->kind == UI_GRID || c->kind == UI_GROUP || c->kind == UI_TOOLBAR || c->kind == UI_SPLIT || c->kind == UI_TAB) {
    for (k = c->kids; k; k = k->sib) {
      if (c->kind != UI_TAB || i == a->value) previous = UiAmigaBuild(k, previous, window);
      i++;
    }
  }
  return previous;
}

U0 UiAmigaPaint(UiCtl *c)
{
  UiAmigaData *a = UiAmiga(c), *window;
  UiAmigaWindow *win;
  UiCtl *k, *saved;
  I64 i = 0, length;
  U8 *text, *next;
  UiAmigaTag tags[2];
  if (a->hidden || !a->owner) return;
  window = UiAmiga(a->owner); if (!window->handle) return;
  win = window->handle(UiAmigaWindow *);
  tags[0].tag = UA_GT + 52; tags[0].value = window->visual;
  if (c->kind == UI_CANVAS) {
    saved = ui_amiga_canvas; ui_amiga_canvas = c; UiFireClick(c); ui_amiga_canvas = saved;
  } else if (c->kind == UI_PROGRESS) {
    DrawBevelBoxA(win->port, a->x, a->y, a->w, a->h, tags);
    SetAPen(win->port, 0); RectFill(win->port, a->x + 2, a->y + 2, a->x + a->w - 3, a->y + a->h - 3);
    if (a->value > 0) {
      SetAPen(win->port, 1); RectFill(win->port, a->x + 2, a->y + 2, a->x + 1 + (a->w - 4) * a->value / 100, a->y + a->h - 3);
    }
  } else if (c->kind == UI_SEP) {
    SetAPen(win->port, 1); Move(win->port, a->x, a->y + 1); Draw(win->port, a->x + a->w - 1, a->y + 1);
  } else if (c->kind == UI_GROUP || c->kind == UI_TABLE) {
    if (c->kind == UI_GROUP) {
      DrawBevelBoxA(win->port, a->x, a->y, a->w, a->h, tags);
      text = StrNew(a->text);
    } else {
      text = StrNew("");
      for (k = c->kids; k; k = k->sib) {
        next = MStrPrint("%s%s%s", text, UiAmigaChoose(*text, "  |  ", ""), UiAmiga(k)->text);
        Free(text); text = next;
      }
    }
    length = MinI64(StrLen(text), MaxI64(0, (a->w - 12) / 8));
    SetAPen(win->port, 1); SetDrMd(win->port, 1); Move(win->port, a->x + 6, a->y + 10);
    Text(win->port, text, length); Free(text);
  }
  if (c->kind == UI_BOX || c->kind == UI_GRID || c->kind == UI_GROUP || c->kind == UI_TOOLBAR || c->kind == UI_SPLIT || c->kind == UI_TAB) {
    for (k = c->kids; k; k = k->sib) {
      if (c->kind != UI_TAB || i == a->value) UiAmigaPaint(k);
      i++;
    }
  }
}

U0 UiAmigaSnapshot(UiCtl *c)
{
  UiAmigaData *a = UiAmiga(c);
  UiAmigaGadget *g;
  UiAmigaString *s;
  if (!a->handle) return;
  g = a->handle(UiAmigaGadget *);
  if (c->kind == UI_ENTRY || c->kind == UI_SPIN) {
    s = g->special(UiAmigaString *);
    if (c->kind == UI_ENTRY) { Free(a->text); a->text = StrNew(s->buffer); }
    else {
      a->value = MaxI64(a->min, MinI64(a->max, s->number));
      if (a->value != s->number) UiAmigaSet(c, UA_GT + 47, a->value);
    }
  } else if (c->kind == UI_CHECKBOX) a->value = (g->flags & 0x80) != 0;
}

U0 UiAmigaRebuild(UiCtl *w)
{
  UiAmigaData *a = UiAmiga(w), *b;
  UiAmigaWindow *win = a->handle(UiAmigaWindow *);
  UiCtl *c;
  U8 *last;
  if (!a->handle) return;
  for (c = ui_ctls; c; c = c->reg) {
    b = UiAmiga(c);
    if (c->kind != UI_WINDOW && b && b->owner == w) { UiAmigaSnapshot(c); b->handle = 0; }
  }
  if (a->gadgets) { RemoveGList(win, a->gadgets, -1); FreeGadgets(a->gadgets); a->gadgets = 0; }
  SetAPen(win->port, 0);
  RectFill(win->port, win->left, win->top, win->width - win->right - 1, win->height - win->bottom - 1);
  if (w->kids) {
    UiAmigaMeasure(w->kids);
    UiAmigaPlace(w->kids, win->left + 6, win->top + 4,
      win->width - win->left - win->right - 12, win->height - win->top - win->bottom - 8);
    last = CreateContext(&a->gadgets); if (!last) throw('UI');
    UiAmigaBuild(w->kids, last, a);
    AddGList(win, a->gadgets, -1, -1, NULL);
    RefreshGList(a->gadgets, win, NULL, -1);
    GT_RefreshWindow(win, NULL); UiAmigaPaint(w->kids);
  }
  UiAmigaMenus(w);
  a->dirty = FALSE;
}

UiCtl *UiWindowNew(U8 *title, I64 w=480, I64 h=320)
{
  UiCtl *c = UiAmigaNew(UI_WINDOW, title);
  c->w = w; c->h = h;
  UiAmiga(c)->owner = c;
  ui_amiga_window = c;
  return c;
}

U0 UiWindowSetChild(UiCtl *w, UiCtl *c)
{
  if (w->kids) throw('UI');
  UiAmigaAttach(w, c); UiAmigaOwn(c, w);
}

U0 UiShow(UiCtl *w)
{
  UiAmigaData *a = UiAmiga(w);
  UiAmigaTag tags[8];
  UiAmigaWindow *win;
  if (a->handle) return;
  UiInit;
  tags[0].tag = UA_WA + 3; tags[0].value = w->w;
  tags[1].tag = UA_WA + 4; tags[1].value = w->h;
  tags[2].tag = UA_WA + 11; tags[2].value = a->text;
  tags[3].tag = UA_WA + 8; tags[3].value = 0x124F;
  tags[4].tag = UA_WA + 7;
  tags[4].value = UA_RESIZE | UA_REFRESH | UA_BUTTONS | UA_MOTION | UA_DOWN | UA_UP | UA_MENU | UA_CLOSE | UA_TICK;
  tags[5].tag = UA_WA + 0x2D; tags[5].value = TRUE;
  a->handle = OpenWindowTagList(NULL, tags);
  if (!a->handle) throw('UI');
  win = a->handle(UiAmigaWindow *);
  a->visual = GetVisualInfoA(win->screen, NULL);
  if (!a->visual) { CloseWindow(win); a->handle = 0; throw('UI'); }
  UiAmigaRebuild(w);
}

U0 UiWindowClose(UiCtl *w)
{
  UiAmigaData *a = UiAmiga(w), *b;
  UiCtl *c;
  if (!a->handle) return;
  if (ui_amiga_drag && UiAmiga(ui_amiga_drag)->owner == w) ui_amiga_drag = NULL;
  if (a->menustrip) { ClearMenuStrip(a->handle); FreeMenus(a->menustrip); a->menustrip = 0; }
  CloseWindow(a->handle); a->handle = 0;
  FreeGadgets(a->gadgets); a->gadgets = 0;
  FreeVisualInfo(a->visual); a->visual = 0;
  for (c = ui_ctls; c; c = c->reg) {
    b = UiAmiga(c);
    if (c->kind != UI_WINDOW && b && b->owner == w) b->handle = 0;
  }
}

U0 UiQuit() { ui_amiga_running = FALSE; }

UiCtl *UiBoxNew(Bool vertical=TRUE) { UiCtl *c = UiAmigaNew(UI_BOX); UiAmiga(c)->vertical = vertical; return c; }
U0 UiBoxAdd(UiCtl *box, UiCtl *c) { UiAmigaAttach(box, c); }
UiCtl *UiGridNew() { return UiAmigaNew(UI_GRID); }
U0 UiGridAdd(UiCtl *g, UiCtl *c, I64 col, I64 row) { c->col = col; c->row = row; UiAmigaAttach(g, c); }
UiCtl *UiLabelNew(U8 *text="") { return UiAmigaNew(UI_LABEL, text); }
UiCtl *UiButtonNew(U8 *text) { return UiAmigaNew(UI_BUTTON, text); }
UiCtl *UiEntryNew(U8 *text="") { return UiAmigaNew(UI_ENTRY, text); }
UiCtl *UiPasswordNew(U8 *text="") { UiAmigaUnsupported("masked password fields"); return NULL; }
U8 *UiEntryText(UiCtl *c) { UiAmigaSnapshot(c); return StrNew(UiAmiga(c)->text); }

U0 UiAmigaSet(UiCtl *c, U32 tag, I64 value)
{
  UiAmigaData *a = UiAmiga(c);
  UiAmigaTag tags[2];
  if (!a->handle || !a->owner || !UiAmiga(a->owner)->handle) return;
  tags[0].tag = tag; tags[0].value = value;
  GT_SetGadgetAttrsA(a->handle, UiAmiga(a->owner)->handle, NULL, tags);
}

U0 UiEntrySetText(UiCtl *c, U8 *text)
{
  UiAmigaData *a = UiAmiga(c);
  U8 *old = a->text;
  a->text = StrNew(text); UiAmigaSet(c, UA_GT + 45, a->text); Free(old);
}
U0 UiLabelSetText(UiCtl *c, U8 *text)
{
  UiAmigaData *a = UiAmiga(c);
  U8 *old = a->text;
  a->text = StrNew(text); UiAmigaSet(c, UA_GT + 11, a->text); Free(old);
}
UiCtl *UiCheckboxNew(U8 *text, Bool checked=FALSE) { UiCtl *c = UiAmigaNew(UI_CHECKBOX, text); UiAmiga(c)->value = checked; return c; }
Bool UiCheckboxChecked(UiCtl *c) { UiAmigaSnapshot(c); return UiAmiga(c)->value; }
UiCtl *UiSliderNew(I64 min=0, I64 max=100) { UiCtl *c; if (min < -32768 || max > 32767 || min > max) throw('UI'); c = UiAmigaNew(UI_SLIDER); UiAmiga(c)->min = min; UiAmiga(c)->max = max; UiAmiga(c)->value = min; return c; }
I64 UiSliderValue(UiCtl *c) { return UiAmiga(c)->value; }
UiCtl *UiProgressNew() { UiCtl *c = UiAmigaNew(UI_PROGRESS); UiAmiga(c)->value = 0; return c; }
U0 UiProgressSet(UiCtl *c, I64 percent) { UiAmiga(c)->value = MaxI64(0, MinI64(100, percent)); UiAmigaPaint(c); }
UiCtl *UiSeparatorNew() { return UiAmigaNew(UI_SEP); }
UiCtl *UiCanvasNew(I64 w, I64 h, UiCallback *drawfn, U0 *data=NULL) { UiCtl *c = UiAmigaNew(UI_CANVAS); c->w = w; c->h = h; UiOnClick(c, drawfn, data); return c; }
U0 UiCanvasRedraw(UiCtl *c) { UiAmigaPaint(c); }

U0 UiSetColor(F64 r, F64 g, F64 b)
{
  UiAmigaWindow *win;
  UiAmigaScreen *screen;
  I64 pen;
  if (!ui_amiga_canvas) return;
  win = UiAmiga(UiAmiga(ui_amiga_canvas)->owner)->handle(UiAmigaWindow *);
  if (!win) return;
  screen = win->screen(UiAmigaScreen *);
  pen = FindColor(screen->colors,
    MaxI64(0, MinI64(255, ToI64(r * 255))) * 0x01010101,
    MaxI64(0, MinI64(255, ToI64(g * 255))) * 0x01010101,
    MaxI64(0, MinI64(255, ToI64(b * 255))) * 0x01010101, -1);
  SetAPen(win->port, MaxI64(0, pen)); SetDrMd(win->port, 1);
}

U0 UiFillRect(F64 x, F64 y, F64 w, F64 h)
{
  UiAmigaData *a;
  UiAmigaWindow *win;
  I64 x1, y1, x2, y2;
  if (!ui_amiga_canvas) return;
  a = UiAmiga(ui_amiga_canvas); win = UiAmiga(a->owner)->handle(UiAmigaWindow *);
  if (!win) return;
  x1 = MaxI64(0, ToI64(x)); y1 = MaxI64(0, ToI64(y));
  x2 = MinI64(a->w - 1, ToI64(x + w) - 1); y2 = MinI64(a->h - 1, ToI64(y + h) - 1);
  if (x1 <= x2 && y1 <= y2) RectFill(win->port, a->x + x1, a->y + y1, a->x + x2, a->y + y2);
}

U0 UiLine(F64 x1, F64 y1, F64 x2, F64 y2)
{
  UiAmigaData *a;
  UiAmigaWindow *win;
  if (!ui_amiga_canvas) return;
  a = UiAmiga(ui_amiga_canvas); win = UiAmiga(a->owner)->handle(UiAmigaWindow *);
  if (!win) return;
  Move(win->port, a->x + MaxI64(0, MinI64(a->w - 1, ToI64(x1))), a->y + MaxI64(0, MinI64(a->h - 1, ToI64(y1))));
  Draw(win->port, a->x + MaxI64(0, MinI64(a->w - 1, ToI64(x2))), a->y + MaxI64(0, MinI64(a->h - 1, ToI64(y2))));
}

UiCtl *UiMenuNew(U8 *title)
{
  UiCtl *m = UiAmigaNew(UI_MENU, title), *k;
  UiAmigaData *a;
  if (!ui_amiga_window) throw('UI');
  a = UiAmiga(ui_amiga_window); k = a->menus;
  if (!k) a->menus = m;
  else { while (k->sib) k = k->sib; k->sib = m; }
  UiAmigaDirty(m);
  return m;
}
UiCtl *UiMenuItem(UiCtl *m, U8 *label, UiCallback *fn, U0 *data=NULL)
{
  UiCtl *c = UiAmigaNew(UI_MENUITEM, label);
  UiAmigaAttach(m, c); UiOnClick(c, fn, data); return c;
}
UiCtl *UiSubMenu(UiCtl *m, U8 *title)
{
  UiCtl *c = UiAmigaNew(UI_MENU, title);
  if (UiAmiga(m)->parent) UiAmigaUnsupported("menus deeper than one submenu");
  UiAmigaAttach(m, c); return c;
}
UiCtl *UiPopupMenuNew() { return UiAmigaNew(UI_MENU); }
U0 UiContextMenu(UiCtl *c, UiCtl *menu) { UiAmigaUnsupported("popup context menus"); }

U0 UiAmigaMenus(UiCtl *w)
{
  UiAmigaData *a = UiAmiga(w);
  UiCtl *m, *k, *sub;
  UiAmigaNewMenu *entries;
  I64 count = 0, i = 0;
  if (!a->handle) return;
  if (a->menustrip) { ClearMenuStrip(a->handle); FreeMenus(a->menustrip); a->menustrip = 0; }
  for (m = a->menus; m; m = m->sib) {
    count++;
    for (k = m->kids; k; k = k->sib) {
      count++;
      for (sub = k->kids; sub; sub = sub->sib) count++;
    }
  }
  if (!count) return;
  entries = CAlloc((count + 1) * sizeof(UiAmigaNewMenu));
  for (m = a->menus; m; m = m->sib) {
    entries[i].type = 1; entries[i++].label = UiAmiga(m)->text;
    for (k = m->kids; k; k = k->sib) {
      entries[i].type = 2; entries[i].label = UiAmiga(k)->text; entries[i++].user = k;
      for (sub = k->kids; sub; sub = sub->sib) {
        entries[i].type = 3; entries[i].label = UiAmiga(sub)->text; entries[i++].user = sub;
      }
    }
  }
  a->menustrip = CreateMenusA(entries, NULL); Free(entries);
  if (!a->menustrip) throw('UI');
  if (!LayoutMenusA(a->menustrip, a->visual, NULL) || !SetMenuStrip(a->handle, a->menustrip)) throw('UI');
}

UiCtl *UiComboNew() { return UiAmigaNew(UI_COMBO); }
U0 UiComboAdd(UiCtl *c, U8 *text) { UiAmigaAttach(c, UiAmigaNew(UI_LABEL, text)); if (UiAmiga(c)->value < 0) UiAmiga(c)->value = 0; }
I64 UiComboSelected(UiCtl *c) { return UiAmiga(c)->value; }
U0 UiComboSetSelected(UiCtl *c, I64 index) { UiAmiga(c)->value = index; UiAmigaSet(c, UA_GT + 15, MaxI64(0, index)); }
U0 UiComboClear(UiCtl *c) { c->kids = NULL; UiAmiga(c)->value = -1; UiAmigaDirty(c); }
UiCtl *UiRadioNew() { return UiAmigaNew(UI_RADIO); }
U0 UiRadioAdd(UiCtl *c, U8 *text) { UiComboAdd(c, text); }
I64 UiRadioSelected(UiCtl *c) { return UiAmiga(c)->value; }
UiCtl *UiSpinNew(I64 min=0, I64 max=100) { UiCtl *c; if (min < -2147483648 || max > 2147483647 || min > max) throw('UI'); c = UiAmigaNew(UI_SPIN); UiAmiga(c)->min = min; UiAmiga(c)->max = max; UiAmiga(c)->value = min; return c; }
I64 UiSpinValue(UiCtl *c) { UiAmigaSnapshot(c); return UiAmiga(c)->value; }
U0 UiSpinSetValue(UiCtl *c, I64 value) { UiAmigaData *a = UiAmiga(c); a->value = MaxI64(a->min, MinI64(a->max, value)); UiAmigaSet(c, UA_GT + 47, a->value); }
UiCtl *UiMultilineNew(U8 *text="") { return UiAmigaNew(UI_MULTILINE, text); }
U0 UiMultilineSetText(UiCtl *c, U8 *text) { Free(UiAmiga(c)->text); UiAmiga(c)->text = StrNew(text); UiAmigaDirty(c); }
U8 *UiMultilineText(UiCtl *c) { return StrNew(UiAmiga(c)->text); }
U0 UiMultilineSetEditable(UiCtl *c, Bool on) { if (on) UiAmigaUnsupported("editable multiline text"); }
UiCtl *UiGroupNew(U8 *title) { return UiAmigaNew(UI_GROUP, title); }
U0 UiGroupSetChild(UiCtl *g, UiCtl *c) { UiAmigaAttach(g, c); }
UiCtl *UiTabNew() { UiCtl *c = UiAmigaNew(UI_TAB); UiAmiga(c)->value = 0; return c; }
U0 UiTabAdd(UiCtl *c, U8 *label, UiCtl *child) { UiCtl *page = UiAmigaNew(UI_BOX, label); UiAmigaAttach(page, child); UiAmigaAttach(c, page); }
U0 UiEnable(UiCtl *c, Bool on) { UiCtl *k; UiAmiga(c)->disabled = !on; UiAmigaSet(c, UA_DISABLED, !on); for (k = c->kids; k; k = k->sib) UiEnable(k, on); }
U0 UiSetVisible(UiCtl *c, Bool on) { UiAmiga(c)->hidden = !on; UiAmigaDirty(c); }
U0 UiExpand(UiCtl *c, Bool on) { UiAmiga(c)->expand = on; UiAmigaDirty(c); }
U0 UiTimer(I64 ms, UiCallback *fn, U0 *data=NULL) { UiCtl *c; UiInit; c = UiAmigaNew(UI_TIMER); UiAmiga(c)->interval = MaxI64(1, ms); UiAmiga(c)->deadline = UiAmigaNow() + MaxI64(1, ms); UiOnClick(c, fn, data); }
U0 UiQueueMain(UiCallback *fn, U0 *data=NULL) { UiCtl *c = UiAmigaNew(UI_TIMER); UiAmiga(c)->once = TRUE; UiAmiga(c)->deadline = 0; UiOnClick(c, fn, data); }
UiCtl *UiToolbarNew() { UiCtl *c = UiAmigaNew(UI_TOOLBAR); UiAmiga(c)->vertical = FALSE; return c; }
U0 UiToolAdd(UiCtl *c, U8 *label, UiCallback *fn, U0 *data=NULL) { UiCtl *b = UiButtonNew(label); UiOnClick(b, fn, data); UiAmigaAttach(c, b); }
UiCtl *UiStatusbarNew(U8 *text="") { return UiAmigaNew(UI_STATUS, text); }
U0 UiStatusSet(UiCtl *c, U8 *text) { UiLabelSetText(c, text); }
UiCtl *UiSplitNew(Bool vertical=FALSE) { UiCtl *c = UiAmigaNew(UI_SPLIT); UiAmiga(c)->vertical = vertical; return c; }
U0 UiSplitAdd(UiCtl *c, UiCtl *child) { UiAmigaAttach(c, child); }
UiCtl *UiScrollNew(UiCtl *child) { if (child->kind != UI_TABLE && child->kind != UI_TREE && child->kind != UI_MULTILINE) UiAmigaUnsupported("scrolling arbitrary containers"); return child; }
UiCtl *UiTableNew(UiCellCallback *fn, U0 *data=NULL) { UiCtl *c = UiAmigaNew(UI_TABLE); c->cellfn = fn; c->celldata = data; UiAmiga(c)->expand = TRUE; return c; }
U0 UiTableColumn(UiCtl *c, U8 *title) { UiAmigaAttach(c, UiAmigaNew(UI_COLUMN, title)); }
U0 UiTableSetRows(UiCtl *c, I64 rows) { c->row = MaxI64(0, rows); UiAmiga(c)->value = -1; UiAmigaDirty(c); }
I64 UiTableSelected(UiCtl *c) { return UiAmiga(c)->value; }
UiCtl *UiTreeNew() { UiCtl *c = UiAmigaNew(UI_TREE); UiAmiga(c)->expand = TRUE; return c; }
UiCtl *UiTreeAdd(UiCtl *c, UiCtl *parent, U8 *label) { UiCtl *node = UiAmigaNew(UI_TREENODE, label); node->celldata = UiAmiga(node)->text; if (!parent) parent = c; UiAmigaAttach(parent, node); UiAmigaDirty(c); return node; }
UiCtl *UiTreeSelected(UiCtl *c) { return UiAmiga(c)->selected; }

U0 UiAmigaMouse(UiCtl *w, I64 event, I64 code, I64 x, I64 y)
{
  UiCtl *c;
  UiAmigaData *a;
  I64 button = 0;
  Bool pressed = FALSE;
  if (event == UA_BUTTONS) {
    if ((code & 0x7F) == 0x68) button = 1;
    else if ((code & 0x7F) == 0x69) button = 2;
    else if ((code & 0x7F) == 0x6A) button = 3;
    else return;
    pressed = (code & 0x80) == 0;
  }
  c = ui_amiga_drag;
  if (!c) {
    for (c = ui_ctls; c; c = c->reg) {
      if (c->kind == UI_CANVAS) {
        a = UiAmiga(c);
        if (a->owner == w && !a->disabled && UiAmigaVisible(c) && x >= a->x && y >= a->y && x < a->x + a->w && y < a->y + a->h) break;
      }
    }
  }
  if (c && UiAmiga(c)->owner == w) {
    a = UiAmiga(c);
    if (event == UA_MOTION && ui_amiga_drag) { button = c->mouse_button; pressed = TRUE; }
    UiFireMouse(c, x - a->x, y - a->y, button, pressed, event == UA_MOTION);
    if (event == UA_BUTTONS) { if (pressed && UiAmiga(w)->handle) ui_amiga_drag = c; else ui_amiga_drag = NULL; }
  }
}

UiCtl *UiAmigaGadgetCtl(UiCtl *w, I64 address)
{
  UiCtl *c;
  UiAmigaData *a;
  if (!address) return NULL;
  for (c = ui_ctls; c; c = c->reg) {
    a = UiAmiga(c);
    if (c->kind != UI_WINDOW && a->owner == w && a->handle == address) return c;
  }
  return NULL;
}

U0 UiAmigaEvents(UiCtl *w)
{
  UiAmigaData *a = UiAmiga(w), *b;
  UiAmigaWindow *win = a->handle(UiAmigaWindow *);
  UiAmigaMessage *message;
  UiAmigaMenuItem *item;
  UiAmigaNode *node;
  UiCtl *c;
  I64 event, code, address, x, y, next, index;
  if (!a->handle) return;
  while (a->handle && (message = GT_GetIMsg(win->messages))) {
    event = message->event; code = message->code; address = message->address;
    x = message->x; y = message->y; c = NULL;
    if (event == UA_UP || event == UA_DOWN || (event == UA_MOTION && address)) {
      c = UiAmigaGadgetCtl(w, address);
      if (c) UiAmigaSnapshot(c);
    }
    // Reply before callbacks can close/rebuild the window and its gadgets.
    GT_ReplyIMsg(message);
    if (event == UA_REFRESH) {
      GT_BeginRefresh(win); if (w->kids) UiAmigaPaint(w->kids);
      if (a->handle) GT_EndRefresh(win, TRUE);
    } else if (event == UA_RESIZE) a->dirty = TRUE;
    else if (!ui_amiga_modal || ui_amiga_modal == w) {
      if (event == UA_CLOSE) UiWindowClose(w);
      else if (event == UA_BUTTONS || (event == UA_MOTION && !c)) UiAmigaMouse(w, event, code, x, y);
      else if (event == UA_MENU) {
        while (code != 0xFFFF && a->handle && a->menustrip) {
          item = ItemAddress(a->menustrip, code)(UiAmigaMenuItem *);
          if (!item) break;
          next = item->next; c = item->user(UiCtl *); UiFireClick(c); code = next;
        }
      } else if (c) {
        b = UiAmiga(c);
        if (c->kind == UI_SLIDER) b->value = code(I16);
        else if (c->kind == UI_COMBO || c->kind == UI_RADIO || c->kind == UI_TAB || c->kind == UI_TABLE || c->kind == UI_TREE) b->value = code;
        if (c->kind == UI_TAB) a->dirty = TRUE;
        if (c->kind == UI_TREE) {
          node = b->list->head(UiAmigaNode *); index = 0;
          while (node->next && index < code) { node = node->next(UiAmigaNode *); index++; }
          b->selected = NULL;
          if (node->next) b->selected = node->control;
        }
        if (event == UA_UP || c->kind == UI_RADIO || c->kind == UI_SLIDER) UiFireClick(c);
        if (event == UA_UP && c->kind == UI_ENTRY) UiFireSubmit(c);
      }
    }
  }
}

Bool UiAmigaPump()
{
  UiCtl *c;
  UiAmigaData *a;
  UiAmigaWindow *win;
  UiAmigaPort *port;
  I64 now = UiAmigaNow();
  U32 signals = 0;
  for (c = ui_ctls; c; c = c->reg) {
    a = UiAmiga(c);
    if (c->kind == UI_WINDOW && a->handle) UiAmigaEvents(c);
    else if (c->kind == UI_TIMER && a->deadline >= 0 && now >= a->deadline) {
      a->deadline = UiAmigaChoose(a->once, -1, now + a->interval);
      UiFireClick(c);
    }
  }
  for (c = ui_ctls; c; c = c->reg) {
    a = UiAmiga(c);
    if (c->kind == UI_WINDOW && a->handle) {
      if (a->dirty) UiAmigaRebuild(c);
      if (a->handle) {
        win = a->handle(UiAmigaWindow *); port = win->messages(UiAmigaPort *);
        signals |= 1 << port->signal;
      }
    }
  }
  if (!signals || !ui_amiga_running) return FALSE;
  Wait(signals);
  return TRUE;
}

U0 UiMain()
{
  UiCtl *c;
  UiInit;
  ui_amiga_running = TRUE;
  while (UiAmigaPump) {}
  ui_amiga_running = FALSE;
  for (c = ui_ctls; c; c = c->reg) if (c->kind == UI_WINDOW) UiWindowClose(c);
  if (ui_amiga_initialized) {
    CloseLibrary(AslBase); AslBase = ui_amiga_bases[3];
    CloseLibrary(GadToolsBase); GadToolsBase = ui_amiga_bases[2];
    CloseLibrary(GfxBase); GfxBase = ui_amiga_bases[1];
    CloseLibrary(IntuitionBase); IntuitionBase = ui_amiga_bases[0];
    ui_amiga_initialized = FALSE;
  }
}

U0 UiMsgBox(U8 *title, U8 *body)
{
  UiAmigaEasy request;
  U32 args[1];
  U32 parent = 0;
  UiInit;
  request.size = sizeof(UiAmigaEasy); request.title = title;
  request.body = "%s"; request.buttons = "OK"; args[0] = body;
  if (ui_amiga_window) parent = UiAmiga(ui_amiga_window)->handle;
  EasyRequestArgs(parent, &request, NULL, args);
}
#define UiWarnBox UiMsgBox

U8 *UiOpenFile()
{
  UiAmigaTag tags[3];
  UiAmigaFile *request;
  U8 *result = NULL, *drawer, *file;
  I64 length;
  UiInit;
  tags[0].tag = 0x80080002;
  if (ui_amiga_window) tags[0].value = UiAmiga(ui_amiga_window)->handle;
  tags[1].tag = 0x8008002B; tags[1].value = TRUE;
  request = AllocAslRequest(0, tags)(UiAmigaFile *);
  if (!request) throw('UI');
  if (AslRequest(request, NULL)) {
    drawer = request->drawer(U8 *); file = request->file(U8 *); length = StrLen(drawer);
    if (length && drawer[length - 1] != ':' && drawer[length - 1] != '/') result = MStrPrint("%s/%s", drawer, file);
    else result = MStrPrint("%s%s", drawer, file);
  }
  FreeAslRequest(request); return result;
}

U0 UiAmigaAccept(UiCtl *c, U0 *data) { I64 *result = data; *result = 1; }
U0 UiAmigaCancel(UiCtl *c, U0 *data) { I64 *result = data; *result = -1; }

U8 *UiPrompt(U8 *title, U8 *body, U8 *init="")
{
  UiCtl *old = ui_amiga_window, *oldmodal = ui_amiga_modal;
  UiCtl *w = UiWindowNew(title, 360, 120), *box = UiBoxNew, *entry = UiEntryNew(init), *row = UiBoxNew(FALSE);
  UiCtl *ok = UiButtonNew("OK"), *cancel = UiButtonNew("Cancel");
  I64 done = 0;
  Bool was_running = ui_amiga_running;
  U8 *result = NULL;
  UiBoxAdd(box, UiLabelNew(body)); UiBoxAdd(box, entry); UiBoxAdd(row, ok); UiBoxAdd(row, cancel); UiBoxAdd(box, row);
  UiOnClick(ok, &UiAmigaAccept, &done); UiOnSubmit(entry, &UiAmigaAccept, &done); UiOnClick(cancel, &UiAmigaCancel, &done);
  UiWindowSetChild(w, box); UiShow(w); ui_amiga_modal = w; ui_amiga_running = TRUE;
  while (!done && UiAmiga(w)->handle && ui_amiga_running) UiAmigaPump;
  if (done == 1) result = UiEntryText(entry);
  UiWindowClose(w); ui_amiga_window = old; ui_amiga_modal = oldmodal;
  if (!was_running) ui_amiga_running = FALSE;
  return result;
}

I64 UiPickColor(U8 *title, I64 rgb=0x808080)
{
  UiCtl *old = ui_amiga_window, *oldmodal = ui_amiga_modal;
  UiCtl *w = UiWindowNew(title, 360, 140), *box = UiBoxNew, *grid = UiGridNew, *row = UiBoxNew(FALSE);
  UiCtl *red = UiSliderNew(0, 255), *green = UiSliderNew(0, 255), *blue = UiSliderNew(0, 255);
  UiCtl *ok = UiButtonNew("OK"), *cancel = UiButtonNew("Cancel");
  I64 done = 0, result = -1;
  Bool was_running = ui_amiga_running;
  UiAmiga(red)->value = (rgb >> 16) & 255; UiAmiga(green)->value = (rgb >> 8) & 255; UiAmiga(blue)->value = rgb & 255;
  UiGridAdd(grid, UiLabelNew("Red"), 0, 0); UiGridAdd(grid, red, 1, 0);
  UiGridAdd(grid, UiLabelNew("Green"), 0, 1); UiGridAdd(grid, green, 1, 1);
  UiGridAdd(grid, UiLabelNew("Blue"), 0, 2); UiGridAdd(grid, blue, 1, 2);
  UiBoxAdd(box, grid); UiBoxAdd(row, ok); UiBoxAdd(row, cancel); UiBoxAdd(box, row);
  UiOnClick(ok, &UiAmigaAccept, &done); UiOnClick(cancel, &UiAmigaCancel, &done);
  UiWindowSetChild(w, box); UiShow(w); ui_amiga_modal = w; ui_amiga_running = TRUE;
  while (!done && UiAmiga(w)->handle && ui_amiga_running) UiAmigaPump;
  if (done == 1) result = (UiSliderValue(red) << 16) | (UiSliderValue(green) << 8) | UiSliderValue(blue);
  UiWindowClose(w); ui_amiga_window = old; ui_amiga_modal = oldmodal;
  if (!was_running) ui_amiga_running = FALSE;
  return result;
}
