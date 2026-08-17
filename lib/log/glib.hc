// GLib system backend: g_log with the LogInit name as the log domain, so
// GNOME applications get their messages through the GLib handlers,
// journald writer and G_MESSAGES_DEBUG filtering like any other domain.
// Works on any platform with GLib; select with -DLOG_GLIB.
// @pkgconfig=glib-2.0
//
// Levels map to G_LOG_LEVEL_*: FATAL -> ERROR (GLib aborts on it, which
// matches LOG_FATAL), CRITICAL and ERROR -> CRITICAL (GLib has no non-fatal
// error level), WARN -> WARNING, INFO -> INFO, DEBUG and TRACE -> DEBUG.

extern U0 g_log(U8 *domain, I64 level, U8 *fmt, ...);

I64 log_glib_level[LOG_LEVELS] = { 4, 8, 8, 16, 64, 128, 128 };
U8 *log_glib_domain;

Bool LogNativeOpen(U8 *name)
{
  log_glib_domain = StrNew(name);
  return TRUE;
}

U0 LogNativeWrite(I64 level, U8 *msg)
{
  g_log(log_glib_domain, log_glib_level[level], "%s", msg);
}

U0 LogNativeClose()
{
  Free(log_glib_domain);
  log_glib_domain = NULL;
}
