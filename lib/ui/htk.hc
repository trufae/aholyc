// lib/ui backend over lib/htk: graphical apps run in the terminal with the
// exact same source.  Select it with -DUI_HTK.  Pixel sizes from the ui.hc
// API map onto cells at 8x16 pixels per cell.

#include "../htk/htk.hc"

#define UI_HTK_CELL_W 8
#define UI_HTK_CELL_H 16

UiCtl *ui_htk_window;   // most recent window, parents menus and dialogs

U0 UiHtkChanged(HtkCtl *h)
{
  UiCtl *c = h->user;

  if (c && c->kind == UI_CANVAS && c->mousefn) {
    I64 x = h->mouse_x, y = h->mouse_y;
    if (h->w > 0)
      x = x * c->w / h->w;
    if (h->h > 0)
      y = y * c->h / h->h;
    UiFireMouse(c, x, y, h->mouse_button, h->mouse_pressed,
      h->mouse_motion);
    return;
  }
  UiFireClick(c);
}

U0 UiHtkSubmit(HtkCtl *h)
{
  UiFireSubmit(h->user);
}

UiCtl *UiHtkWrap(I64 kind, HtkCtl *h)
{
  UiCtl *c = UiCtlNew(kind, h);

  h->user = c;
  h->changed = &UiHtkChanged;
  return c;
}

HtkCtl *UiHtk(UiCtl *c)
{
  return c->native(HtkCtl *);
}

U0 UiInit()
{
  HtkInit;
}

U0 UiQuit()
{
  HtkQuit;
}

U0 UiMain()
{
  HtkMain;
  HtkFini;
}

U0 UiShow(UiCtl *w)
{
  htk_dirty = TRUE;
}

U0 UiWindowClose(UiCtl *w)
{
  HtkWindowClose(UiHtk(w));
}

UiCtl *UiWindowNew(U8 *title, I64 w=480, I64 h=320)
{
  HtkCtl *win = HtkWindowNew(title, w / UI_HTK_CELL_W, h / UI_HTK_CELL_H);
  UiCtl *c = UiHtkWrap(UI_WINDOW, win);

  c->w = w;
  c->h = h;
  ui_htk_window = c;
  return c;
}

U0 UiWindowSetChild(UiCtl *w, UiCtl *c)
{
  HtkAdd(UiHtk(w), UiHtk(c));
}

UiCtl *UiBoxNew(Bool vertical=TRUE)
{
  HtkCtl *h = HtkNew(HTK_BOX);

  h->vertical = vertical;
  return UiHtkWrap(UI_BOX, h);
}

U0 UiBoxAdd(UiCtl *box, UiCtl *c)
{
  HtkAdd(UiHtk(box), UiHtk(c));
}

UiCtl *UiGridNew()
{
  return UiHtkWrap(UI_GRID, HtkNew(HTK_GRID));
}

U0 UiGridAdd(UiCtl *g, UiCtl *c, I64 col, I64 row)
{
  HtkCtl *h = UiHtk(c);

  h->col = col;
  h->row = row;
  HtkAdd(UiHtk(g), h);
}

UiCtl *UiLabelNew(U8 *text="")
{
  HtkCtl *h = HtkNew(HTK_LABEL);

  HtkSetText(h, text);
  return UiHtkWrap(UI_LABEL, h);
}

U0 UiLabelSetText(UiCtl *l, U8 *text)
{
  HtkSetText(UiHtk(l), text);
}

UiCtl *UiButtonNew(U8 *text)
{
  return UiHtkWrap(UI_BUTTON, HtkButtonNew(text));
}

UiCtl *UiEntryNew(U8 *text="")
{
  UiCtl *c = UiHtkWrap(UI_ENTRY, HtkEntryNew(text));

  UiHtk(c)->submit = &UiHtkSubmit;
  return c;
}

