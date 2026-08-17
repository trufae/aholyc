// ui.hc — a tiny cross-platform UI library for HolyC
// Select the backend with -DUI_COCOA, -DUI_WIN32 or -DUI_GTK4; the
// default is the platform's native one: Cocoa on macOS, Win32 on
// Windows, GTK4 elsewhere.
// Every backend implements the same frontend API:
//
//   UiInit();
//   UiCtl *UiWindowNew(U8 *title, I64 w=480, I64 h=320);
//   UiCtl *UiBoxNew(Bool vertical=TRUE);
//   UiCtl *UiGridNew();
//   UiCtl *UiLabelNew(U8 *text="");
//   UiCtl *UiButtonNew(U8 *text);
//   UiCtl *UiEntryNew(U8 *text="");
//   UiCtl *UiCheckboxNew(U8 *text, Bool checked=FALSE);
//   UiCtl *UiSliderNew(I64 min=0, I64 max=100);
//   UiCtl *UiProgressNew();
//   UiCtl *UiSeparatorNew();
//   UiCtl *UiCanvasNew(I64 w, I64 h, U0 *drawfn, U0 *data=NULL);
//   UiCtl *UiMenuNew(U8 *title);                    // create the window first
//   UiCtl *UiMenuItem(UiCtl *m, U8 *label, U0 *fn, U0 *data=NULL);
//   UiCtl *UiSubMenu(UiCtl *m, U8 *title);          // nested menu
//   UiCtl *UiPopupMenuNew();                        // menu outside the bar
//   U0 UiContextMenu(UiCtl *c, UiCtl *menu);        // pops on right click
//   U0 UiLabelSetText(UiCtl *l, U8 *text);
//   U8 *UiEntryText(UiCtl *e);                      // MAlloc'd copy, Free it
//   U0 UiEntrySetText(UiCtl *e, U8 *text);
//   Bool UiCheckboxChecked(UiCtl *c);
//   I64 UiSliderValue(UiCtl *s);
//   U0 UiProgressSet(UiCtl *p, I64 percent);
//   U0 UiOnClick(UiCtl *c, U0 *fn, U0 *data=NULL);  // fn: U0 (UiCtl*, U0*)
//   U0 UiOnChange(UiCtl *c, U0 *fn, U0 *data=NULL); // entry/slider/checkbox
//   U0 UiOnSubmit(UiCtl *e, U0 *fn, U0 *data=NULL); // Enter pressed in entry
//   U0 UiBoxAdd(UiCtl *box, UiCtl *c);
//   U0 UiGridAdd(UiCtl *g, UiCtl *c, I64 col, I64 row);
//   U0 UiWindowSetChild(UiCtl *w, UiCtl *c);
//   U0 UiShow(UiCtl *w);
//   U0 UiWindowClose(UiCtl *w);                     // as if the user closed it
//   U0 UiMain();
//   U0 UiQuit();
//   U0 UiCanvasRedraw(UiCtl *c);
//   U0 UiOnMouse(UiCtl *c, U0 *fn, U0 *data=NULL); // canvas pointer event
//   I64 UiMouseX(UiCtl *c);
//   I64 UiMouseY(UiCtl *c);
//   I64 UiMouseButton(UiCtl *c);
//   Bool UiMousePressed(UiCtl *c);
//   Bool UiMouseMotion(UiCtl *c);
//
// Modal dialogs (parented to the most recent window):
//   U0 UiMsgBox(U8 *title, U8 *body);
//   U0 UiWarnBox(U8 *title, U8 *body);
//   U8 *UiOpenFile();                            // MAlloc'd path, NULL on cancel
//   U8 *UiPrompt(U8 *title, U8 *body, U8 *init=""); // MAlloc'd, NULL on cancel
//
// UiWindowNew may be called repeatedly; the program ends when the last
// window closes (on win32, create each window before its widgets).
//
// More widgets:
//   UiCtl *UiComboNew();                         // dropdown
//   U0 UiComboAdd(UiCtl *c, U8 *text);
//   I64 UiComboSelected(UiCtl *c);               // -1 if none
//   U0 UiComboSetSelected(UiCtl *c, I64 index);
//   U0 UiComboClear(UiCtl *c);                     // remove every item
//   UiCtl *UiRadioNew();                          // vertical radio group
//   U0 UiRadioAdd(UiCtl *r, U8 *text);
//   I64 UiRadioSelected(UiCtl *r);
//   UiCtl *UiSpinNew(I64 min=0, I64 max=100);
//   I64 UiSpinValue(UiCtl *s);
//   U0 UiSpinSetValue(UiCtl *s, I64 value);
//   UiCtl *UiMultilineNew(U8 *text="");           // multi-line text area
//   U0 UiMultilineSetText(UiCtl *m, U8 *text);     // replace, scroll to end
//   U8 *UiMultilineText(UiCtl *m);                 // MAlloc'd copy, Free it
//   U0 UiMultilineSetEditable(UiCtl *m, Bool on);
//   UiCtl *UiPasswordNew(U8 *text="");
//   UiCtl *UiGroupNew(U8 *title);                 // titled frame
//   U0 UiGroupSetChild(UiCtl *g, UiCtl *child);
//   UiCtl *UiTabNew();
//   U0 UiTabAdd(UiCtl *t, U8 *label, UiCtl *child);
//
// Lifecycle and timing (fn: U0 (UiCtl *ctl, U0 *data)):
//   U0 UiEnable(UiCtl *c, Bool on);
//   U0 UiExpand(UiCtl *c, Bool on);               // fill spare box space
//   U0 UiSetVisible(UiCtl *c, Bool on);
//   U0 UiTimer(I64 ms, U0 *fn, U0 *data=NULL);    // repeating
//   U0 UiQueueMain(U0 *fn, U0 *data=NULL);        // run once on the UI thread
//
// App-shell containers (each is a control you UiBoxAdd like any other):
//   UiCtl *UiToolbarNew();
//   U0 UiToolAdd(UiCtl *tb, U8 *label, U0 *fn, U0 *data=NULL);
//   UiCtl *UiStatusbarNew(U8 *text="");
//   U0 UiStatusSet(UiCtl *sb, U8 *text);
//   UiCtl *UiSplitNew(Bool vertical=FALSE);       // two-pane divider
//   U0 UiSplitAdd(UiCtl *sp, UiCtl *child);        // call twice
//   UiCtl *UiScrollNew(UiCtl *child);              // wrap a control in a scroller
//
// Table — a pull model: you supply a cell callback and a row count, the
// widget asks for the text of each visible cell (col: U8 *fn(UiCtl *t,
// I64 row, I64 col, U0 *data)).
//   UiCtl *UiTableNew(U0 *cellfn, U0 *data=NULL);
//   U0 UiTableColumn(UiCtl *t, U8 *title);         // add columns in order
//   U0 UiTableSetRows(UiCtl *t, I64 nrows);        // (re)load with N rows
//   I64 UiTableSelected(UiCtl *t);                 // selected row, -1 if none
//   U0 UiOnClick(UiCtl *t, ...);                   // fires on selection change
//
// Tree (push model) — build nodes, the widget renders the hierarchy:
//   UiCtl *UiTreeNew();
//   UiCtl *UiTreeAdd(UiCtl *t, UiCtl *parent, U8 *label);  // parent=NULL: root
//   UiCtl *UiTreeSelected(UiCtl *t);               // selected node, NULL if none
//
// Inside a canvas draw callback (U0 fn(UiCtl *c, U0 *data)) only:
//   U0 UiSetColor(F64 r, F64 g, F64 b);             // 0.0 .. 1.0
//   U0 UiFillRect(F64 x, F64 y, F64 w, F64 h);
//   U0 UiLine(F64 x1, F64 y1, F64 x2, F64 y2);

