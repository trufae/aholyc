// Win32 backend for ui.hc (cross-build with mingw, ANSI APIs).
// Controls are parented to the main window at creation, so create the
// window before its widgets; the top-level box lays children out at
// UiShow (one container level: a box whose children may include a grid).
// @ldflags=-mwindows -luser32 -lgdi32 -lcomctl32 -lcomdlg32

extern I64 GetModuleHandleA(I64 name);
extern I64 LoadCursorA(I64 inst, I64 name);
extern I64 RegisterClassExA(U0 *wc);
extern I64 CreateWindowExA(I64 exstyle, U8 *cls, U8 *title, I64 style,
  I64 x, I64 y, I64 w, I64 h, I64 parent, I64 menu, I64 inst, I64 param);
extern I64 DefWindowProcA(I64 hwnd, I64 msg, I64 wp, I64 lp);
extern U0 PostQuitMessage(I64 code);
extern I64 GetMessageA(U0 *msg, I64 hwnd, I64 min, I64 max);
extern I64 TranslateMessage(U0 *msg);
extern I64 DispatchMessageA(U0 *msg);
extern I64 SendMessageA(I64 hwnd, I64 msg, I64 wp, I64 lp);
extern I64 SetWindowTextA(I64 hwnd, U8 *text);
extern I64 GetWindowTextA(I64 hwnd, U8 *buf, I64 max);
extern I64 GetWindowTextLengthA(I64 hwnd);
extern I64 MoveWindow(I64 hwnd, I64 x, I64 y, I64 w, I64 h, I64 repaint);
extern I64 ShowWindow(I64 hwnd, I64 cmd);
extern I64 GetClientRect(I64 hwnd, U0 *rect);
extern I64 InvalidateRect(I64 hwnd, I64 rect, I64 erase);
extern I64 InitCommonControlsEx(U0 *icc);
extern I64 CreateMenu();
extern I64 CreatePopupMenu();
extern I64 AppendMenuA(I64 menu, I64 flags, I64 id, U8 *label);
extern I64 SetMenu(I64 hwnd, I64 menu);
extern I64 BeginPaint(I64 hwnd, U0 *ps);
extern I64 EndPaint(I64 hwnd, U0 *ps);
extern I64 FillRect(I64 hdc, U0 *rect, I64 brush);
extern I64 MoveToEx(I64 hdc, I64 x, I64 y, I64 old);
extern I64 LineTo(I64 hdc, I64 x, I64 y);
extern I64 CreateSolidBrush(I64 color);
extern I64 CreatePen(I64 style, I64 width, I64 color);
extern I64 SelectObject(I64 hdc, I64 obj);
extern I64 DeleteObject(I64 obj);
extern I64 MessageBoxA(I64 hwnd, U8 *body, U8 *title, I64 flags);
extern I64 GetOpenFileNameA(U0 *ofn);
extern I64 DestroyWindow(I64 hwnd);
extern I64 EnableWindow(I64 hwnd, I64 on);
extern I64 SetTimer(I64 hwnd, I64 id, I64 ms, I64 proc);
extern I64 KillTimer(I64 hwnd, I64 id);

#define WM_DESTROY 2
#define WM_PAINT 0xF
#define WM_COMMAND 0x111
#define WM_HSCROLL 0x114
#define WM_VSCROLL 0x115
#define WM_TIMER 0x113
#define WS_OVERLAPPEDWINDOW 0xCF0000
#define WS_CHILD_VISIBLE 0x50000000  // WS_CHILD | WS_VISIBLE
#define CW_USEDEFAULT 0x80000000
#define SW_SHOW 5
#define BM_GETCHECK 0xF0
#define BM_SETCHECK 0xF1
#define BS_AUTOCHECKBOX 3
#define TBM_GETPOS 0x400
#define TBM_SETRANGEMIN 0x407
#define TBM_SETRANGEMAX 0x408
#define PBM_SETPOS 0x402
#define PBM_SETRANGE32 0x406
#define MF_POPUP 0x10

/* @align */ class UiWndClass
{
  U32 size, style;
  I64 wndproc;
  U32 cls_extra, wnd_extra;
  I64 inst, icon, cursor, background;
  U8 *menu_name, *class_name;
  I64 icon_sm;
};

