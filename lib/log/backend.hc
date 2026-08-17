// Backend selection for lib/log.
//
// Two layers are picked here.  The OS layer (posix.hc / windows.hc) gives
// the frontend stderr, terminal detection, timestamps, files and getenv;
// it follows the host and can be forced with LOG_POSIX / LOG_WINDOWS.  The
// system backend is the platform log the LOG_TARGET_SYSTEM target writes
// to; define one of these to override the host default:
//
//   -DLOG_SYSLOG    syslog(3)              default on Linux and the BSDs
//   -DLOG_OSLOG     os_log (unified log)   default on macOS
//   -DLOG_EVENTLOG  Windows Event Log      default on Windows
//   -DLOG_GLIB      g_log (GLib/GNOME)     any platform with GLib
//   -DLOG_NONE      no system log; LOG_TARGET_SYSTEM writes nothing

#ifdef LOG_WINDOWS
#include "windows.hc"
#else
#ifdef LOG_POSIX
#include "posix.hc"
#else
#ifdef IS_WINDOWS
#include "windows.hc"
#else
#ifdef IS_UNIX
#include "posix.hc"
#else
#error lib/log supports Linux, macOS, the BSDs and Windows native targets
#endif
#endif
#endif
#endif

#ifdef LOG_NONE
#include "none.hc"
#else
#ifdef LOG_GLIB
#include "glib.hc"
#else
#ifdef LOG_SYSLOG
#include "syslog.hc"
#else
#ifdef LOG_OSLOG
#include "oslog.hc"
#else
#ifdef LOG_EVENTLOG
#include "eventlog.hc"
#else
#ifdef IS_MACOS
#include "oslog.hc"
#else
#ifdef IS_WINDOWS
#include "eventlog.hc"
#else
#include "syslog.hc"
#endif
#endif
#endif
#endif
#endif
#endif
#endif
