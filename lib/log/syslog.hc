// syslog(3) system backend: Linux, the BSDs, and macOS when LOG_SYSLOG is
// defined (where it lands in the unified log through the syslog shim).
//
// Levels map to syslog priorities: FATAL -> ALERT, CRITICAL -> CRIT,
// ERROR -> ERR, WARN -> WARNING, INFO -> INFO, DEBUG and TRACE -> DEBUG.
// The message is passed through "%s", never as the format string.

extern U0 openlog(U8 *ident, I64 option, I64 facility);
extern U0 syslog(I64 priority, U8 *fmt, ...);
extern U0 closelog();

#define LOG_SYSLOG_PID  1
#define LOG_SYSLOG_USER 8

I64 log_syslog_priority[LOG_LEVELS] = { 1, 2, 3, 4, 6, 7, 7 };
U8 *log_syslog_ident;

Bool LogNativeOpen(U8 *name)
{
  // openlog keeps the pointer, so it must outlive the connection.
  log_syslog_ident = StrNew(name);
  openlog(log_syslog_ident, LOG_SYSLOG_PID, LOG_SYSLOG_USER);
  return TRUE;
}

U0 LogNativeWrite(I64 level, U8 *msg)
{
  syslog(log_syslog_priority[level], "%s", msg);
}

U0 LogNativeClose()
{
  closelog;
  Free(log_syslog_ident);
  log_syslog_ident = NULL;
}
