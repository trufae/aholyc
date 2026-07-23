// Cocoa/AppKit backend for ui.hc (macOS)
// objc_msgSend is dlsym'd into typed function pointers, one per ABI shape;
// rect/CGFloat arguments must be F64-typed expressions (float registers).
// @ldflags=-framework AppKit -framework CoreGraphics -lobjc

extern I64 dlsym(I64 handle, U8 *name);
extern I64 objc_getClass(U8 *name);
extern I64 sel_registerName(U8 *name);
extern I64 objc_allocateClassPair(I64 super, U8 *name, I64 extra);
extern U0 objc_registerClassPair(I64 cls);
extern I64 class_addMethod(I64 cls, I64 sel, I64 imp, U8 *types);
extern U0 CGContextSetRGBFillColor(I64 c, F64 r, F64 g, F64 b, F64 a);
extern U0 CGContextSetRGBStrokeColor(I64 c, F64 r, F64 g, F64 b, F64 a);
extern U0 CGContextFillRect(I64 c, F64 x, F64 y, F64 w, F64 h);
extern U0 CGContextMoveToPoint(I64 c, F64 x, F64 y);
extern U0 CGContextAddLineToPoint(I64 c, F64 x, F64 y);
extern U0 CGContextStrokePath(I64 c);
extern U0 CGContextSetLineWidth(I64 c, F64 w);

I64 (*ui_msg)(I64 self, I64 sel, I64 a, I64 b, I64 c);
I64 (*ui_msgf)(I64 self, I64 sel, F64 x, F64 y, F64 w, F64 h, I64 a, I64 b, I64 c);
// interval(d0) then four integer args (x2..x5): NSTimer scheduling
I64 (*ui_msgt)(I64 self, I64 sel, F64 iv, I64 tgt, I64 s2, I64 ui, I64 rep);
I64 ui_app, ui_target, ui_timer_tgt, ui_tbl_src, ui_tree_src, ui_mainmenu = 0;
I64 ui_cg = 0;  // CGContext, valid inside a draw callback

I64 UiSel(U8 *name) { return sel_registerName(name); }
I64 UiCls(U8 *name) { return objc_getClass(name); }
I64 UiStr(U8 *s)
{
  return ui_msg(UiCls("NSString"), UiSel("stringWithUTF8String:"), s, 0, 0);
}

U0 UiFrame(I64 view, F64 x, F64 y, F64 w, F64 h)
{
  ui_msg(view, UiSel("setTranslatesAutoresizingMaskIntoConstraints:"), 1, 0, 0);
  ui_msgf(view, UiSel("setFrame:"), x, y, w, h, 0, 0, 0);
}

// pin one autolayout dimension so views keep a size inside NSStackView
U0 UiPin(I64 view, U8 *anchor, I64 px)
{
  F64 f = px;
  I64 con = ui_msgf(ui_msg(view, UiSel(anchor), 0, 0, 0),
    UiSel("constraintEqualToConstant:"), f, 0.0, 0.0, 0.0, 0, 0, 0);
  ui_msg(con, UiSel("setActive:"), 1, 0, 0);
}

U0 UiCocoaClick(I64 self, I64 cmd, I64 sender)
{
  UiFireClick(UiCtlFind(sender));
}

U0 UiCocoaTextChange(I64 self, I64 cmd, I64 notif)
{
  UiFireClick(UiCtlFind(ui_msg(notif, UiSel("object"), 0, 0, 0)));
}

I64 UiCocoaLastClose(I64 self, I64 cmd, I64 sender)
{
  return 1;  // quit when the last window closes
}

I64 UiCocoaFlipped(I64 self, I64 cmd)
{
  return 1;  // top-left canvas origin, like the gtk4/win32 backends
}

// NSTimer target: the timer's userInfo is our UiCtl boxed in an NSValue
// (NSTimer retains userInfo, so it must be a real ObjC object, never a
// raw HolyC pointer)
U0 UiCocoaTick(I64 self, I64 cmd, I64 timer)
{
  I64 box = ui_msg(timer, UiSel("userInfo"), 0, 0, 0);
  UiFireClick(ui_msg(box, UiSel("pointerValue"), 0, 0, 0));
}

U0 UiCocoaDraw(I64 self, I64 cmd, F64 x, F64 y, F64 w, F64 h)
{
  I64 nsctx = ui_msg(UiCls("NSGraphicsContext"), UiSel("currentContext"), 0, 0, 0);
  ui_cg = ui_msg(nsctx, UiSel("CGContext"), 0, 0, 0);
  UiFireClick(UiCtlFind(self));
  ui_cg = 0;
}

// find a table/tree by its inner view (stashed in ->col; ->native is the
// enclosing scroll view)
UiCtl *UiByCol(I64 h)
{
  UiCtl *c = ui_ctls;
  while (c) {
    if (c->col == h)
      return c;
    c = c->reg;
  }
  return NULL;
}