UiCtl *UiPasswordNew(U8 *text="")
{
  UiCtl *c = UiEntryNew(text);

  UiHtk(c)->secret = TRUE;
  return c;
}

U8 *UiEntryText(UiCtl *e)
{
  return StrNew(UiHtk(e)->text);
}

U0 UiEntrySetText(UiCtl *e, U8 *text)
{
  HtkCtl *h = UiHtk(e);

  HtkSetText(h, text);
  h->cursor = StrLen(text);
}

UiCtl *UiCheckboxNew(U8 *text, Bool checked=FALSE)
{
  return UiHtkWrap(UI_CHECKBOX, HtkCheckboxNew(text, checked));
}

Bool UiCheckboxChecked(UiCtl *c)
{
  return UiHtk(c)->value;
}

UiCtl *UiSliderNew(I64 min=0, I64 max=100)
{
  return UiHtkWrap(UI_SLIDER, HtkSliderNew(min, max));
}

I64 UiSliderValue(UiCtl *s)
{
  return UiHtk(s)->value;
}

UiCtl *UiProgressNew()
{
  return UiHtkWrap(UI_PROGRESS, HtkProgressNew);
}

U0 UiProgressSet(UiCtl *p, I64 percent)
{
  UiHtk(p)->value = percent;
  htk_dirty = TRUE;
}

UiCtl *UiSeparatorNew()
{
  return UiHtkWrap(UI_SEP, HtkNew(HTK_SEP));
}

// Canvas: the app draws in its pixel space, scaled onto the cell grid.
U0 UiHtkPaint(HtkCtl *h)
{
  UiCtl *c = h->user;
  I64 paint = c->cellfn;

  if (paint)
    paint(c, c->celldata);
}

UiCtl *UiCanvasNew(I64 w, I64 h, U0 *drawfn, U0 *data=NULL)
{
  HtkCtl *canvas = HtkCanvasNew(w / UI_HTK_CELL_W, h / UI_HTK_CELL_H,
    &UiHtkPaint, 0);
  UiCtl *c = UiHtkWrap(UI_CANVAS, canvas);

  c->w = w;
  c->h = h;
  c->cellfn = drawfn;
  c->celldata = data;
  return c;
}

U0 UiCanvasRedraw(UiCtl *c)
{
  htk_dirty = TRUE;
}

U0 UiSetColor(F64 r, F64 g, F64 b)
{
  HtkCanvasColor(r, g, b);
}

U0 UiFillRect(F64 x, F64 y, F64 w, F64 h)
{
  UiCtl *c;

  if (!htk_canvas)
    return;
  c = htk_canvas->user;
  HtkCanvasRect(x * htk_canvas->w / c->w, y * htk_canvas->h / c->h,
    w * htk_canvas->w / c->w, h * htk_canvas->h / c->h);
}

U0 UiLine(F64 x1, F64 y1, F64 x2, F64 y2)
{
  UiCtl *c;

  if (!htk_canvas)
    return;
  c = htk_canvas->user;
  HtkCanvasLine(x1 * htk_canvas->w / c->w, y1 * htk_canvas->h / c->h,
    x2 * htk_canvas->w / c->w, y2 * htk_canvas->h / c->h);
}

UiCtl *UiMenuNew(U8 *title)
{
  return UiHtkWrap(UI_MENU, HtkMenuNew(UiHtk(ui_htk_window), title));
}

UiCtl *UiMenuItem(UiCtl *m, U8 *label, U0 *fn, U0 *data=NULL)
{
  UiCtl *c = UiHtkWrap(UI_MENUITEM, HtkMenuItem(UiHtk(m), label));

  UiOnClick(c, fn, data);
  return c;
}

UiCtl *UiSubMenu(UiCtl *m, U8 *title)
{
  return UiHtkWrap(UI_MENU, HtkSubMenu(UiHtk(m), title));
}

UiCtl *UiPopupMenuNew()
{
  return UiHtkWrap(UI_MENU, HtkContextMenuNew);
}

