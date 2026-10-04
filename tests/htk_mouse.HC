#define UI_HTK
#define HTK_NODESK
#include "lib/ui/ui.hc"

extern I64 pipe(I32 *fds);
extern I64 dup(I64 fd);

I64 failures;
I32 input[2];
I64 canvas_events;

U0 Check(Bool condition, U8 *name)
{
  if (!condition) {
    "FAIL %s\n", name;
    failures++;
  }
}

Bool ReadEvent(U8 *report, CTermEvent *e)
{
  I64 length = StrLen(report);

  Check(write(input[1], report, length) == length, "write mouse report");
  return TermPollEvent(e, 0);
}

U0 Mouse(U8 *report)
{
  CTermEvent e;

  if (ReadEvent(report, &e) && e.type == TERM_EVENT_MOUSE)
    HtkMouse(&e);
  else
    Check(FALSE, "decode mouse report");
}

U0 Tap(I64 x, I64 y)
{
  U8 *report = MStrPrint("\x1B[<0;%d;%dM", x + 1, y + 1);

  Mouse(report);
  report[StrLen(report) - 1] = 'm';
  Mouse(report);
  Free(report);
}

U0 Key(U8 *report)
{
  CTermEvent e;

  if (ReadEvent(report, &e) && e.type == TERM_EVENT_KEY)
    HtkKey(&e);
  else
    Check(FALSE, "decode key report");
}

U0 TestSgr()
{
  CTermEvent e;

  Check(ReadEvent("\x1B[<0;17;6M", &e) &&
    e.type == TERM_EVENT_MOUSE && e.button == TERM_MOUSE_LEFT &&
    e.pressed && !e.motion && e.x == 16 && e.y == 5, "SGR press");
  Check(ReadEvent("\x1B[<32;24;9M", &e) &&
    e.type == TERM_EVENT_MOUSE && e.button == TERM_MOUSE_LEFT &&
    e.pressed && e.motion && e.x == 23 && e.y == 8, "SGR drag");
  Check(ReadEvent("\x1B[<0;24;9m", &e) &&
    e.type == TERM_EVENT_MOUSE && e.button == TERM_MOUSE_LEFT &&
    !e.pressed && !e.motion, "SGR release");
  Check(ReadEvent("\x1B[<60;301;201M", &e) &&
    e.pressed && e.motion && e.x == 300 && e.y == 200 &&
    e.mods == (TERM_MOD_SHIFT | TERM_MOD_ALT | TERM_MOD_CTRL),
    "SGR modified drag and large coordinates");
}

U0 TestWindow()
{
  UiCtl *win = UiWindowNew("Drag", 320, 160);
  HtkCtl *w = UiHtk(win);

  w->x = 10;
  w->y = 5;
  Mouse("\x1B[<0;17;6M");
  Check(htk_drag == w, "capture title bar");
  Mouse("\x1B[<32;24;9M");
  Check(w->x == 17 && w->y == 8, "move window");
  Mouse("\x1B[<64;30;10M");
  Check(w->x == 17 && w->y == 8 && htk_drag == w,
    "wheel does not move window or end drag");
  Mouse("\x1B[<2;30;10m");
  Check(w->x == 17 && w->y == 8 && htk_drag == w,
    "another button's release does not end drag");
  Mouse("\x1B[<0;26;11m");
  Check(w->x == 19 && w->y == 10 && !htk_drag,
    "release applies final position and ends drag");
  Tap(w->x + 6, w->y);
  Check(w->x == 19 && w->y == 10 && !htk_drag, "title tap leaves window still");
  Tap(w->x + w->w - 2, w->y + w->h - 1);
  Check(w->w == 40 && w->h == 10, "corner tap does not resize window");
  Mouse("\x1B[<0;58;20M");
  Mouse("\x1B[<32;61;22M");
  Mouse("\x1B[<0;63;23m");
  Check(w->w == 45 && w->h == 13 && !htk_drag, "resize keeps corner grab offset");
  UiWindowClose(win);
}

U0 MoveMenu(HtkCtl *w)
{
  Tap(w->x + 3, w->y);
  Check(htk_popup != NULL, "tap opens system menu");
  if (htk_popup)
    Tap(htk_popup->x + 2, htk_popup->y + 1);
}

U0 TestTouchMove()
{
  UiCtl *win = UiWindowNew("Touch", 320, 160);
  HtkCtl *w = UiHtk(win);

  w->x = 10;
  w->y = 5;
  MoveMenu(w);
  Check(htk_move == w && !htk_popup && !htk_drag,
    "menu tap release keeps Move active");
  Mouse("\x1B[<65;17;6M");
  Check(htk_move == w && w->x == 10 && w->y == 5,
    "touch swipe does not place window");
  Tap(50, 20);
  Check(!htk_move && !htk_drag && w->x == 30 && w->y == 20,
    "destination tap places title center without starting a drag");
  MoveMenu(w);
  Key("\x1B[C");
  Key("\x1B[B");
  Check(w->x == 31 && w->y == 21, "Move arrow keys");
  Key("\x1B");
  Check(!htk_move && w->x == 30 && w->y == 20, "Escape restores original position");
  MoveMenu(w);
  Key("\x1B[D");
  Key("\r");
  Check(!htk_move && w->x == 29 && w->y == 20, "Enter accepts keyboard move");
  MoveMenu(w);
  Key("\x1B[D");
  HtkWindowMenuOpen(w, 0, 0);
  Check(!htk_move && w->x == 29 && w->y == 20,
    "opening another popup cancels Move");
  HtkPopupClose;
  MoveMenu(w);
  Tap(99, 39);
  Check(!htk_move && w->x == 79 && w->y == 39,
    "destination can reach desktop edge");
  HtkWindowMaximize(w);
  HtkWindowLayout(w);
  MoveMenu(w);
  Check(!htk_move && htk_wm_move->disabled, "maximized window cannot enter Move");
  HtkWindowMaximize(w);
  MoveMenu(w);
  HtkWindowMinimize(w);
  Check(!htk_move, "minimizing window ends Move");
  HtkWindowRestore(w);
  MoveMenu(w);
  UiWindowClose(win);
  Check(!htk_move, "closing window ends Move");
}

U0 OnMouse(UiCtl *c, U0 *data)
{
  canvas_events++;
}

U0 TestCanvas()
{
  UiCtl *win = UiWindowNew("Canvas", 320, 160);
  UiCtl *canvas = UiCanvasNew(160, 80, NULL);
  HtkCtl *w = UiHtk(win);

  UiWindowSetChild(win, canvas);
  UiOnMouse(canvas, &OnMouse);
  w->x = 10;
  w->y = 5;
  HtkWindowLayout(w);
  Mouse("\x1B[<0;15;8M");
  Check(canvas_events == 1 && UiMousePressed(canvas), "canvas press callback");
  Mouse("\x1B[<32;16;9M");
  Check(canvas_events == 2 && UiMouseMotion(canvas), "canvas motion callback");
  Mouse("\x1B[<0;17;10m");
  Check(canvas_events == 3 && !UiMousePressed(canvas) && !htk_drag,
    "canvas gets exactly one release callback");
  MoveMenu(w);
  Tap(50, 20);
  Check(canvas_events == 3 && !htk_drag,
    "placing a window does not click its canvas");
  UiWindowClose(win);
}