// NSOutlineView retains its items and keys expansion state on their
// identity, so each node is a real ObjC object: an NSValue boxing the
// UiCtl* (cached in node->native). Unbox to reach the node.
UiCtl *UiUnbox(I64 item)
{
  return ui_msg(item, UiSel("pointerValue"), 0, 0, 0)(UiCtl *);
}

// children of an item (nil item = the tree root)
UiCtl *UiTreeKids(I64 ov, I64 item)
{
  if (item)
    return UiUnbox(item)->kids;
  UiCtl *t = UiByCol(ov);
  if (t)
    return t->kids;
  return NULL;
}

I64 UiCocoaTreeCount(I64 self, I64 cmd, I64 ov, I64 item)
{
  I64 n = 0;
  UiCtl *k = UiTreeKids(ov, item);
  while (k) {
    n++;
    k = k->sib;
  }
  return n;
}

I64 UiCocoaTreeChild(I64 self, I64 cmd, I64 ov, I64 idx, I64 item)
{
  UiCtl *k = UiTreeKids(ov, item);
  while (idx > 0 && k) {
    k = k->sib;
    idx--;
  }
  if (!k)
    return 0;
  return k->native;   // the node's cached NSValue box
}

I64 UiCocoaTreeExpandable(I64 self, I64 cmd, I64 ov, I64 item)
{
  if (item && UiUnbox(item)->kids)
    return 1;
  return 0;
}

I64 UiCocoaTreeValue(I64 self, I64 cmd, I64 ov, I64 column, I64 item)
{
  return UiStr(UiUnbox(item)->celldata);
}

U0 UiCocoaTreeSel(I64 self, I64 cmd, I64 notif)
{
  UiFireClick(UiByCol(ui_msg(notif, UiSel("object"), 0, 0, 0)));
}

I64 UiCocoaRowCount(I64 self, I64 cmd, I64 tv)
{
  UiCtl *t = UiByCol(tv);
  if (!t)
    return 0;
  return t->row;
}

I64 UiCocoaCellValue(I64 self, I64 cmd, I64 tv, I64 column, I64 rowidx)
{
  UiCtl *t = UiByCol(tv);
  I64 col = ui_msg(ui_msg(column, UiSel("identifier"), 0, 0, 0),
    UiSel("integerValue"), 0, 0, 0);
  return UiStr(UiTableCell(t, rowidx, col));
}

U0 UiCocoaSelChanged(I64 self, I64 cmd, I64 notif)
{
  UiFireClick(UiByCol(ui_msg(notif, UiSel("object"), 0, 0, 0)));
}

