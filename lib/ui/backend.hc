// check for UI backend depending on

// -DUI_HTK selects the terminal backend on any platform
#ifdef UI_HTK
#undef UI_HTK
#define USE_HTK
#endif

// check flags
#define UI_GTK4 1
#define UI_WIN32 2
#define UI_COCOA 3
#define UI_HTK 4
#define UI_AMIGA 5

#undef USE_GTK4
#undef USE_WIN32
#undef USE_COCOA
#undef USE_AMIGA
#ifdef UI_BACKEND
#if UI_BACKEND == UI_GTK4
#define USE_GTK4
#else
#if UI_BACKEND == UI_WIN32
#define USE_WIN32
#else
#if UI_BACKEND == UI_COCOA
#define USE_COCOA
#else
#if UI_BACKEND == UI_HTK
#define USE_HTK
#else
#if UI_BACKEND == UI_AMIGA
#define USE_AMIGA
#else
#error invalid value for UI_BACKEND, use UI_GTK4, UI_COCOA, UI_WIN32, UI_HTK or UI_AMIGA
#endif
#endif
#endif
#endif
#endif
#endif

// check preferences
#ifdef USE_AMIGA
#include "amiga.hc"
#else
#ifdef USE_HTK
#include "htk.hc"
#else
#ifdef USE_GTK4
#include "gtk4.hc"
#else
#ifdef USE_WIN32
#include "win32.hc"
#else
#ifdef USE_COCOA
#include "cocoa.hc"
#else

// check for OS
#ifdef IS_AMIGA
#include "amiga.hc"
#else
#ifdef IS_MACOS
#include "cocoa.hc"
#else
#ifdef IS_WINDOWS
#include "win32.hc"
#else
#include "gtk4.hc"
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif

