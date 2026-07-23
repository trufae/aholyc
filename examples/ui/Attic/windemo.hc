// windemo.hc — a Win32 graphical hello world written in HolyC.
//
// Cross-build from mac/linux with mingw; the llvm backend hardcodes clang,
// so use the c backend, and the wrapper rewrites the host linker-GC flag:
//
//   CC=demos/windows/ccwin.sh ./aholyc -b c examples/ui/windemo.hc -o windemo.exe
//
// or without the driver:
//
//   ./aholyc -b c -S examples/ui/windemo.hc -o windemo.c
//   x86_64-w64-mingw32-gcc -Os -w windemo.c -o windemo.exe -mwindows -luser32 -lm
//
// A window class whose WNDPROC is a HolyC function, a visible window, and
// "Hello, World from HolyC" drawn centered from WM_PAINT. ANSI (*A) APIs
// keep the hello world free of UTF-16, and all-I64 externs are safe on
// Win64, where stack args occupy 8-byte slots (unlike arm64 Darwin).

// @ldflags=-mwindows -luser32

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
extern I64 BeginPaint(I64 hwnd, U0 *ps);
extern I64 EndPaint(I64 hwnd, U0 *ps);
extern I64 GetClientRect(I64 hwnd, U0 *rect);
extern I64 DrawTextA(I64 hdc, U8 *text, I64 len, U0 *rect, I64 fmt);

#define WM_DESTROY 2
#define WM_PAINT 0xF
#define CS_HREDRAW_VREDRAW 3
#define COLOR_WINDOW_BRUSH 6              // COLOR_WINDOW + 1
#define IDC_ARROW 32512
#define WS_OVERLAPPED_VISIBLE 0x10CF0000  // WS_OVERLAPPEDWINDOW | WS_VISIBLE
#define CW_USEDEFAULT 0x80000000
#define DT_CENTERED 0x25                  // DT_CENTER | DT_VCENTER | DT_SINGLELINE

/* @align */ class WndClassExA
{
  U32 size, style;
  I64 wndproc;
  U32 cls_extra, wnd_extra;
  I64 inst, icon, cursor, background;
  U8 *menu_name, *class_name;
  I64 icon_sm;
};

I64 WndProc(I64 hwnd, I64 msg, I64 wp, I64 lp)
{
  U8 ps[80], rc[16];      // PAINTSTRUCT and RECT, touched only by Win32
  I64 hdc;
  switch (msg) {
  case WM_PAINT:
    hdc = BeginPaint(hwnd, ps);
    GetClientRect(hwnd, rc);
    DrawTextA(hdc, "Hello, World from HolyC", -1, rc, DT_CENTERED);
    EndPaint(hwnd, ps);
    return 0;
  case WM_DESTROY:
    PostQuitMessage(0);
    return 0;
  }
  return DefWindowProcA(hwnd, msg, wp, lp);
}

I64 inst = GetModuleHandleA(0);
WndClassExA wc;             // global, zero-initialized
wc.size = sizeof(WndClassExA);
wc.style = CS_HREDRAW_VREDRAW;
wc.wndproc = &WndProc;
wc.inst = inst;
wc.cursor = LoadCursorA(0, IDC_ARROW);
wc.background = COLOR_WINDOW_BRUSH;
wc.class_name = "HolyCWin";
if (!RegisterClassExA(&wc)(U16))
  Exit(1);
CreateWindowExA(0, "HolyCWin", "HolyC on Win32", WS_OVERLAPPED_VISIBLE,
  CW_USEDEFAULT, CW_USEDEFAULT, 480, 320, 0, 0, inst, 0);

U8 m[64];                   // MSG buffer, touched only by Win32
while (GetMessageA(m, 0, 0, 0)(I32) > 0) {
  TranslateMessage(m);
  DispatchMessageA(m);
}
