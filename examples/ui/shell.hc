// shell.hc — an app shell: toolbar on top, sidebar split in the middle,
// status bar at the bottom. Same three backends as demo.hc.
//
//   ./aholyc run examples/ui/shell.hc
//   ./aholyc run -DUI_GTK4 examples/ui/shell.hc
//   CC=demos/windows/ccwin.sh ./aholyc -b c -DUI_WIN32 examples/ui/shell.hc -o shell.exe

#include "lib/ui.hc"

UiCtl *gStatus, *gBody;

U0 OnNew(UiCtl *c, U0 *data)   { UiStatusSet(gStatus, "New");   UiLabelSetText(gBody, "New document"); }
U0 OnSave(UiCtl *c, U0 *data)  { UiStatusSet(gStatus, "Saved"); UiLabelSetText(gBody, "Document saved"); }
U0 OnOpen(UiCtl *c, U0 *data)
{
  U8 *p = UiOpenFile;
  if (!p)
    return;
  UiStatusSet(gStatus, p);
  UiLabelSetText(gBody, p);
  Free(p);
}

UiInit;
UiCtl *win = UiWindowNew("HolyC Shell", 640, 420);
UiCtl *root = UiBoxNew;

UiCtl *tb = UiToolbarNew;
UiToolAdd(tb, "New", &OnNew);
UiToolAdd(tb, "Open", &OnOpen);
UiToolAdd(tb, "Save", &OnSave);
UiBoxAdd(root, tb);

UiCtl *split = UiSplitNew;
UiCtl *side = UiBoxNew;
UiBoxAdd(side, UiLabelNew("Sidebar"));
UiBoxAdd(side, UiButtonNew("Item 1"));
UiBoxAdd(side, UiButtonNew("Item 2"));
UiSplitAdd(split, side);
gBody = UiLabelNew("Body — pick a toolbar action");
UiCtl *main = UiBoxNew;
UiBoxAdd(main, gBody);
UiSplitAdd(split, UiScrollNew(main));
UiBoxAdd(root, split);

gStatus = UiStatusbarNew("Ready");
UiBoxAdd(root, gStatus);

UiWindowSetChild(win, root);
UiShow(win);
"shell: window up, close it to quit\n";
UiMain;