// Win64 OPENFILENAMEA, natural alignment matches pshpack8 (152 bytes)
/* @align */ class UiOfn
{
  U32 size;
  I64 owner, inst;
  U8 *filter, *custom;
  U32 maxcust, filterindex;
  U8 *file;
  U32 maxfile;
  U8 *filetitle;
  U32 maxfiletitle;
  U8 *initdir, *title;
  U32 flags;
  U16 fileoff, fileext;
  U8 *defext;
  I64 custdata, hook;
  U8 *template_name;
  U0 *reserved;
  U32 dwreserved, flagsex;
};

I64 ui_inst, ui_hwnd, ui_menubar = 0, ui_menuid = 1000, ui_nwin = 0;
I64 ui_hdc = 0, ui_brush = 0, ui_pen = 0;  // valid inside a draw callback
I64 ui_dlg_done = 0, ui_dlg_text = 0, ui_timerid = 0, ui_onceid = 90000;
UiWndClass ui_wc, ui_cwc, ui_dwc;

U0 UiLayout(UiCtl *w);  // defined after the window procs that call it

UiCtl *UiMenuFind(I64 id)
{
  UiCtl *c = ui_ctls;
  while (c) {
    if (c->kind == UI_MENUITEM && c->native == id)
      return c;
    c = c->reg;
  }
  return NULL;
}

I64 UiWndProc(I64 hwnd, I64 msg, I64 wp, I64 lp)
{
  I64 code = wp >> 16 & 0xFFFF;
  switch (msg) {
  case WM_COMMAND:
    if (!lp)
      UiFireClick(UiMenuFind(wp & 0xFFFF));
    else if (code == 0 || code == 0x300 || code == 1)  // BN_CLICKED, EN_CHANGE, CBN_SELCHANGE
      UiFireClick(UiCtlFind(lp));
    return 0;
  case WM_HSCROLL:
  case WM_VSCROLL:
    UiFireClick(UiCtlFind(lp));
    return 0;
  case WM_TIMER:
    UiFireClick(UiCtlFind(wp));
    if (wp >= 90000)  // one-shot (UiQueueMain) ids live at 90000+
      KillTimer(hwnd, wp);
    return 0;
  case 5:  // WM_SIZE: reflow the window's children
    UiLayout(UiCtlFind(hwnd));
    return 0;
  case 0x4E:  // WM_NOTIFY: lParam->NMHDR{hwndFrom@0, idFrom@8, code@16}
  {
    I64 *nm = lp;
    I64 code = nm[2](I32);
    if (code == -101 || code == -402)  // LVN_ITEMCHANGED / TVN_SELCHANGEDA
      UiFireClick(UiCtlFind(nm[0]));   // hwndFrom
    return DefWindowProcA(hwnd, msg, wp, lp);
  }
  case WM_DESTROY:
    ui_nwin--;
    if (ui_nwin <= 0)
      PostQuitMessage(0);
    return 0;
  }
  return DefWindowProcA(hwnd, msg, wp, lp);
}

// dialog windows: route child commands, close ends the modal loop
I64 UiDlgProc(I64 hwnd, I64 msg, I64 wp, I64 lp)
{
  I64 code = wp >> 16 & 0xFFFF;
  if (msg == WM_COMMAND && lp && code == 0) {
    UiFireClick(UiCtlFind(lp));
    return 0;
  }
  if (msg == 0x10) {  // WM_CLOSE
    ui_dlg_done = 1;
    return 0;
  }
  return DefWindowProcA(hwnd, msg, wp, lp);
}

I64 UiCanvasProc(I64 hwnd, I64 msg, I64 wp, I64 lp)
{
  U8 ps[80];
  if (msg == WM_PAINT) {
    ui_hdc = BeginPaint(hwnd, ps);
    UiFireClick(UiCtlFind(hwnd));
    if (ui_brush)
      DeleteObject(ui_brush);
    if (ui_pen)
      DeleteObject(ui_pen);
    ui_brush = ui_pen = ui_hdc = 0;
    EndPaint(hwnd, ps);
    return 0;
  }
  return DefWindowProcA(hwnd, msg, wp, lp);
}

