// table.hc — a data-source table: the widget pulls each cell from a
// HolyC callback. Same three backends.
//
//   ./aholyc run examples/ui/table.hc
//   ./aholyc run -DUI_GTK4 examples/ui/table.hc
//   CC=demos/windows/ccwin.sh ./aholyc -b c -DUI_WIN32 examples/ui/table.hc -o table.exe

#include "lib/ui.hc"

U8 *names[5];
I64 ages[5];
UiCtl *gTable, *gStatus;

U8 *Cell(UiCtl *t, I64 row, I64 col, U0 *data)
{
  if (col == 0)
    return names[row];
  return MStrPrint("%d", ages[row]);   // leaked per-pull; fine for a demo
}

U0 OnSelect(UiCtl *t, U0 *data)
{
  I64 r = UiTableSelected(t);
  if (r < 0)
    return;
  U8 *s = MStrPrint("Selected: %s (%d)", names[r], ages[r]);
  UiLabelSetText(gStatus, s);
  Free(s);
}

names[0] = "Terry";   ages[0] = 48;
names[1] = "Ada";     ages[1] = 36;
names[2] = "Alan";    ages[2] = 41;
names[3] = "Grace";   ages[3] = 52;
names[4] = "Dennis";  ages[4] = 70;

UiInit;
UiCtl *win = UiWindowNew("HolyC Table", 420, 340);
UiCtl *box = UiBoxNew;
gTable = UiTableNew(&Cell);
UiTableColumn(gTable, "Name");
UiTableColumn(gTable, "Age");
UiTableSetRows(gTable, 5);
UiOnClick(gTable, &OnSelect);
UiBoxAdd(box, gTable);
gStatus = UiLabelNew("Pick a row");
UiBoxAdd(box, gStatus);
UiWindowSetChild(win, box);
UiShow(win);
"table: window up, close it to quit\n";
UiMain;
