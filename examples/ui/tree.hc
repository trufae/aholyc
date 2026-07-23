// tree.hc — a tree/outline built imperatively, with selection reported
// back to a HolyC callback. Same three backends.
//
//   ./aholyc run examples/ui/tree.hc
//   ./aholyc run -DUI_GTK4 examples/ui/tree.hc
//   CC=demos/windows/ccwin.sh ./aholyc -b c -DUI_WIN32 examples/ui/tree.hc -o tree.exe

#include "lib/ui.hc"

UiCtl *gTree, *gStatus;

U0 OnSelect(UiCtl *t, U0 *data)
{
  UiCtl *n = UiTreeSelected(t);
  if (n)
    UiStatusSet(gStatus, n->celldata);
}

UiInit;
UiCtl *win = UiWindowNew("HolyC Tree", 400, 380);
UiCtl *box = UiBoxNew;

gTree = UiTreeNew;
UiCtl *src = UiTreeAdd(gTree, NULL, "src");
UiTreeAdd(gTree, src, "lexer.c");
UiTreeAdd(gTree, src, "parser.c");
UiCtl *back = UiTreeAdd(gTree, src, "backends");
UiTreeAdd(gTree, back, "llvm.c");
UiTreeAdd(gTree, back, "c.c");
UiCtl *doc = UiTreeAdd(gTree, NULL, "doc");
UiTreeAdd(gTree, doc, "language.md");
UiTreeAdd(gTree, doc, "usage.md");
UiOnClick(gTree, &OnSelect);
UiBoxAdd(box, gTree);

gStatus = UiStatusbarNew("Pick a node");
UiBoxAdd(box, gStatus);
UiWindowSetChild(win, box);
UiShow(win);
"tree: window up, close it to quit\n";
UiMain;