U0 UiInit()
{
  ui_inst = GetModuleHandleA(0);
  U8 icc[8];
  I32 *ip = icc;
  ip[0] = 8;
  ip[1] = 0x24;  // ICC_BAR_CLASSES | ICC_PROGRESS_CLASS
  InitCommonControlsEx(icc);
  ui_wc.size = sizeof(UiWndClass);
  ui_wc.style = 3;  // CS_HREDRAW | CS_VREDRAW
  ui_wc.wndproc = &UiWndProc;
  ui_wc.inst = ui_inst;
  ui_wc.cursor = LoadCursorA(0, 32512);  // IDC_ARROW
  ui_wc.background = 6;                  // COLOR_WINDOW + 1
  ui_wc.class_name = "UiWin";
  if (!RegisterClassExA(&ui_wc)(U16))
    Exit(1);
  ui_cwc.size = sizeof(UiWndClass);
  ui_cwc.wndproc = &UiCanvasProc;
  ui_cwc.inst = ui_inst;
  ui_cwc.cursor = ui_wc.cursor;
  ui_cwc.class_name = "UiCanvasC";
  if (!RegisterClassExA(&ui_cwc)(U16))
    Exit(1);
  ui_dwc.size = sizeof(UiWndClass);
  ui_dwc.wndproc = &UiDlgProc;
  ui_dwc.inst = ui_inst;
  ui_dwc.cursor = ui_wc.cursor;
  ui_dwc.background = 6;
  ui_dwc.class_name = "UiDlg";
  if (!RegisterClassExA(&ui_dwc)(U16))
    Exit(1);
}

U0 UiQuit()
{
  PostQuitMessage(0);
}

UiCtl *UiWindowNew(U8 *title, I64 w=480, I64 h=320)
{
  ui_hwnd = CreateWindowExA(0, "UiWin", title, WS_OVERLAPPEDWINDOW,
    CW_USEDEFAULT, CW_USEDEFAULT, w, h, 0, 0, ui_inst, 0);
  ui_nwin++;
  UiCtl *c = UiCtlNew(UI_WINDOW, ui_hwnd);
  c->w = w;
  c->h = h;
  return c;
}

U0 UiMsgBox(U8 *title, U8 *body)
{
  MessageBoxA(ui_hwnd, body, title, 0x40);  // MB_ICONINFORMATION
}

U0 UiWarnBox(U8 *title, U8 *body)
{
  MessageBoxA(ui_hwnd, body, title, 0x30);  // MB_ICONWARNING
}

U8 *UiOpenFile()
{
  UiOfn ofn;
  MemSet(&ofn, 0, sizeof(UiOfn));
  U8 *buf = MAlloc(1024);
  buf[0] = 0;
  ofn.size = sizeof(UiOfn);
  ofn.owner = ui_hwnd;
  ofn.file = buf;
  ofn.maxfile = 1024;
  ofn.flags = 0x1800;  // OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST
  if (!GetOpenFileNameA(&ofn)(I32)) {
    Free(buf);
    return NULL;
  }
  return buf;
}

U0 UiW32PromptOk(UiCtl *c, U0 *entry)
{
  I64 h = entry;
  I64 n = GetWindowTextLengthA(h)(I32) + 1;
  ui_dlg_text = MAlloc(n);
  GetWindowTextA(h, ui_dlg_text, n);
  ui_dlg_done = 1;
}

U8 *UiPrompt(U8 *title, U8 *body, U8 *init="")
{
  I64 win = CreateWindowExA(0, "UiDlg", title, 0xCA0000,  // caption+sysmenu
    CW_USEDEFAULT, CW_USEDEFAULT, 320, 180, ui_hwnd, 0, ui_inst, 0);
  I64 lbl = CreateWindowExA(0, "STATIC", body, WS_CHILD_VISIBLE,
    20, 15, 260, 22, win, 0, ui_inst, 0);
  I64 entry = CreateWindowExA(0x200, "EDIT", init, WS_CHILD_VISIBLE | 0x80,
    20, 45, 260, 24, win, 0, ui_inst, 0);
  I64 okh = CreateWindowExA(0, "BUTTON", "OK", WS_CHILD_VISIBLE,
    100, 85, 100, 28, win, 0, ui_inst, 0);
  UiCtl *ok = UiCtlNew(UI_BUTTON, okh);
  UiOnClick(ok, &UiW32PromptOk, entry);
  ShowWindow(win, SW_SHOW);
  ui_dlg_done = 0;
  ui_dlg_text = 0;
  U8 m[64];
  while (!ui_dlg_done && GetMessageA(m, 0, 0, 0)(I32) > 0) {
    TranslateMessage(m);
    DispatchMessageA(m);
  }
  DestroyWindow(win);
  return ui_dlg_text;
}

