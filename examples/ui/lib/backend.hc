// check for UI backend depending on

// check flags
#define UI_GTK4 1
#define UI_WIN32 2
#define UI_COCOA 3

#undef USE_GTK4
#undef USE_WIN32
#undef USE_COCOA
#ifdef UI_BACKEND
#if UI_BACKEND == UI_GTK4
#define USE_GTK4
#else
#if UIBACKEND == UI_WIN32
#define USE_WIN32
#else
#if UI_BACKEND == UI_COCOA
#define USE_COCOA
#else
#error invalid value for UI_BACKEND, use UI_GTK4, UI_COCOA or UI_WIN32
#endif
#endif
#endif
#endif

// check preferences
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

