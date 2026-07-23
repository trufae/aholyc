// demo.hc — one program, three toolkits: the ui.hc library hides them.
//
//   ./aholyc run examples/ui/demo.hc                          (native backend)
//   ./aholyc run -DUI_GTK4 examples/ui/demo.hc                (force gtk4)
//   CC=demos/windows/ccwin.sh ./aholyc -b c -DUI_WIN32 \
//       examples/ui/demo.hc -o demo.exe                       (cross-build)
//
// Exercises the full ui.hc surface: menus, box + grid layout, label,
// button, entry, checkbox, slider, progress bar, separator, and a canvas
// redrawn live from the slider and checkbox.

#include "../../lib/ui/ui.hc"

UiCtl *gStatus, *gGreet, *gCheck, *gSlider, *gProgress, *gCanvas;
UiCtl *gCombo, *gRadio, *gSpin;
I64 gClicks, gTick;

U0 OnQuit(UiCtl *c, U0 *data)
{
  UiQuit;
}

U0 OnAbout(UiCtl *c, U0 *data)
{
  UiMsgBox("HolyC UI", "An offering from the temple.");
}

U0 OnOpen(UiCtl *c, U0 *data)
{
  U8 *p = UiOpenFile;
  if (p) {
    UiLabelSetText(gStatus, p);
    Free(p);
  }
}

U0 OnAsk(UiCtl *c, U0 *data)
{
  U8 *t = UiPrompt("Name", "Who art thou?", "Terry");
  if (!t)
    return;
  U8 *s = MStrPrint("Hello, %s", t);
  UiLabelSetText(gGreet, s);
  Free(t);
  Free(s);
}

U0 OnNewWin(UiCtl *c, U0 *data)
{
  UiCtl *w2 = UiWindowNew("Second temple", 300, 160);
  UiCtl *b2 = UiBoxNew;
  UiBoxAdd(b2, UiLabelNew("Another window"));
  UiWindowSetChild(w2, b2);
  UiShow(w2);
}

U0 OnClick(UiCtl *c, U0 *data)
{
  gClicks++;
  U8 *s = MStrPrint("Clicked %d times", gClicks);
  UiLabelSetText(gStatus, s);
  Free(s);
}

U0 OnEntry(UiCtl *c, U0 *data)
{
  U8 *t = UiEntryText(c);
  U8 *s = MStrPrint("Hello, %s", t);
  UiLabelSetText(gGreet, s);
  Free(t);
  Free(s);
}

U0 OnSlide(UiCtl *c, U0 *data)
{
  UiProgressSet(gProgress, UiSliderValue(c));
  UiCanvasRedraw(gCanvas);
}

U0 OnToggle(UiCtl *c, U0 *data)
{
  UiCanvasRedraw(gCanvas);
}

U0 OnPick(UiCtl *c, U0 *data)
{
  U8 *s = MStrPrint("combo=%d  radio=%d  spin=%d",
    UiComboSelected(gCombo), UiRadioSelected(gRadio), UiSpinValue(gSpin));
  UiLabelSetText(gStatus, s);
  Free(s);
}

U0 OnTick(UiCtl *c, U0 *data)
{
  gTick = (gTick + 5) % 105;
  UiProgressSet(gProgress, gTick);
  UiCanvasRedraw(gCanvas);
}

U0 OnDraw(UiCtl *c, U0 *data)
{
  F64 v = UiSliderValue(gSlider);
  UiSetColor(0.10, 0.10, 0.14);
  UiFillRect(0.0, 0.0, 420.0, 100.0);
  if (UiCheckboxChecked(gCheck))
    UiSetColor(1.0, 0.8, 0.1);
  else
    UiSetColor(0.3, 0.6, 1.0);
  UiFillRect(10.0, 30.0, 10.0 + v * 4.0, 40.0);
  UiSetColor(0.9, 0.9, 0.9);
  UiLine(10.0, 15.0, 410.0, 15.0);
}

UiInit;
UiCtl *win = UiWindowNew("HolyC UI", 520, 720);
UiCtl *m = UiMenuNew("File");
UiMenuItem(m, "About", &OnAbout);
UiMenuItem(m, "Open...", &OnOpen);
UiMenuItem(m, "Ask name...", &OnAsk);
UiMenuItem(m, "New window", &OnNewWin);
UiMenuItem(m, "Quit", &OnQuit);

UiCtl *box = UiBoxNew;
gStatus = UiLabelNew("An offering from the temple");
UiBoxAdd(box, gStatus);
UiCtl *btn = UiButtonNew("Click me");
UiOnClick(btn, &OnClick);
UiBoxAdd(box, btn);
UiBoxAdd(box, UiSeparatorNew);

UiCtl *grid = UiGridNew;
UiGridAdd(grid, UiLabelNew("Name:"), 0, 0);
UiCtl *entry = UiEntryNew("Terry");
UiOnChange(entry, &OnEntry);
UiGridAdd(grid, entry, 1, 0);
UiGridAdd(grid, UiLabelNew("Greeting:"), 0, 1);
gGreet = UiLabelNew("Hello, Terry");
UiGridAdd(grid, gGreet, 1, 1);
UiBoxAdd(box, grid);

UiCtl *row = UiBoxNew(FALSE);
gCombo = UiComboNew;
UiComboAdd(gCombo, "Amber");
UiComboAdd(gCombo, "Gold");
UiComboAdd(gCombo, "Silver");
UiOnChange(gCombo, &OnPick);
UiBoxAdd(row, gCombo);
gSpin = UiSpinNew(0, 10);
UiOnChange(gSpin, &OnPick);
UiBoxAdd(row, gSpin);
UiBoxAdd(box, row);

gRadio = UiRadioNew;
UiRadioAdd(gRadio, "First");
UiRadioAdd(gRadio, "Second");
UiOnChange(gRadio, &OnPick);
UiBoxAdd(box, gRadio);

gCheck = UiCheckboxNew("Gold bar");
UiOnChange(gCheck, &OnToggle);
UiBoxAdd(box, gCheck);
gSlider = UiSliderNew;
UiOnChange(gSlider, &OnSlide);
UiBoxAdd(box, gSlider);
gProgress = UiProgressNew;
UiBoxAdd(box, gProgress);
gCanvas = UiCanvasNew(420, 100, &OnDraw);
UiBoxAdd(box, gCanvas);

UiWindowSetChild(win, box);
UiShow(win);
UiTimer(500, &OnTick);
"uidemo: window up, close it to quit\n";
UiMain;