UiCtl *UiBoxNew(Bool vertical=TRUE)
{
  return UiCtlNew(UI_BOX, 0);
}

UiCtl *UiGridNew()
{
  return UiCtlNew(UI_GRID, 0);
}

U0 UiGridAdd(UiCtl *g, UiCtl *c, I64 col, I64 row)
{
  c->col = col;
  c->row = row;
  UiKidAdd(g, c);
}

UiCtl *UiLabelNew(U8 *text="")
{
  I64 h = CreateWindowExA(0, "STATIC", text, WS_CHILD_VISIBLE,
    0, 0, 10, 10, ui_hwnd, 0, ui_inst, 0);
  return UiCtlNew(UI_LABEL, h);
}

U0 UiLabelSetText(UiCtl *l, U8 *text)
{
  SetWindowTextA(l->native, text);
}

UiCtl *UiButtonNew(U8 *text)
{
  I64 h = CreateWindowExA(0, "BUTTON", text, WS_CHILD_VISIBLE,
    0, 0, 10, 10, ui_hwnd, 0, ui_inst, 0);
  return UiCtlNew(UI_BUTTON, h);
}

UiCtl *UiEntryNew(U8 *text="")
{
  I64 h = CreateWindowExA(0x200, "EDIT", text,  // WS_EX_CLIENTEDGE
    WS_CHILD_VISIBLE | 0x80,                    // ES_AUTOHSCROLL
    0, 0, 10, 10, ui_hwnd, 0, ui_inst, 0);
  return UiCtlNew(UI_ENTRY, h);
}

U8 *UiEntryText(UiCtl *e)
{
  I64 n = GetWindowTextLengthA(e->native)(I32) + 1;
  U8 *buf = MAlloc(n);
  GetWindowTextA(e->native, buf, n);
  return buf;
}

U0 UiEntrySetText(UiCtl *e, U8 *text)
{
  SetWindowTextA(e->native, text);
}

UiCtl *UiCheckboxNew(U8 *text, Bool checked=FALSE)
{
  I64 h = CreateWindowExA(0, "BUTTON", text,
    WS_CHILD_VISIBLE | BS_AUTOCHECKBOX, 0, 0, 10, 10, ui_hwnd, 0, ui_inst, 0);
  SendMessageA(h, BM_SETCHECK, checked, 0);
  return UiCtlNew(UI_CHECKBOX, h);
}

Bool UiCheckboxChecked(UiCtl *c)
{
  return SendMessageA(c->native, BM_GETCHECK, 0, 0) & 1;
}

UiCtl *UiSliderNew(I64 min=0, I64 max=100)
{
  I64 h = CreateWindowExA(0, "msctls_trackbar32", "", WS_CHILD_VISIBLE,
    0, 0, 10, 10, ui_hwnd, 0, ui_inst, 0);
  SendMessageA(h, TBM_SETRANGEMIN, 1, min);
  SendMessageA(h, TBM_SETRANGEMAX, 1, max);
  return UiCtlNew(UI_SLIDER, h);
}

I64 UiSliderValue(UiCtl *s)
{
  return SendMessageA(s->native, TBM_GETPOS, 0, 0)(I32);
}

UiCtl *UiProgressNew()
{
  I64 h = CreateWindowExA(0, "msctls_progress32", "", WS_CHILD_VISIBLE,
    0, 0, 10, 10, ui_hwnd, 0, ui_inst, 0);
  SendMessageA(h, PBM_SETRANGE32, 0, 100);
  return UiCtlNew(UI_PROGRESS, h);
}

U0 UiProgressSet(UiCtl *p, I64 percent)
{
  SendMessageA(p->native, PBM_SETPOS, percent, 0);
}

UiCtl *UiSeparatorNew()
{
  I64 h = CreateWindowExA(0, "STATIC", "", WS_CHILD_VISIBLE | 0x10, // SS_ETCHEDHORZ
    0, 0, 10, 2, ui_hwnd, 0, ui_inst, 0);
  return UiCtlNew(UI_SEP, h);
}

UiCtl *UiCanvasNew(I64 w, I64 h, U0 *drawfn, U0 *data=NULL)
{
  I64 hw = CreateWindowExA(0, "UiCanvasC", "", WS_CHILD_VISIBLE,
    0, 0, w, h, ui_hwnd, 0, ui_inst, 0);
  UiCtl *c = UiCtlNew(UI_CANVAS, hw);
  c->w = w;
  c->h = h;
  UiOnClick(c, drawfn, data);
  return c;
}

U0 UiCanvasRedraw(UiCtl *c)
{
  InvalidateRect(c->native, 0, 1);
}

U0 UiSetColor(F64 r, F64 g, F64 b)
{
  I64 ri = r * 255.0, gi = g * 255.0, bi = b * 255.0;
  I64 color = ri | gi << 8 | bi << 16;
  if (ui_brush)
    DeleteObject(ui_brush);
  if (ui_pen)
    DeleteObject(ui_pen);
  ui_brush = CreateSolidBrush(color);
  ui_pen = CreatePen(0, 1, color);
  SelectObject(ui_hdc, ui_pen);
}

U0 UiFillRect(F64 x, F64 y, F64 w, F64 h)
{
  U8 rc[16];
  I32 *p = rc;
  p[0] = x;
  p[1] = y;
  p[2] = x + w;
  p[3] = y + h;
  FillRect(ui_hdc, rc, ui_brush);
}

U0 UiLine(F64 x1, F64 y1, F64 x2, F64 y2)
{
  I64 a = x1, b = y1, c = x2, d = y2;
  MoveToEx(ui_hdc, a, b, 0);
  LineTo(ui_hdc, c, d);
}

UiCtl *UiMenuNew(U8 *title)
{
  if (!ui_menubar)
    ui_menubar = CreateMenu;
  I64 m = CreatePopupMenu;
  AppendMenuA(ui_menubar, MF_POPUP, m, title);
  SetMenu(ui_hwnd, ui_menubar);
  return UiCtlNew(UI_MENU, m);
}

UiCtl *UiMenuItem(UiCtl *m, U8 *label, U0 *fn, U0 *data=NULL)
{
  I64 id = ++ui_menuid;
  AppendMenuA(m->native, 0, id, label);
  UiCtl *c = UiCtlNew(UI_MENUITEM, id);
  UiOnClick(c, fn, data);
  return c;
}

UiCtl *UiComboNew()
{
  I64 h = CreateWindowExA(0, "COMBOBOX", "",
    WS_CHILD_VISIBLE | 3 | 0x200000,  // CBS_DROPDOWNLIST | WS_VSCROLL
    0, 0, 10, 200, ui_hwnd, 0, ui_inst, 0);
  return UiCtlNew(UI_COMBO, h);
}

U0 UiComboAdd(UiCtl *c, U8 *text)
{
  SendMessageA(c->native, 0x143, 0, text);  // CB_ADDSTRING
}

I64 UiComboSelected(UiCtl *c)
{
  return SendMessageA(c->native, 0x147, 0, 0)(I32);  // CB_GETCURSEL
}

UiCtl *UiRadioNew()
{
  UiCtl *c = UiCtlNew(UI_RADIO, 0);
  return c;
}

U0 UiRadioAdd(UiCtl *r, U8 *text)
{
  I64 style = WS_CHILD_VISIBLE | 9;  // BS_AUTORADIOBUTTON
  if (!r->kids)
    style |= 0x20000;  // WS_GROUP on the first button
  I64 h = CreateWindowExA(0, "BUTTON", text, style,
    0, 0, 10, 22, ui_hwnd, 0, ui_inst, 0);
  UiKidAdd(r, UiCtlNew(UI_BUTTON, h));
}

I64 UiRadioSelected(UiCtl *r)
{
  I64 i = 0;
  UiCtl *k = r->kids;
  while (k) {
    if (SendMessageA(k->native, BM_GETCHECK, 0, 0) & 1)
      return i;
    i++;
    k = k->sib;
  }
  return -1;
}

UiCtl *UiSpinNew(I64 min=0, I64 max=100)
{
  I64 ed = CreateWindowExA(0x200, "EDIT", "0", WS_CHILD_VISIBLE | 0x2000, // ES_NUMBER
    0, 0, 10, 24, ui_hwnd, 0, ui_inst, 0);
  I64 ud = CreateWindowExA(0, "msctls_updown32", "",
    WS_CHILD_VISIBLE | 0x28,  // UDS_SETBUDDYINT | UDS_ALIGNRIGHT
    0, 0, 0, 0, ui_hwnd, 0, ui_inst, 0);
  SendMessageA(ud, 0x469, ed, 0);          // UDM_SETBUDDY
  SendMessageA(ud, 0x467, 0, max << 16 | min & 0xFFFF);  // UDM_SETRANGE
  UiCtl *c = UiCtlNew(UI_SPIN, ud);
  c->col = ed;
  return c;
}