U0 UiContextMenu(UiCtl *c, UiCtl *menu)
{
  UiHtk(c)->menu = UiHtk(menu);
}

UiCtl *UiComboNew()
{
  return UiHtkWrap(UI_COMBO, HtkComboNew);
}

U0 UiComboAdd(UiCtl *c, U8 *text)
{
  HtkComboAdd(UiHtk(c), text);
}

I64 UiComboSelected(UiCtl *c)
{
  return UiHtk(c)->value;
}

U0 UiComboSetSelected(UiCtl *c, I64 index)
{
  UiHtk(c)->value = index;
  htk_dirty = TRUE;
}

U0 UiComboClear(UiCtl *c)
{
  HtkCtl *h = UiHtk(c), *k = h->kids, *next;

  while (k) {
    next = k->sib;
    Free(k->text);
    Free(k);
    k = next;
  }
  h->kids = NULL;
  h->value = -1;
  htk_dirty = TRUE;
}

UiCtl *UiRadioNew()
{
  return UiHtkWrap(UI_RADIO, HtkRadioNew);
}

U0 UiRadioAdd(UiCtl *r, U8 *text)
{
  HtkRadioAdd(UiHtk(r), text);
}

I64 UiRadioSelected(UiCtl *r)
{
  return UiHtk(r)->value;
}

UiCtl *UiSpinNew(I64 min=0, I64 max=100)
{
  return UiHtkWrap(UI_SPIN, HtkSpinNew(min, max));
}

I64 UiSpinValue(UiCtl *s)
{
  return UiHtk(s)->value;
}

U0 UiSpinSetValue(UiCtl *s, I64 value)
{
  UiHtk(s)->value = value;
  htk_dirty = TRUE;
}

UiCtl *UiMultilineNew(U8 *text="")
{
  return UiHtkWrap(UI_MULTILINE, HtkMultilineNew(text));
}

U0 UiMultilineSetText(UiCtl *m, U8 *text)
{
  HtkCtl *h = UiHtk(m);

  HtkSetText(h, text);
  h->cursor = StrLen(text);  // the draw keeps the cursor row visible
}

U8 *UiMultilineText(UiCtl *m)
{
  return StrNew(UiHtk(m)->text);
}

U0 UiMultilineSetEditable(UiCtl *m, Bool on)
{
  UiHtk(m)->readonly = !on;
}

UiCtl *UiGroupNew(U8 *title)
{
  return UiHtkWrap(UI_GROUP, HtkGroupNew(title));
}

U0 UiGroupSetChild(UiCtl *g, UiCtl *child)
{
  HtkAdd(UiHtk(g), UiHtk(child));
}

UiCtl *UiTabNew()
{
  return UiHtkWrap(UI_TAB, HtkTabNew);
}

U0 UiTabAdd(UiCtl *t, U8 *label, UiCtl *child)
{
  HtkTabAdd(UiHtk(t), label, UiHtk(child));
}

U0 UiEnable(UiCtl *c, Bool on)
{
  UiHtk(c)->disabled = !on;
  htk_dirty = TRUE;
}

U0 UiSetVisible(UiCtl *c, Bool on)
{
  UiHtk(c)->hidden = !on;
  htk_dirty = TRUE;
}

U0 UiExpand(UiCtl *c, Bool on)
{
  UiHtk(c)->expand = on;
}

U0 UiHtkTimerFire(I64 ctl, I64 unused)
{
  UiFireClick(ctl);
}

U0 UiTimer(I64 ms, U0 *fn, U0 *data=NULL)
{
  UiCtl *t = UiCtlNew(UI_TIMER, 0);

  UiOnClick(t, fn, data);
  HtkHookAdd(ms, ms, &UiHtkTimerFire, t, 0);
}