U0 UiInit()
{
  ui_msg = ui_msgf = ui_msgt = dlsym(-2, "objc_msgSend");
  ui_msg(ui_msg(UiCls("NSAutoreleasePool"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_app = ui_msg(UiCls("NSApplication"), UiSel("sharedApplication"), 0, 0, 0);
  ui_msg(ui_app, UiSel("setActivationPolicy:"), 0, 0, 0);
  I64 dcls = objc_allocateClassPair(UiCls("NSObject"), "UiDelegate", 0);
  class_addMethod(dcls, UiSel("applicationShouldTerminateAfterLastWindowClosed:"),
    &UiCocoaLastClose, "c@:@");
  objc_registerClassPair(dcls);
  ui_msg(ui_app, UiSel("setDelegate:"),
    ui_msg(ui_msg(dcls, UiSel("alloc"), 0, 0, 0), UiSel("init"), 0, 0, 0), 0, 0);
  I64 tcls = objc_allocateClassPair(UiCls("NSObject"), "UiTarget", 0);
  class_addMethod(tcls, UiSel("clicked:"), &UiCocoaClick, "v@:@");
  class_addMethod(tcls, UiSel("controlTextDidChange:"), &UiCocoaTextChange, "v@:@");
  objc_registerClassPair(tcls);
  ui_target = ui_msg(ui_msg(tcls, UiSel("alloc"), 0, 0, 0), UiSel("init"), 0, 0, 0);
  I64 tmcls = objc_allocateClassPair(UiCls("NSObject"), "UiTimerTgt", 0);
  class_addMethod(tmcls, UiSel("tick:"), &UiCocoaTick, "v@:@");
  objc_registerClassPair(tmcls);
  ui_timer_tgt = ui_msg(ui_msg(tmcls, UiSel("alloc"), 0, 0, 0), UiSel("init"), 0, 0, 0);
  I64 ccls = objc_allocateClassPair(UiCls("NSView"), "UiCanvasV", 0);
  class_addMethod(ccls, UiSel("drawRect:"), &UiCocoaDraw,
    "v@:{CGRect={CGPoint=dd}{CGSize=dd}}");
  class_addMethod(ccls, UiSel("isFlipped"), &UiCocoaFlipped, "c@:");
  objc_registerClassPair(ccls);
  // NSTableView data source + delegate (pull model)
  I64 scls = objc_allocateClassPair(UiCls("NSObject"), "UiTblSrc", 0);
  class_addMethod(scls, UiSel("numberOfRowsInTableView:"),
    &UiCocoaRowCount, "q@:@");
  class_addMethod(scls, UiSel("tableView:objectValueForTableColumn:row:"),
    &UiCocoaCellValue, "@@:@@q");
  class_addMethod(scls, UiSel("tableViewSelectionDidChange:"),
    &UiCocoaSelChanged, "v@:@");
  objc_registerClassPair(scls);
  ui_tbl_src = ui_msg(ui_msg(scls, UiSel("alloc"), 0, 0, 0), UiSel("init"), 0, 0, 0);
  // NSOutlineView data source + delegate (tree pull model)
  I64 ocls = objc_allocateClassPair(UiCls("NSObject"), "UiTreeSrc", 0);
  class_addMethod(ocls, UiSel("outlineView:numberOfChildrenOfItem:"),
    &UiCocoaTreeCount, "q@:@@");
  class_addMethod(ocls, UiSel("outlineView:child:ofItem:"),
    &UiCocoaTreeChild, "@@:@q@");
  class_addMethod(ocls, UiSel("outlineView:isItemExpandable:"),
    &UiCocoaTreeExpandable, "c@:@@");
  class_addMethod(ocls, UiSel("outlineView:objectValueForTableColumn:byItem:"),
    &UiCocoaTreeValue, "@@:@@@");
  class_addMethod(ocls, UiSel("outlineViewSelectionDidChange:"),
    &UiCocoaTreeSel, "v@:@");
  objc_registerClassPair(ocls);
  ui_tree_src = ui_msg(ui_msg(ocls, UiSel("alloc"), 0, 0, 0), UiSel("init"), 0, 0, 0);
}

U0 UiQuit()
{
  ui_msg(ui_app, UiSel("terminate:"), 0, 0, 0);
}

UiCtl *UiWindowNew(U8 *title, I64 w=480, I64 h=320)
{
  F64 fw = w, fh = h;
  I64 win = ui_msgf(ui_msg(UiCls("NSWindow"), UiSel("alloc"), 0, 0, 0),
    UiSel("initWithContentRect:styleMask:backing:defer:"),
    0.0, 0.0, fw, fh, 15, 2, 0);
  ui_msg(win, UiSel("setTitle:"), UiStr(title), 0, 0);
  UiCtl *c = UiCtlNew(UI_WINDOW, win);
  c->w = w;
  c->h = h;
  return c;
}

UiCtl *UiBoxNew(Bool vertical=TRUE)
{
  I64 sv = ui_msg(ui_msg(UiCls("NSStackView"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(sv, UiSel("setOrientation:"), vertical, 0, 0);
  ui_msgf(sv, UiSel("setSpacing:"), 16.0, 0.0, 0.0, 0.0, 0, 0, 0);
  return UiCtlNew(UI_BOX, sv);
}

// a grid emulated as a vertical stack of horizontal row stacks; add cells
// in increasing row order, the column index only orders within its row
UiCtl *UiGridNew()
{
  I64 sv = ui_msg(ui_msg(UiCls("NSStackView"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(sv, UiSel("setOrientation:"), 1, 0, 0);
  ui_msgf(sv, UiSel("setSpacing:"), 10.0, 0.0, 0.0, 0.0, 0, 0, 0);
  return UiCtlNew(UI_GRID, sv);
}

U0 UiGridAdd(UiCtl *g, UiCtl *c, I64 col, I64 row)
{
  UiCtl *r = g->kids;
  while (r && r->row != row)
    r = r->sib;
  if (!r) {
    I64 sv = ui_msg(ui_msg(UiCls("NSStackView"), UiSel("alloc"), 0, 0, 0),
      UiSel("init"), 0, 0, 0);
    ui_msg(sv, UiSel("setOrientation:"), 0, 0, 0);
    ui_msgf(sv, UiSel("setSpacing:"), 10.0, 0.0, 0.0, 0.0, 0, 0, 0);
    ui_msg(g->native, UiSel("addArrangedSubview:"), sv, 0, 0);
    r = UiCtlNew(UI_BOX, sv);
    r->row = row;
    UiKidAdd(g, r);
  }
  ui_msg(r->native, UiSel("addArrangedSubview:"), c->native, 0, 0);
}

UiCtl *UiLabelNew(U8 *text="")
{
  I64 l = ui_msg(UiCls("NSTextField"), UiSel("labelWithString:"),
    UiStr(text), 0, 0);
  return UiCtlNew(UI_LABEL, l);
}

U0 UiLabelSetText(UiCtl *l, U8 *text)
{
  ui_msg(l->native, UiSel("setStringValue:"), UiStr(text), 0, 0);
}

UiCtl *UiButtonNew(U8 *text)
{
  I64 b = ui_msg(UiCls("NSButton"), UiSel("buttonWithTitle:target:action:"),
    UiStr(text), ui_target, UiSel("clicked:"));
  return UiCtlNew(UI_BUTTON, b);
}

UiCtl *UiEntryNew(U8 *text="")
{
  I64 e = ui_msg(UiCls("NSTextField"), UiSel("textFieldWithString:"),
    UiStr(text), 0, 0);
  ui_msg(e, UiSel("setDelegate:"), ui_target, 0, 0);
  UiPin(e, "widthAnchor", 200);
  return UiCtlNew(UI_ENTRY, e);
}

U8 *UiEntryText(UiCtl *e)
{
  I64 s = ui_msg(e->native, UiSel("stringValue"), 0, 0, 0);
  U8 *u = ui_msg(s, UiSel("UTF8String"), 0, 0, 0);
  return StrNew(u);
}

U0 UiEntrySetText(UiCtl *e, U8 *text)
{
  ui_msg(e->native, UiSel("setStringValue:"), UiStr(text), 0, 0);
}

UiCtl *UiCheckboxNew(U8 *text, Bool checked=FALSE)
{
  I64 b = ui_msg(UiCls("NSButton"), UiSel("checkboxWithTitle:target:action:"),
    UiStr(text), ui_target, UiSel("clicked:"));
  ui_msg(b, UiSel("setState:"), checked, 0, 0);
  return UiCtlNew(UI_CHECKBOX, b);
}

Bool UiCheckboxChecked(UiCtl *c)
{
  return ui_msg(c->native, UiSel("state"), 0, 0, 0) & 1;
}

UiCtl *UiSliderNew(I64 min=0, I64 max=100)
{
  F64 fmin = min, fmax = max;
  I64 s = ui_msgf(UiCls("NSSlider"),
    UiSel("sliderWithValue:minValue:maxValue:target:action:"),
    fmin, fmin, fmax, 0.0, ui_target, UiSel("clicked:"), 0);
  UiPin(s, "widthAnchor", 240);
  return UiCtlNew(UI_SLIDER, s);
}

I64 UiSliderValue(UiCtl *s)
{
  return ui_msg(s->native, UiSel("integerValue"), 0, 0, 0);
}

UiCtl *UiProgressNew()
{
  I64 p = ui_msg(ui_msg(UiCls("NSProgressIndicator"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(p, UiSel("setStyle:"), 0, 0, 0);
  ui_msg(p, UiSel("setIndeterminate:"), 0, 0, 0);
  ui_msgf(p, UiSel("setMinValue:"), 0.0, 0.0, 0.0, 0.0, 0, 0, 0);
  ui_msgf(p, UiSel("setMaxValue:"), 100.0, 0.0, 0.0, 0.0, 0, 0, 0);
  UiPin(p, "widthAnchor", 240);
  return UiCtlNew(UI_PROGRESS, p);
}

U0 UiProgressSet(UiCtl *p, I64 percent)
{
  F64 f = percent;
  ui_msgf(p->native, UiSel("setDoubleValue:"), f, 0.0, 0.0, 0.0, 0, 0, 0);
}

UiCtl *UiSeparatorNew()
{
  I64 b = ui_msg(ui_msg(UiCls("NSBox"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(b, UiSel("setBoxType:"), 2, 0, 0);
  UiPin(b, "widthAnchor", 400);
  return UiCtlNew(UI_SEP, b);
}

UiCtl *UiCanvasNew(I64 w, I64 h, U0 *drawfn, U0 *data=NULL)
{
  F64 fw = w, fh = h;
  I64 v = ui_msgf(ui_msg(UiCls("UiCanvasV"), UiSel("alloc"), 0, 0, 0),
    UiSel("initWithFrame:"), 0.0, 0.0, fw, fh, 0, 0, 0);
  UiPin(v, "widthAnchor", w);
  UiPin(v, "heightAnchor", h);
  UiCtl *c = UiCtlNew(UI_CANVAS, v);
  c->w = w;
  c->h = h;
  UiOnClick(c, drawfn, data);
  return c;
}

U0 UiCanvasRedraw(UiCtl *c)
{
  ui_msg(c->native, UiSel("setNeedsDisplay:"), 1, 0, 0);
}

U0 UiSetColor(F64 r, F64 g, F64 b)
{
  CGContextSetRGBFillColor(ui_cg, r, g, b, 1.0);
  CGContextSetRGBStrokeColor(ui_cg, r, g, b, 1.0);
}

U0 UiFillRect(F64 x, F64 y, F64 w, F64 h)
{
  CGContextFillRect(ui_cg, x, y, w, h);
}

U0 UiLine(F64 x1, F64 y1, F64 x2, F64 y2)
{
  CGContextSetLineWidth(ui_cg, 1.0);
  CGContextMoveToPoint(ui_cg, x1, y1);
  CGContextAddLineToPoint(ui_cg, x2, y2);
  CGContextStrokePath(ui_cg);
}

UiCtl *UiMenuNew(U8 *title)
{
  if (!ui_mainmenu) {
    ui_mainmenu = ui_msg(ui_msg(UiCls("NSMenu"), UiSel("alloc"), 0, 0, 0),
      UiSel("init"), 0, 0, 0);
    ui_msg(ui_app, UiSel("setMainMenu:"), ui_mainmenu, 0, 0);
    // slot 0 is the application menu; park an empty one there so user
    // menus land after the app name, like every mac app
    I64 appitem = ui_msg(ui_msg(UiCls("NSMenuItem"), UiSel("alloc"), 0, 0, 0),
      UiSel("init"), 0, 0, 0);
    ui_msg(ui_mainmenu, UiSel("addItem:"), appitem, 0, 0);
    ui_msg(appitem, UiSel("setSubmenu:"),
      ui_msg(ui_msg(UiCls("NSMenu"), UiSel("alloc"), 0, 0, 0),
        UiSel("init"), 0, 0, 0), 0, 0);
  }
  I64 item = ui_msg(ui_msg(UiCls("NSMenuItem"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  I64 sub = ui_msg(ui_msg(UiCls("NSMenu"), UiSel("alloc"), 0, 0, 0),
    UiSel("initWithTitle:"), UiStr(title), 0, 0);
  ui_msg(ui_mainmenu, UiSel("addItem:"), item, 0, 0);
  ui_msg(item, UiSel("setSubmenu:"), sub, 0, 0);
  return UiCtlNew(UI_MENU, sub);
}

UiCtl *UiMenuItem(UiCtl *m, U8 *label, U0 *fn, U0 *data=NULL)
{
  I64 it = ui_msg(ui_msg(UiCls("NSMenuItem"), UiSel("alloc"), 0, 0, 0),
    UiSel("initWithTitle:action:keyEquivalent:"),
    UiStr(label), UiSel("clicked:"), UiStr(""));
  ui_msg(it, UiSel("setTarget:"), ui_target, 0, 0);
  ui_msg(m->native, UiSel("addItem:"), it, 0, 0);
  UiCtl *c = UiCtlNew(UI_MENUITEM, it);
  UiOnClick(c, fn, data);
  return c;
}

I64 UiCocoaAlert(U8 *title, U8 *body, I64 style)
{
  I64 a = ui_msg(ui_msg(UiCls("NSAlert"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(a, UiSel("setMessageText:"), UiStr(title), 0, 0);
  ui_msg(a, UiSel("setInformativeText:"), UiStr(body), 0, 0);
  ui_msg(a, UiSel("setAlertStyle:"), style, 0, 0);
  return a;
}

U0 UiMsgBox(U8 *title, U8 *body)
{
  ui_msg(UiCocoaAlert(title, body, 1), UiSel("runModal"), 0, 0, 0);
}

U0 UiWarnBox(U8 *title, U8 *body)
{
  ui_msg(UiCocoaAlert(title, body, 2), UiSel("runModal"), 0, 0, 0);
}

U8 *UiOpenFile()
{
  I64 p = ui_msg(UiCls("NSOpenPanel"), UiSel("openPanel"), 0, 0, 0);
  I64 rc = ui_msg(p, UiSel("runModal"), 0, 0, 0);
  if (rc(I32) != 1)
    return NULL;
  I64 path = ui_msg(ui_msg(p, UiSel("URL"), 0, 0, 0), UiSel("path"), 0, 0, 0);
  U8 *u = ui_msg(path, UiSel("UTF8String"), 0, 0, 0);
  return StrNew(u);
}

U8 *UiPrompt(U8 *title, U8 *body, U8 *init="")
{
  I64 a = UiCocoaAlert(title, body, 1);
  ui_msg(a, UiSel("addButtonWithTitle:"), UiStr("OK"), 0, 0);
  ui_msg(a, UiSel("addButtonWithTitle:"), UiStr("Cancel"), 0, 0);
  I64 tf = ui_msg(UiCls("NSTextField"), UiSel("textFieldWithString:"),
    UiStr(init), 0, 0);
  UiFrame(tf, 0.0, 0.0, 220.0, 24.0);
  ui_msg(a, UiSel("setAccessoryView:"), tf, 0, 0);
  I64 rc = ui_msg(a, UiSel("runModal"), 0, 0, 0);
  if (rc(I32) != 1000)  // NSAlertFirstButtonReturn
    return NULL;
  U8 *u = ui_msg(ui_msg(tf, UiSel("stringValue"), 0, 0, 0),
    UiSel("UTF8String"), 0, 0, 0);
  return StrNew(u);
}

UiCtl *UiComboNew()
{
  I64 p = ui_msg(ui_msg(UiCls("NSPopUpButton"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(p, UiSel("setTarget:"), ui_target, 0, 0);
  ui_msg(p, UiSel("setAction:"), UiSel("clicked:"), 0, 0);
  UiPin(p, "widthAnchor", 200);
  return UiCtlNew(UI_COMBO, p);
}

U0 UiComboAdd(UiCtl *c, U8 *text)
{
  ui_msg(c->native, UiSel("addItemWithTitle:"), UiStr(text), 0, 0);
}

I64 UiComboSelected(UiCtl *c)
{
  return ui_msg(c->native, UiSel("indexOfSelectedItem"), 0, 0, 0)(I32);
}

UiCtl *UiRadioNew()
{
  I64 sv = ui_msg(ui_msg(UiCls("NSStackView"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(sv, UiSel("setOrientation:"), 1, 0, 0);
  ui_msg(sv, UiSel("setAlignment:"), 1, 0, 0);  // NSLayoutAttributeLeft
  ui_msgf(sv, UiSel("setSpacing:"), 4.0, 0.0, 0.0, 0.0, 0, 0, 0);
  return UiCtlNew(UI_RADIO, sv);
}

U0 UiRadioAdd(UiCtl *r, U8 *text)
{
  I64 b = ui_msg(UiCls("NSButton"), UiSel("radioButtonWithTitle:target:action:"),
    UiStr(text), ui_target, UiSel("clicked:"));
  ui_msg(r->native, UiSel("addArrangedSubview:"), b, 0, 0);
  UiCtl *k = UiCtlNew(UI_BUTTON, b);
  UiKidAdd(r, k);
}

I64 UiRadioSelected(UiCtl *r)
{
  I64 i = 0;
  UiCtl *k = r->kids;
  while (k) {
    if (ui_msg(k->native, UiSel("state"), 0, 0, 0) & 1)
      return i;
    i++;
    k = k->sib;
  }
  return -1;
}

UiCtl *UiSpinNew(I64 min=0, I64 max=100)
{
  I64 tf = ui_msg(UiCls("NSTextField"), UiSel("textFieldWithString:"),
    UiStr("0"), 0, 0);
  I64 st = ui_msg(ui_msg(UiCls("NSStepper"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  F64 fmin = min, fmax = max;
  ui_msgf(st, UiSel("setMinValue:"), fmin, 0.0, 0.0, 0.0, 0, 0, 0);
  ui_msgf(st, UiSel("setMaxValue:"), fmax, 0.0, 0.0, 0.0, 0, 0, 0);
  ui_msg(st, UiSel("setTarget:"), ui_target, 0, 0);
  ui_msg(st, UiSel("setAction:"), UiSel("clicked:"), 0, 0);
  I64 sv = ui_msg(ui_msg(UiCls("NSStackView"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(sv, UiSel("addArrangedSubview:"), tf, 0, 0);
  ui_msg(sv, UiSel("addArrangedSubview:"), st, 0, 0);
  UiPin(tf, "widthAnchor", 60);
  UiCtl *c = UiCtlNew(UI_SPIN, sv);
  c->col = st;   // stepper holds the value
  c->row = tf;   // field mirrors it
  return c;
}

I64 UiSpinValue(UiCtl *s)
{
  I64 v = ui_msg(s->col, UiSel("integerValue"), 0, 0, 0);
  U8 *t = MStrPrint("%d", v);
  ui_msg(s->row, UiSel("setStringValue:"), UiStr(t), 0, 0);
  Free(t);
  return v;
}

UiCtl *UiMultilineNew(U8 *text="")
{
  I64 tv = ui_msg(ui_msg(UiCls("NSTextView"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(ui_msg(tv, UiSel("textStorage"), 0, 0, 0),
    UiSel("setAttributedString:"),
    ui_msg(ui_msg(UiCls("NSAttributedString"), UiSel("alloc"), 0, 0, 0),
      UiSel("initWithString:"), UiStr(text), 0), 0, 0);
  UiPin(tv, "heightAnchor", 80);
  UiPin(tv, "widthAnchor", 240);
  return UiCtlNew(UI_MULTILINE, tv);
}

UiCtl *UiPasswordNew(U8 *text="")
{
  I64 e = ui_msg(ui_msg(UiCls("NSSecureTextField"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(e, UiSel("setStringValue:"), UiStr(text), 0, 0);
  ui_msg(e, UiSel("setDelegate:"), ui_target, 0, 0);
  UiPin(e, "widthAnchor", 200);
  return UiCtlNew(UI_ENTRY, e);
}

UiCtl *UiGroupNew(U8 *title)
{
  I64 b = ui_msg(ui_msg(UiCls("NSBox"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(b, UiSel("setTitle:"), UiStr(title), 0, 0);
  return UiCtlNew(UI_GROUP, b);
}

U0 UiGroupSetChild(UiCtl *g, UiCtl *child)
{
  ui_msg(g->native, UiSel("setContentView:"), child->native, 0, 0);
}

UiCtl *UiTabNew()
{
  I64 tv = ui_msg(ui_msg(UiCls("NSTabView"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  return UiCtlNew(UI_TAB, tv);
}

U0 UiTabAdd(UiCtl *t, U8 *label, UiCtl *child)
{
  I64 it = ui_msg(ui_msg(UiCls("NSTabViewItem"), UiSel("alloc"), 0, 0, 0),
    UiSel("initWithIdentifier:"), 0, 0, 0);
  ui_msg(it, UiSel("setLabel:"), UiStr(label), 0, 0);
  ui_msg(it, UiSel("setView:"), child->native, 0, 0);
  ui_msg(t->native, UiSel("addTabViewItem:"), it, 0, 0);
}

U0 UiEnable(UiCtl *c, Bool on)
{
  ui_msg(c->native, UiSel("setEnabled:"), on, 0, 0);
}

U0 UiSetVisible(UiCtl *c, Bool on)
{
  ui_msg(c->native, UiSel("setHidden:"), !on, 0, 0);
}

U0 UiCocoaSchedule(F64 secs, U0 *fn, U0 *data, I64 repeats)
{
  UiCtl *t = UiCtlNew(UI_TIMER, 0);
  UiOnClick(t, fn, data);
  I64 box = ui_msg(UiCls("NSValue"), UiSel("valueWithPointer:"), t, 0, 0);
  ui_msgt(UiCls("NSTimer"),
    UiSel("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),
    secs, ui_timer_tgt, UiSel("tick:"), box, repeats);
}

U0 UiTimer(I64 ms, U0 *fn, U0 *data=NULL)
{
  F64 secs = ms;
  UiCocoaSchedule(secs / 1000.0, fn, data, 1);
}

U0 UiQueueMain(U0 *fn, U0 *data=NULL)
{
  UiCocoaSchedule(0.0, fn, data, 0);  // repeats:0 fires once, self-invalidates
}

UiCtl *UiToolbarNew()
{
  I64 sv = ui_msg(ui_msg(UiCls("NSStackView"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(sv, UiSel("setOrientation:"), 0, 0, 0);
  ui_msgf(sv, UiSel("setSpacing:"), 8.0, 0.0, 0.0, 0.0, 0, 0, 0);
  return UiCtlNew(UI_TOOLBAR, sv);
}

U0 UiToolAdd(UiCtl *tb, U8 *label, U0 *fn, U0 *data=NULL)
{
  I64 b = ui_msg(UiCls("NSButton"), UiSel("buttonWithTitle:target:action:"),
    UiStr(label), ui_target, UiSel("clicked:"));
  UiCtl *c = UiCtlNew(UI_BUTTON, b);
  UiOnClick(c, fn, data);
  ui_msg(tb->native, UiSel("addArrangedSubview:"), b, 0, 0);
}

UiCtl *UiStatusbarNew(U8 *text="")
{
  I64 l = ui_msg(UiCls("NSTextField"), UiSel("labelWithString:"),
    UiStr(text), 0, 0);
  return UiCtlNew(UI_STATUS, l);
}

U0 UiStatusSet(UiCtl *sb, U8 *text)
{
  ui_msg(sb->native, UiSel("setStringValue:"), UiStr(text), 0, 0);
}

UiCtl *UiSplitNew(Bool vertical=FALSE)
{
  I64 sv = ui_msg(ui_msg(UiCls("NSSplitView"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(sv, UiSel("setVertical:"), !vertical, 0, 0);  // NSSplitView vertical = side-by-side
  ui_msg(sv, UiSel("setDividerStyle:"), 2, 0, 0);
  UiPin(sv, "heightAnchor", 300);
  return UiCtlNew(UI_SPLIT, sv);
}

U0 UiSplitAdd(UiCtl *sp, UiCtl *child)
{
  ui_msg(sp->native, UiSel("addSubview:"), child->native, 0, 0);
}

UiCtl *UiScrollNew(UiCtl *child)
{
  I64 s = ui_msg(ui_msg(UiCls("NSScrollView"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(s, UiSel("setHasVerticalScroller:"), 1, 0, 0);
  ui_msg(s, UiSel("setDocumentView:"), child->native, 0, 0);
  return UiCtlNew(UI_SCROLL, s);
}

UiCtl *UiTableNew(U0 *cellfn, U0 *data=NULL)
{
  I64 tv = ui_msg(ui_msg(UiCls("NSTableView"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(tv, UiSel("setDataSource:"), ui_tbl_src, 0, 0);
  ui_msg(tv, UiSel("setDelegate:"), ui_tbl_src, 0, 0);
  ui_msg(tv, UiSel("setUsesAlternatingRowBackgroundColors:"), 1, 0, 0);
  I64 scroll = ui_msg(ui_msg(UiCls("NSScrollView"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(scroll, UiSel("setHasVerticalScroller:"), 1, 0, 0);
  ui_msg(scroll, UiSel("setDocumentView:"), tv, 0, 0);
  UiPin(scroll, "heightAnchor", 200);
  UiPin(scroll, "widthAnchor", 360);
  UiCtl *c = UiCtlNew(UI_TABLE, scroll);
  c->col = tv;
  c->cellfn = cellfn;
  c->celldata = data;
  return c;
}

U0 UiTableColumn(UiCtl *t, U8 *title)
{
  U8 *ident = MStrPrint("%d", t->w);
  I64 col = ui_msg(ui_msg(UiCls("NSTableColumn"), UiSel("alloc"), 0, 0, 0),
    UiSel("initWithIdentifier:"), UiStr(ident), 0, 0);
  ui_msg(ui_msg(col, UiSel("headerCell"), 0, 0, 0),
    UiSel("setStringValue:"), UiStr(title), 0, 0);
  ui_msgf(col, UiSel("setWidth:"), 120.0, 0.0, 0.0, 0.0, 0, 0, 0);
  ui_msg(t->col, UiSel("addTableColumn:"), col, 0, 0);
  t->w++;
  Free(ident);
}

U0 UiTableSetRows(UiCtl *t, I64 nrows)
{
  t->row = nrows;
  ui_msg(t->col, UiSel("reloadData"), 0, 0, 0);
}

I64 UiTableSelected(UiCtl *t)
{
  return ui_msg(t->col, UiSel("selectedRow"), 0, 0, 0)(I32);
}

UiCtl *UiTreeNew()
{
  I64 ov = ui_msg(ui_msg(UiCls("NSOutlineView"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  I64 col = ui_msg(ui_msg(UiCls("NSTableColumn"), UiSel("alloc"), 0, 0, 0),
    UiSel("initWithIdentifier:"), UiStr("t"), 0, 0);
  ui_msgf(col, UiSel("setWidth:"), 320.0, 0.0, 0.0, 0.0, 0, 0, 0);
  ui_msg(ov, UiSel("addTableColumn:"), col, 0, 0);
  ui_msg(ov, UiSel("setOutlineTableColumn:"), col, 0, 0);
  ui_msg(ov, UiSel("setDataSource:"), ui_tree_src, 0, 0);
  ui_msg(ov, UiSel("setDelegate:"), ui_tree_src, 0, 0);
  ui_msg(ov, UiSel("setHeaderView:"), 0, 0, 0);
  I64 scroll = ui_msg(ui_msg(UiCls("NSScrollView"), UiSel("alloc"), 0, 0, 0),
    UiSel("init"), 0, 0, 0);
  ui_msg(scroll, UiSel("setHasVerticalScroller:"), 1, 0, 0);
  ui_msg(scroll, UiSel("setDocumentView:"), ov, 0, 0);
  UiPin(scroll, "heightAnchor", 220);
  UiPin(scroll, "widthAnchor", 340);
  UiCtl *c = UiCtlNew(UI_TREE, scroll);
  c->col = ov;
  return c;
}

UiCtl *UiTreeAdd(UiCtl *t, UiCtl *parent, U8 *label)
{
  UiCtl *n = UiCtlNew(UI_TREENODE, 0);
  n->celldata = StrNew(label);
  n->native = ui_msg(UiCls("NSValue"), UiSel("valueWithPointer:"), n, 0, 0);
  if (parent)
    UiKidAdd(parent, n);
  else
    UiKidAdd(t, n);
  ui_msg(t->col, UiSel("reloadData"), 0, 0, 0);
  return n;
}

UiCtl *UiTreeSelected(UiCtl *t)
{
  I64 row = ui_msg(t->col, UiSel("selectedRow"), 0, 0, 0)(I32);
  if (row < 0)
    return NULL;
  I64 item = ui_msg(t->col, UiSel("itemAtRow:"), row, 0, 0);
  if (!item)
    return NULL;
  return UiUnbox(item);
}

U0 UiBoxAdd(UiCtl *box, UiCtl *c)
{
  ui_msg(box->native, UiSel("addArrangedSubview:"), c->native, 0, 0);
}

U0 UiWindowSetChild(UiCtl *w, UiCtl *c)
{
  ui_msg(w->native, UiSel("setContentView:"), c->native, 0, 0);
  F64 fw = w->w, fh = w->h;
  ui_msgf(w->native, UiSel("setContentSize:"), fw, fh, 0.0, 0.0, 0, 0, 0);
  ui_msg(w->native, UiSel("center"), 0, 0, 0);
}

U0 UiShow(UiCtl *w)
{
  ui_msg(w->native, UiSel("makeKeyAndOrderFront:"), 0, 0, 0);
  // the arranged content view has a fitting size; re-assert ours
  F64 fw = w->w, fh = w->h;
  ui_msgf(w->native, UiSel("setContentSize:"), fw, fh, 0.0, 0.0, 0, 0, 0);
  ui_msg(w->native, UiSel("center"), 0, 0, 0);
  ui_msg(ui_app, UiSel("activateIgnoringOtherApps:"), 1, 0, 0);
}

U0 UiMain()
{
  ui_msg(ui_app, UiSel("run"), 0, 0, 0);
}