I64 UiSpinValue(UiCtl *s)
{
  return SendMessageA(s->native, 0x468, 0, 0)(I32);  // UDM_GETPOS
}

UiCtl *UiMultilineNew(U8 *text="")
{
  I64 h = CreateWindowExA(0x200, "EDIT", text,
    WS_CHILD_VISIBLE | 0xC4,  // ES_MULTILINE | ES_AUTOVSCROLL | WS_VSCROLL-ish
    0, 0, 10, 80, ui_hwnd, 0, ui_inst, 0);
  return UiCtlNew(UI_MULTILINE, h);
}

UiCtl *UiPasswordNew(U8 *text="")
{
  I64 h = CreateWindowExA(0x200, "EDIT", text,
    WS_CHILD_VISIBLE | 0x20,  // ES_PASSWORD
    0, 0, 10, 24, ui_hwnd, 0, ui_inst, 0);
  return UiCtlNew(UI_ENTRY, h);
}

UiCtl *UiGroupNew(U8 *title)
{
  I64 h = CreateWindowExA(0, "BUTTON", title, WS_CHILD_VISIBLE | 7,  // BS_GROUPBOX
    0, 0, 10, 60, ui_hwnd, 0, ui_inst, 0);
  return UiCtlNew(UI_GROUP, h);
}

U0 UiGroupSetChild(UiCtl *g, UiCtl *child)
{
  g->kids = child;
}

UiCtl *UiTabNew()
{
  I64 h = CreateWindowExA(0, "SysTabControl32", "", WS_CHILD_VISIBLE,
    0, 0, 10, 200, ui_hwnd, 0, ui_inst, 0);
  return UiCtlNew(UI_TAB, h);
}

U0 UiTabAdd(UiCtl *t, U8 *label, UiCtl *child)
{
  U8 item[40];
  MemSet(item, 0, 40);
  I32 *ip = item;
  ip[0] = 1;      // TCIF_TEXT
  I64 *pp = &item[8];
  pp[0] = label;  // pszText
  I64 n = 0;
  UiCtl *k = t->kids;
  while (k) { n++; k = k->sib; }
  SendMessageA(t->native, 0x133D, n, item);  // TCM_INSERTITEMA
  UiKidAdd(t, child);
}

U0 UiEnable(UiCtl *c, Bool on)
{
  EnableWindow(c->native, on);
}

U0 UiSetVisible(UiCtl *c, Bool on)
{
  I64 cmd = 0;
  if (on)
    cmd = SW_SHOW;
  ShowWindow(c->native, cmd);
}

U0 UiTimer(I64 ms, U0 *fn, U0 *data=NULL)
{
  UiCtl *t = UiCtlNew(UI_TIMER, ++ui_timerid);
  UiOnClick(t, fn, data);
  SetTimer(ui_hwnd, ui_timerid, ms, 0);
}

U0 UiQueueMain(U0 *fn, U0 *data=NULL)
{
  UiCtl *t = UiCtlNew(UI_TIMER, ++ui_onceid);
  UiOnClick(t, fn, data);
  SetTimer(ui_hwnd, ui_onceid, 0, 0);
}

UiCtl *UiToolbarNew()
{
  return UiCtlNew(UI_TOOLBAR, 0);
}

U0 UiToolAdd(UiCtl *tb, U8 *label, U0 *fn, U0 *data=NULL)
{
  I64 h = CreateWindowExA(0, "BUTTON", label, WS_CHILD_VISIBLE,
    0, 0, 10, 10, ui_hwnd, 0, ui_inst, 0);
  UiCtl *c = UiCtlNew(UI_BUTTON, h);
  UiOnClick(c, fn, data);
  UiKidAdd(tb, c);
}

UiCtl *UiStatusbarNew(U8 *text="")
{
  I64 h = CreateWindowExA(0, "msctls_statusbar32", text, WS_CHILD_VISIBLE,
    0, 0, 0, 0, ui_hwnd, 0, ui_inst, 0);
  return UiCtlNew(UI_STATUS, h);
}

U0 UiStatusSet(UiCtl *sb, U8 *text)
{
  SendMessageA(sb->native, 0x401, 0, text);   // SB_SETTEXTA, part 0
}

