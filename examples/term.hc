// Interactive lib/term demo: draws a status ribbon, echoes events, lets the
// mouse paint, and survives resizes.  Quit with q or ^C.
#include "../lib/term/term.hc"

Bool demo_dirty;

U0 DemoResized(I64 width, I64 height)
{
  demo_dirty = TRUE;
  TermFill(0, 0, width, height);
}

U0 DemoChrome()
{
  I64 width = TermWidth;
  I64 height = TermHeight;

  TermFill(0, 0, width, 1, ' ', TERM_BLACK, TERM_CYAN);
  TermText(1, 0, "lib/term demo", TERM_BLACK, TERM_CYAN, TERM_BOLD);
  TermFill(0, height - 1, width, 1, ' ', TERM_BLACK, TERM_WHITE);
  TermText(1, height - 1, "q quits, ^C interrupts, drag to paint",
    TERM_BLACK, TERM_WHITE);
}

U0 DemoEvent(CTermEvent *event)
{
  U8 line[80];

  if (event->type == TERM_EVENT_KEY) {
    if (event->key > 0x20 && event->key < 0x110000)
      StrPrint(line, "key: %c mods:%d      ", event->key, event->mods);
    else
      StrPrint(line, "key: 0x%X mods:%d      ", event->key, event->mods);
  } else if (event->type == TERM_EVENT_MOUSE) {
    StrPrint(line, "mouse: %d,%d button:%d pressed:%d  ",
      event->x, event->y, event->button, event->pressed);
    if (event->pressed && event->button == TERM_MOUSE_LEFT)
      TermCell(event->x, event->y, '*', TERM_BRIGHT_YELLOW);
  } else if (event->type == TERM_EVENT_RESIZE)
    StrPrint(line, "resize: %dx%d        ", event->width, event->height);
  else
    return;
  TermText(2, 2, line, TERM_BRIGHT_GREEN);
}

U0 Main()
{
  CTermEvent event;

  if (!TermInit) {
    "lib/term needs an interactive terminal\n";
    return;
  }
  TermMouse;
  TermShowCursor(FALSE);
  TermOnResize(&DemoResized);
  demo_dirty = TRUE;
  while (TRUE) {
    if (demo_dirty) {
      DemoChrome;
      demo_dirty = FALSE;
    }
    TermCommit;
    if (TermPollEvent(&event, 100)) {
      if (event.type == TERM_EVENT_KEY && event.key == 'q')
        break;
      DemoEvent(&event);
    }
    if (TermInterrupted)
      break;
  }
  TermFini;
  "bye\n";
}

Main;