#define UI_WINDOW   0
#define UI_BOX      1
#define UI_GRID     2
#define UI_LABEL    3
#define UI_BUTTON   4
#define UI_ENTRY    5
#define UI_CHECKBOX 6
#define UI_SLIDER   7
#define UI_PROGRESS 8
#define UI_SEP      9
#define UI_CANVAS   10
#define UI_MENU     11
#define UI_MENUITEM 12
#define UI_COMBO    13
#define UI_RADIO    14
#define UI_SPIN     15
#define UI_MULTILINE 16
#define UI_GROUP    17
#define UI_TAB      18
#define UI_TIMER    19
#define UI_TOOLBAR  20
#define UI_STATUS   21
#define UI_SPLIT    22
#define UI_SCROLL   23
#define UI_TABLE    24
#define UI_COLUMN   25
#define UI_TREE     26
#define UI_TREENODE 27

class UiCtl
{
  I64 native;        // toolkit handle (menu-item id on win32)
  I64 cb, cb_data;   // event callback + user data
  I64 submitfn, submitdata; // entry Enter callback + user data
  I64 popup;         // context menu handle (backend specific)
  I64 kind;          // UI_*
  I64 w, h;          // window/canvas size
  I64 col, row;      // grid cell (table: ncols, nrows)
  I64 cellfn, celldata;  // table pull-model cell callback
  I64 mousefn, mousedata; // canvas mouse callback + user data
  I64 mouse_x, mouse_y, mouse_button;
  Bool mouse_pressed, mouse_motion;
  UiCtl *reg;        // registry chain
  UiCtl *kids, *sib; // container children, for backends without containers
};

