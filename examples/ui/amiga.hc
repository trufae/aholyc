// A compact native UI demo for a 640x256 Workbench screen.
// ./aholyc -t amiga examples/ui/amiga.hc -o holy-ui
#include "../../lib/ui/ui.hc"

UiCtl *status, *entry, *slider, *check, *progress, *canvas;

U0 Quit(UiCtl *c, U0 *data) { UiQuit; }

U0 Open(UiCtl *c, U0 *data)
{
  U8 *path = UiOpenFile;
  if (path) { UiStatusSet(status, path); Free(path); }
}

U0 Ask(UiCtl *c, U0 *data)
{
  U8 *name = UiPrompt("HolyC", "Your name:", "Amiga");
  if (name) { UiEntrySetText(entry, name); Free(name); }
}

U0 About(UiCtl *c, U0 *data)
{
  UiMsgBox("HolyC UI", "Native Intuition and GadTools, from HolyC.");
}

U0 DrawBar(UiCtl *c, U0 *data)
{
  UiSetColor(0.0, 0.0, 0.0);
  UiFillRect(0.0, 0.0, 480.0, 48.0);
  if (UiCheckboxChecked(check)) UiSetColor(1.0, 1.0, 1.0);
  else UiSetColor(0.3, 0.5, 1.0);
  UiFillRect(4.0, 8.0, 4.0 + UiSliderValue(slider) * 4.0, 24.0);
}

U0 Changed(UiCtl *c, U0 *data)
{
  UiProgressSet(progress, UiSliderValue(slider));
  UiCanvasRedraw(canvas);
}

U0 Greeting(UiCtl *c, U0 *data)
{
  U8 *name = UiEntryText(entry), *text = MStrPrint("Hello, %s", name);
  UiStatusSet(status, text); Free(text); Free(name);
}

UiInit;
UiCtl *window = UiWindowNew("HolyC on Amiga", 512, 244);
UiCtl *menu = UiMenuNew("Project");
UiMenuItem(menu, "About", &About);
UiMenuItem(menu, "Open...", &Open);
UiMenuItem(menu, "Ask name...", &Ask);
UiMenuItem(menu, "Quit", &Quit);

UiCtl *box = UiBoxNew, *row = UiToolbarNew, *grid = UiGridNew;
UiBoxAdd(box, UiLabelNew("Native Amiga widgets and drawing"));
UiToolAdd(row, "About", &About);
UiToolAdd(row, "Open", &Open);
UiToolAdd(row, "Ask", &Ask);
UiToolAdd(row, "Quit", &Quit);
UiBoxAdd(box, row);
entry = UiEntryNew("Amiga");
UiOnSubmit(entry, &Greeting);
UiGridAdd(grid, UiLabelNew("Name:"), 0, 0);
UiGridAdd(grid, entry, 1, 0);
UiBoxAdd(box, grid);
check = UiCheckboxNew("White bar");
UiOnChange(check, &Changed); UiBoxAdd(box, check);
slider = UiSliderNew;
UiOnChange(slider, &Changed); UiBoxAdd(box, slider);
progress = UiProgressNew;
UiBoxAdd(box, progress);
canvas = UiCanvasNew(480, 48, &DrawBar);
UiBoxAdd(box, canvas);
status = UiStatusbarNew("Enter a name and press Return");
UiBoxAdd(box, status);
UiWindowSetChild(window, box);
UiShow(window);
UiMain;