U0 TestTouchTitle()
{
  UiCtl *win = UiWindowNew("Touch title", 320, 160);
  UiCtl *canvas = UiCanvasNew(160, 80, NULL);
  HtkCtl *w = UiHtk(win);
  I64 events = canvas_events;

  htk_touch_titles = TRUE;
  UiWindowSetChild(win, canvas);
  UiOnMouse(canvas, &OnMouse);
  w->x = 10;
  w->y = 5;
  HtkWindowLayout(w);
  // Real Termux finger scrolls have no button press, motion or release,
  // and every wheel report in the gesture repeats the same coordinates.
  Mouse("\x1B[<65;17;6M");
  Mouse("\x1B[<65;17;6M");
  Mouse("\x1B[<64;17;6M");
  Check(htk_move == w && !htk_drag && w->x == 10 && w->y == 5,
    "wheel-only title swipe offers Move without requiring a release");
  Tap(36, 15);
  Check(!htk_move && !htk_drag && w->x == 30 && w->y == 15,
    "title swipe placement preserves the grabbed title offset");
  Check(canvas_events == events, "title swipe placement does not click canvas");

  Tap(w->x + 8, w->y);
  Check(htk_move == w && !htk_drag, "title tap offers Move on finger-up");
  Tap(40, 16);
  Check(!htk_move && !htk_drag && w->x == 32 && w->y == 16,
    "title tap placement preserves the grabbed title offset");
  Tap(w->x + 8, w->y);
  Key("\x1B[C");
  Key("\x1B");
  Check(!htk_move && w->x == 32 && w->y == 16,
    "Escape cancels title Move and restores its original position");

  Mouse("\x1B[<0;39;17M");
  Mouse("\x1B[<32;43;19M");
  Mouse("\x1B[<64;43;19M");
  Mouse("\x1B[<0;45;20m");
  Check(!htk_move && !htk_drag && w->x == 38 && w->y == 19,
    "physical mouse still drags normally on Termux");
  Mouse("\x1B[<0;45;20M");
  Mouse("\x1B[<32;45;20M");
  Mouse("\x1B[<0;45;20m");
  Check(!htk_move && !htk_drag,
    "physical motion within one cell does not become a title tap");

  HtkWindowLayout(w);
  Mouse("\x1B[<65;43;22M");
  Check(!htk_move && canvas_events == events + 1 &&
    UiMouseButton(canvas) == TERM_MOUSE_WHEEL_DOWN,
    "content wheel still reaches the canvas");
  Tap(w->x + 3, w->y);
  Check(htk_popup && !htk_move, "touch title system-menu button still opens menu");
  HtkPopupClose;
  HtkWindowMaximize(w);
  HtkWindowLayout(w);
  Mouse("\x1B[<65;7;1M");
  Tap(6, 0);
  Check(!htk_move && !htk_drag, "maximized title cannot enter touch Move");
  HtkWindowMaximize(w);

  htk_touch_titles = FALSE;
  Mouse("\x1B[<65;45;20M");
  Tap(w->x + 6, w->y);
  Check(!htk_move && !htk_drag && w->x == 38 && w->y == 19,
    "ordinary terminals keep title wheel and tap behavior");
  UiWindowClose(win);
}