UiCtl *UiSplitNew(Bool vertical=FALSE)
{
  UiCtl *c = UiCtlNew(UI_SPLIT, 0);
  c->col = vertical;
  return c;
}

U0 UiSplitAdd(UiCtl *sp, UiCtl *child)
{
  UiKidAdd(sp, child);
}

// no native wrapper: EDIT/LISTBOX-style children scroll themselves; a
// plain control just passes through as its own scroller
UiCtl *UiScrollNew(UiCtl *child)
{
  return child;
}

// Win64 LVCOLUMNA / LVITEMA, laid out with natural C alignment
/* @align */ class UiLvCol
{
  U32 mask, fmt, cx;
  U8 *text;          // @16
  U32 cch, subitem;
};

/* @align */ class UiLvItem
{
  U32 mask, item, subitem, state, statemask;
  U8 *text;          // @24
  U32 cch, image;
  I64 lparam;        // @40
};

UiCtl *UiTableNew(U0 *cellfn, U0 *data=NULL)
{
  I64 h = CreateWindowExA(0, "SysListView32", "",
    WS_CHILD_VISIBLE | 0x1 | 0xC000,  // LVS_REPORT | WS_BORDER-ish
    0, 0, 10, 200, ui_hwnd, 0, ui_inst, 0);
  SendMessageA(h, 0x1036, 0, 0x20 | 0x1);  // LVM_SETEXTENDEDLISTVIEWSTYLE: FULLROWSELECT|GRIDLINES
  UiCtl *c = UiCtlNew(UI_TABLE, h);
  c->cellfn = cellfn;
  c->celldata = data;
  return c;
}

U0 UiTableColumn(UiCtl *t, U8 *title)
{
  UiLvCol col;
  MemSet(&col, 0, sizeof(UiLvCol));
  col.mask = 0x5;  // LVCF_TEXT | LVCF_WIDTH
  col.cx = 120;
  col.text = title;
  col.subitem = t->w;
  SendMessageA(t->native, 0x101B, t->w, &col);  // LVM_INSERTCOLUMNA
  t->w++;
}

U0 UiTableSetRows(UiCtl *t, I64 nrows)
{
  UiLvItem it;
  I64 r = 0, c;
  t->row = nrows;
  SendMessageA(t->native, 0x1009, 0, 0);  // LVM_DELETEALLITEMS
  while (r < nrows) {
    MemSet(&it, 0, sizeof(UiLvItem));
    it.mask = 0x1;  // LVIF_TEXT
    it.item = r;
    it.text = UiTableCell(t, r, 0);
    SendMessageA(t->native, 0x1007, 0, &it);  // LVM_INSERTITEMA
    c = 1;
    while (c < t->w) {
      MemSet(&it, 0, sizeof(UiLvItem));
      it.item = r;
      it.subitem = c;
      it.text = UiTableCell(t, r, c);
      SendMessageA(t->native, 0x1006, r, &it);  // LVM_SETITEMTEXTA
      c++;
    }
    r++;
  }
}

I64 UiTableSelected(UiCtl *t)
{
  return SendMessageA(t->native, 0x100C, -1, 8)(I32);  // LVM_GETNEXTITEM, LVNI_SELECTED
}

// TVINSERTSTRUCTA: { HTREEITEM hParent; HTREEITEM hInsertAfter;
//   TVITEMA item{ UINT mask; HTREEITEM hItem; UINT state, stateMask;
//   LPSTR pszText; ... } } laid out with natural C alignment
/* @align */ class UiTvIns
{
  I64 parent, after;
  U32 mask;
  U32 pad;
  I64 hitem;
  U32 state, statemask;
  U8 *text;
  I64 rest[6];
};

UiCtl *UiTreeNew()
{
  I64 h = CreateWindowExA(0, "SysTreeView32", "",
    WS_CHILD_VISIBLE | 0x1 | 0x20 | 0x4,  // TVS_HASBUTTONS|TVS_HASLINES|TVS_LINESATROOT
    0, 0, 10, 200, ui_hwnd, 0, ui_inst, 0);
  UiCtl *c = UiCtlNew(UI_TREE, h);
  return c;
}

