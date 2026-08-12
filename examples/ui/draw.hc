// draw.hc - lib/ui canvas version of examples/term.hc.
//
//   ./aholyc run examples/ui/draw.hc
//   ./aholyc run -DUI_GTK4 examples/ui/draw.hc
//   ./aholyc run -DUI_HTK examples/ui/draw.hc
//   CC=demos/windows/ccwin.sh ./aholyc -b c -DUI_WIN32 \
//       examples/ui/draw.hc -o draw.exe

#include "../../lib/ui/ui.hc"

#define DRAW_W 720
#define DRAW_H 420
#define DRAW_MAX_POINTS 2048

UiCtl *gEvent, *gFooter, *gCanvas, *gBright, *gCount;
I64 gPtsX[DRAW_MAX_POINTS], gPtsY[DRAW_MAX_POINTS], gPtsBright[DRAW_MAX_POINTS];
I64 gPaintN, gMouseX, gMouseY;
Bool gMouseSeen, gMouseDown;

I64 DrawClamp(I64 v, I64 low, I64 high)
{
  if (v < low)
    return low;
  if (v > high)
    return high;
  return v;
}

U0 DrawSetEvent(U8 *text)
{
  UiLabelSetText(gEvent, text);
  UiStatusSet(gFooter, text);
}

U0 DrawAddPoint(I64 x, I64 y)
{
  I64 i = 1;

  x = DrawClamp(x, 0, DRAW_W - 1);
  y = DrawClamp(y, 0, DRAW_H - 1);
  if (gPaintN >= DRAW_MAX_POINTS) {
    while (i < DRAW_MAX_POINTS) {
      gPtsX[i - 1] = gPtsX[i];
      gPtsY[i - 1] = gPtsY[i];
      gPtsBright[i - 1] = gPtsBright[i];
      i++;
    }
    gPaintN = DRAW_MAX_POINTS - 1;
  }
  gPtsX[gPaintN] = x;
  gPtsY[gPaintN] = y;
  gPtsBright[gPaintN] = UiCheckboxChecked(gBright);
  gPaintN++;
  UiProgressSet(gCount, gPaintN * 100 / DRAW_MAX_POINTS);
}

U0 DrawStar(I64 x, I64 y, Bool bright)
{
  F64 fx = x, fy = y;

  if (bright)
    UiSetColor(1.0, 0.82, 0.08);
  else
    UiSetColor(0.35, 0.68, 1.0);
  UiFillRect(fx - 2.0, fy - 2.0, 4.0, 4.0);
  UiLine(fx - 6.0, fy, fx + 6.0, fy);
  UiLine(fx, fy - 6.0, fx, fy + 6.0);
}

U0 DrawCanvas(UiCtl *c, U0 *data)
{
  I64 i = 0;

  UiSetColor(0.05, 0.06, 0.08);
  UiFillRect(0.0, 0.0, DRAW_W, DRAW_H);

  UiSetColor(0.0, 0.72, 0.78);
  UiFillRect(0.0, 0.0, DRAW_W, 28.0);
  UiSetColor(0.92, 0.92, 0.92);
  UiFillRect(0.0, DRAW_H - 28.0, DRAW_W, 28.0);

  UiSetColor(0.13, 0.16, 0.20);
  while (i < DRAW_W) {
    UiLine(i, 36.0, i, DRAW_H - 36.0);
    i += 40;
  }
  i = 36;
  while (i < DRAW_H - 36) {
    UiLine(0.0, i, DRAW_W, i);
    i += 40;
  }

  i = 0;
  while (i < gPaintN) {
    DrawStar(gPtsX[i], gPtsY[i], gPtsBright[i]);
    i++;
  }

  if (gMouseSeen) {
    if (gMouseDown)
      UiSetColor(1.0, 0.25, 0.18);
    else
      UiSetColor(0.10, 1.0, 0.35);
    UiLine(gMouseX - 10.0, gMouseY, gMouseX + 10.0, gMouseY);
    UiLine(gMouseX, gMouseY - 10.0, gMouseX, gMouseY + 10.0);
  }
}

U0 DrawMouse(UiCtl *c, U0 *data)
{
  U8 *s;

  gMouseX = DrawClamp(UiMouseX(c), 0, DRAW_W - 1);
  gMouseY = DrawClamp(UiMouseY(c), 0, DRAW_H - 1);
  gMouseDown = UiMousePressed(c) && UiMouseButton(c) == 1;
  gMouseSeen = TRUE;

  if (gMouseDown)
    DrawAddPoint(gMouseX, gMouseY);

  s = MStrPrint("mouse: %d,%d button:%d pressed:%d",
    gMouseX, gMouseY, UiMouseButton(c), UiMousePressed(c));
  DrawSetEvent(s);
  Free(s);
  UiCanvasRedraw(gCanvas);
}

U0 DrawClear(UiCtl *c, U0 *data)
{
  gPaintN = 0;
  gMouseSeen = FALSE;
  gMouseDown = FALSE;
  UiProgressSet(gCount, 0);
  DrawSetEvent("resize: 720x420");
  UiCanvasRedraw(gCanvas);
}

U0 DrawQuit(UiCtl *c, U0 *data)
{
  DrawSetEvent("quit");
  UiQuit;
}

U0 Main()
{
  UiInit;

  UiCtl *win = UiWindowNew("lib/ui draw demo", 820, 620);
  UiCtl *m = UiMenuNew("File");
  UiMenuItem(m, "Clear", &DrawClear);
  UiMenuItem(m, "Quit", &DrawQuit);

  UiCtl *box = UiBoxNew;
  UiBoxAdd(box, UiLabelNew("lib/ui draw demo"));
  gEvent = UiLabelNew("resize: 720x420");
  UiBoxAdd(box, gEvent);

  UiCtl *tb = UiToolbarNew;
  UiToolAdd(tb, "Clear", &DrawClear);
  UiToolAdd(tb, "Quit", &DrawQuit);
  UiBoxAdd(box, tb);

  gCanvas = UiCanvasNew(DRAW_W, DRAW_H, &DrawCanvas);
  UiOnMouse(gCanvas, &DrawMouse);
  UiBoxAdd(box, gCanvas);

  gBright = UiCheckboxNew("bright paint", TRUE);
  UiBoxAdd(box, gBright);
  gCount = UiProgressNew;
  UiBoxAdd(box, gCount);
  gFooter = UiStatusbarNew("drag left mouse button to paint");
  UiBoxAdd(box, gFooter);

  UiWindowSetChild(win, box);
  UiShow(win);
  "uidraw: window up, close it to quit\n";
  UiMain;
}

Main;