U0 TestKeyboardGeometry()
{
  UiCtl *win = UiWindowNew("Keyboard", 320, 160);
  HtkCtl *w = UiHtk(win);
  HtkCtl *entry = HtkEntryNew("text");

  HtkAdd(w, entry);
  HtkSetFocus(entry);
  w->x = 10;
  w->y = 5;
  HtkWindowKeysDefault;
  // Alt-F7 and Alt-F8 go through the terminal's modified-key decoder.
  Key("\x1B[18;3~");
  Check(htk_move == w && !htk_move_resize, "Alt-F7 enters Move");
  Key("\x1B[C");
  Key("\x1B[1;2B");
  Check(w->x == 11 && w->y == 10 && !StrCmp(entry->text, "text"),
    "Move arrows and Shift-arrows consume keys before focused control");
  Key("\x1B");
  Check(!htk_move && w->x == 10 && w->y == 5, "keyboard Move cancellation");
  Key("\x1B[18;3~");
  Key("\x1B[C");
  Key("\r");
  Check(!htk_move && w->x == 11 && w->y == 5, "keyboard Move acceptance");

  HtkWindowSetSizeLimits(w, 38, 8, 42, 16);
  Key("\x1B[19;3~");
  Check(htk_move == w && htk_move_resize, "Alt-F8 enters Resize");
  Key("\x1B[C");
  Key("\x1B[1;2B");
  Check(w->w == 41 && w->h == 15 && w->x == 11 && w->y == 5,
    "Resize arrows move bottom-right corner with fixed origin");
  Key("\x1B[1;2C");
  Key("\x1B[1;2B");
  Check(w->w == 42 && w->h == 16, "keyboard Resize respects maximum size");
  Key("\x1B");
  Check(!htk_move && !htk_move_resize && w->w == 40 && w->h == 10,
    "Escape restores original size after Resize");
  Key("\x1B[19;3~");
  Key("\x1B[1;2D");
  Key("\x1B[1;2A");
  Check(w->w == 38 && w->h == 8, "keyboard Resize respects minimum size");
  Key("\r");
  Check(!htk_move && w->w == 38 && w->h == 8, "Enter accepts Resize");
  HtkWindowSetSizeLimits(w);

  Key("\x07");
  Check(htk_popup != NULL, "Ctrl-G opens keyboard window menu");
  Key("\x1B[B");
  Key("\r");
  Check(htk_move == w && htk_move_resize && !htk_popup,
    "Resize can be selected entirely through keyboard menu");
  Mouse("\x1B[<65;17;6M");
  Check(htk_move == w && w->w == 38, "wheel does not place Resize");
  Tap(w->x + 44, w->y + 14);
  Check(!htk_move && !htk_drag && w->w == 45 && w->h == 15,
    "Resize destination tap places bottom-right corner");

  Check(HtkWindowSetKeybinding(HTK_WM_MOVE, 'm', TERM_MOD_ALT) &&
    HtkWindowSetKeybinding(HTK_WM_RESIZE, 'r', TERM_MOD_ALT),
    "configure window activation shortcuts");
  Check(!HtkWindowSetKeybinding(HTK_WM_RESIZE, 'm', TERM_MOD_ALT) &&
    !HtkWindowSetKeybinding(HTK_WM_MOVE, 'm', 8),
    "reject conflicting shortcuts and invalid modifiers");
  Key("\x1B[18;3~");
  Check(!htk_move, "rebinding removes previous activation shortcut");
  Key("\x1Bm");
  Check(htk_move == w && !htk_move_resize, "custom Alt-M starts Move");
  Key("\x1B");
  Key("\x1Br");
  Check(htk_move == w && htk_move_resize, "custom Alt-R starts Resize");
  Key("\x1B");
  HtkWindowSetKeybinding(HTK_WM_MOVE, 0);
  Key("\x1Bm");
  Check(!htk_move, "zero key disables activation shortcut");
  HtkWindowKeysDefault;

  HtkWindowMaximize(w);
  HtkWindowLayout(w);
  Key("\x1B[18;3~");
  Key("\x1B[19;3~");
  Check(!htk_move, "maximized window rejects geometry shortcuts");
  HtkWindowMenuOpen(w, 2, 1);
  Check(htk_wm_resize->disabled, "maximized Resize menu item is disabled");
  HtkPopupClose;
  HtkWindowMaximize(w);
  HtkWindowResizeBegin(w);
  Key("\x1B[C");
  HtkWindowMenuOpen(w, w->x + 2, w->y + 1);
  Check(!htk_move && w->w == 45 && w->h == 15,
    "opening a popup cancels Resize and restores geometry");
  HtkPopupClose;
  HtkWindowResizeBegin(w);
  HtkWindowMinimize(w);
  Check(!htk_move, "minimizing window ends Resize");
  HtkWindowRestore(w);
  HtkWindowResizeBegin(w);
  UiWindowClose(win);
  Check(!htk_move, "closing window ends Resize");
}

I64 saved_input = dup(0)(I32);
if (pipe(input)(I32) || saved_input < 0 || dup2(input[0], 0)(I32) < 0)
  Exit(1);
close(input[0]);
term_started = TRUE;
term_width = 100;
term_height = 40;
TestSgr;
TestWindow;
TestTouchMove;
TestCanvas;
TestTouchTitle;
TestKeyboardGeometry;
term_started = FALSE;
dup2(saved_input, 0);
close(saved_input);
close(input[1]);
"htk mouse: %d failures\n", failures;
Exit(failures != 0);