UiCtl *UiTreeAdd(UiCtl *t, UiCtl *parent, U8 *label)
{
  UiTvIns ins;
  MemSet(&ins, 0, sizeof(UiTvIns));
  ins.parent = 0;
  if (parent)
    ins.parent = parent->native;
  ins.after = -0x10000;   // TVI_LAST
  ins.mask = 0x1;         // TVIF_TEXT
  ins.text = label;
  I64 h = SendMessageA(t->native, 0x1132, 0, &ins);  // TVM_INSERTITEMA
  UiCtl *n = UiCtlNew(UI_TREENODE, h);
  n->celldata = StrNew(label);
  return n;
}

UiCtl *UiTreeSelected(UiCtl *t)
{
  I64 h = SendMessageA(t->native, 0x100A, 9, 0);  // TVM_GETNEXTITEM, TVGN_CARET
  if (!h)
    return NULL;
  UiCtl *c = ui_ctls;
  while (c) {
    if (c->kind == UI_TREENODE && c->native == h)
      return c;
    c = c->reg;
  }
  return NULL;
}

U0 UiBoxAdd(UiCtl *box, UiCtl *c)
{
  UiKidAdd(box, c);
}

U0 UiWindowSetChild(UiCtl *w, UiCtl *c)
{
  w->kids = c;
}

// one layout pass over the top container's children; re-runnable so
// WM_SIZE can reflow. A grid consumes a band of rows, a toolbar a row of
// buttons, a split two side-by-side panes, a canvas its own height; a
// native status bar auto-docks and is skipped.
U0 UiLayout(UiCtl *w)
{
  U8 rc[16];
  GetClientRect(w->native, rc);
  I32 *p = rc;
  I64 width = p[2], height = p[3], y = 20;
  UiCtl *box = w->kids;
  UiCtl *c = NULL;
  if (box)
    c = box->kids;
  while (c) {
    if (c->kind == UI_GRID) {
      I64 ncol = 0, nrow = 0;
      UiCtl *k = c->kids;
      while (k) {
        if (k->col >= ncol)
          ncol = k->col + 1;
        if (k->row >= nrow)
          nrow = k->row + 1;
        k = k->sib;
      }
      I64 cw = (width - 40) / ncol;
      k = c->kids;
      while (k) {
        MoveWindow(k->native, 20 + k->col * cw, y + k->row * 38, cw - 10, 28, 1);
        k = k->sib;
      }
      y += nrow * 38;
    } else if (c->kind == UI_TOOLBAR) {
      I64 x = 20;
      UiCtl *k = c->kids;
      while (k) {
        MoveWindow(k->native, x, y, 80, 28, 1);
        x += 88;
        k = k->sib;
      }
      y += 40;
    } else if (c->kind == UI_SPLIT) {
      I64 paneh = height - y - 40, i = 0;
      I64 half = (width - 40) / 2;
      UiCtl *k = c->kids;
      while (k) {
        MoveWindow(k->native, 20 + i * (half + 10), y, half - 10, paneh, 1);
        i++;
        k = k->sib;
      }
      y += paneh + 10;
    } else if (c->kind == UI_STATUS) {
      SendMessageA(c->native, 5, 0, 0);  // WM_SIZE: the status bar auto-docks
    } else if (c->kind == UI_RADIO) {
      UiCtl *k = c->kids;
      while (k) {
        MoveWindow(k->native, 20, y, width - 40, 22, 1);
        y += 26;
        k = k->sib;
      }
      y += 12;
    } else if (c->kind == UI_MULTILINE) {
      MoveWindow(c->native, 20, y, width - 40, 80, 1);
      y += 90;
    } else if (c->kind == UI_TABLE || c->kind == UI_TREE) {
      I64 th = height - y - 50;
      if (th < 80)
        th = 80;
      MoveWindow(c->native, 20, y, width - 40, th, 1);
      y += th + 10;
    } else if (c->kind == UI_CANVAS) {
      MoveWindow(c->native, 20, y, c->w, c->h, 1);
      y += c->h + 10;
    } else if (c->kind == UI_SEP) {
      MoveWindow(c->native, 20, y, width - 40, 2, 1);
      y += 12;
    } else {
      MoveWindow(c->native, 20, y, width - 40, 28, 1);
      y += 38;
    }
    c = c->sib;
  }
}

U0 UiShow(UiCtl *w)
{
  UiLayout(w);
  ShowWindow(w->native, SW_SHOW);
}

U0 UiMain()
{
  U8 m[64];
  while (GetMessageA(m, 0, 0, 0)(I32) > 0) {
    TranslateMessage(m);
    DispatchMessageA(m);
  }
}