U0 UiQueueMain(U0 *fn, U0 *data=NULL)
{
  UiCtl *t = UiCtlNew(UI_TIMER, 0);

  UiOnClick(t, fn, data);
  HtkHookAdd(0, 0, &UiHtkTimerFire, t, 0);
}

UiCtl *UiToolbarNew()
{
  return UiHtkWrap(UI_TOOLBAR, HtkToolbarNew);
}

U0 UiToolAdd(UiCtl *tb, U8 *label, U0 *fn, U0 *data=NULL)
{
  UiCtl *c = UiHtkWrap(UI_BUTTON, HtkButtonNew(label));

  UiOnClick(c, fn, data);
  HtkAdd(UiHtk(tb), UiHtk(c));
}

UiCtl *UiStatusbarNew(U8 *text="")
{
  HtkCtl *h = HtkStatusbarNew(text);

  return UiHtkWrap(UI_STATUS, h);
}

U0 UiStatusSet(UiCtl *sb, U8 *text)
{
  HtkSetText(UiHtk(sb), text);
}

UiCtl *UiSplitNew(Bool vertical=FALSE)
{
  HtkCtl *h = HtkNew(HTK_SPLIT);

  h->vertical = vertical;
  h->expand = TRUE;
  return UiHtkWrap(UI_SPLIT, h);
}

U0 UiSplitAdd(UiCtl *sp, UiCtl *child)
{
  HtkAdd(UiHtk(sp), UiHtk(child));
}

UiCtl *UiScrollNew(UiCtl *child)
{
  HtkCtl *h = HtkNew(HTK_SCROLL);

  h->focusable = TRUE;
  h->expand = TRUE;
  HtkAdd(h, UiHtk(child));
  return UiHtkWrap(UI_SCROLL, h);
}

U8 *UiHtkCell(HtkCtl *t, I64 row, I64 col, I64 data)
{
  return UiTableCell(t->user, row, col);
}

UiCtl *UiTableNew(U0 *cellfn, U0 *data=NULL)
{
  HtkCtl *h = HtkTableNew(&UiHtkCell, 0);
  UiCtl *c = UiHtkWrap(UI_TABLE, h);

  c->cellfn = cellfn;
  c->celldata = data;
  return c;
}

U0 UiTableColumn(UiCtl *t, U8 *title)
{
  HtkTableColumn(UiHtk(t), title);
  t->col++;
}

U0 UiTableSetRows(UiCtl *t, I64 nrows)
{
  HtkCtl *h = UiHtk(t);

  h->high = nrows;
  if (h->value >= nrows)
    h->value = nrows - 1;
  t->row = nrows;
  htk_dirty = TRUE;
}

I64 UiTableSelected(UiCtl *t)
{
  return UiHtk(t)->value;
}

UiCtl *UiTreeNew()
{
  return UiHtkWrap(UI_TREE, HtkTreeNew);
}

UiCtl *UiTreeAdd(UiCtl *t, UiCtl *parent, U8 *label)
{
  HtkCtl *from = NULL;
  HtkCtl *node;

  if (parent)
    from = UiHtk(parent);
  node = HtkTreeAdd(UiHtk(t), from, label);
  return UiHtkWrap(UI_TREENODE, node);
}

UiCtl *UiTreeSelected(UiCtl *t)
{
  HtkCtl *node = UiHtk(t)->link;

  if (!node)
    return NULL;
  return node->user;
}

U0 UiMsgBox(U8 *title, U8 *body)
{
  HtkMsgBox(title, body);
}

U0 UiWarnBox(U8 *title, U8 *body)
{
  HtkMsgBox(title, body);
}

U8 *UiOpenFile()
{
  return HtkOpenFile;
}

U8 *UiPrompt(U8 *title, U8 *body, U8 *init="")
{
  return HtkPrompt(title, body, init);
}

I64 UiPickColor(U8 *title, I64 rgb=0x808080)
{
  return HtkColorPick(title, rgb);
}