UiCtl *ui_ctls = NULL;

UiCtl *UiCtlNew(I64 kind, I64 native)
{
  UiCtl *c = CAlloc(sizeof(UiCtl));
  c->kind = kind;
  c->native = native;
  c->reg = ui_ctls;
  ui_ctls = c;
  return c;
}

UiCtl *UiCtlFind(I64 native)
{
  UiCtl *c = ui_ctls;
  while (c) {
    if (c->native == native)
      return c;
    c = c->reg;
  }
  return NULL;
}

U0 UiKidAdd(UiCtl *parent, UiCtl *c)
{
  UiCtl *k = parent->kids;
  if (!k) {
    parent->kids = c;
    return;
  }
  while (k->sib)
    k = k->sib;
  k->sib = c;
}

U0 UiFireClick(UiCtl *c)
{
  if (c && c->cb)
    c->cb(c, c->cb_data);
}

U0 UiOnClick(UiCtl *c, U0 *fn, U0 *data=NULL)
{
  c->cb = fn;
  c->cb_data = data;
}

U0 UiOnChange(UiCtl *c, U0 *fn, U0 *data=NULL)
{
  UiOnClick(c, fn, data);
}

U0 UiFireSubmit(UiCtl *c)
{
  if (c && c->submitfn)
    c->submitfn(c, c->submitdata);
}

U0 UiOnSubmit(UiCtl *c, U0 *fn, U0 *data=NULL)
{
  c->submitfn = fn;
  c->submitdata = data;
}

U0 UiOnMouse(UiCtl *c, U0 *fn, U0 *data=NULL)
{
  c->mousefn = fn;
  c->mousedata = data;
}

U0 UiFireMouse(UiCtl *c, I64 x, I64 y, I64 button, Bool pressed, Bool motion)
{
  if (!c)
    return;
  c->mouse_x = x;
  c->mouse_y = y;
  c->mouse_button = button;
  c->mouse_pressed = pressed;
  c->mouse_motion = motion;
  if (c->mousefn)
    c->mousefn(c, c->mousedata);
}

I64 UiMouseX(UiCtl *c)
{
  return c->mouse_x;
}

I64 UiMouseY(UiCtl *c)
{
  return c->mouse_y;
}

I64 UiMouseButton(UiCtl *c)
{
  return c->mouse_button;
}

Bool UiMousePressed(UiCtl *c)
{
  return c->mouse_pressed;
}

Bool UiMouseMotion(UiCtl *c)
{
  return c->mouse_motion;
}

// pull one cell's text from the table's data-source callback (through the
// raw pointer; typed fn-ptr declarators are rejected by the compiler)
U8 *UiTableCell(UiCtl *t, I64 row, I64 col)
{
  if (!t->cellfn)
    return "";
  I64 fn = t->cellfn;
  return fn(t, row, col, t->celldata)(U8 *);
}

#include "backend.hc"
