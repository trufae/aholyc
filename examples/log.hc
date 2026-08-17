// lib/log demo: levels, targets, source locations, timestamps and a
// callback.  Build and run:
//   aholyc examples/log.hc -o log && ./log
//   HC_LOG_LEVEL=trace HC_LOG_TS=1 HC_LOG_SOURCE=1 ./log
//   HC_LOG_TARGET=stderr,system ./log      # also syslog/os_log/Event Log
//   aholyc -DLOG_GLIB examples/log.hc -o log  # GNOME: g_log domain "logdemo"
#include "lib/log/log.hc"

Bool Tap(I64 level, U8 *file, I64 line, U8 *msg, U0 *data)
{
  I64 *count = data;

  (*count)++;
  return FALSE;  // not handled: the other targets still see it
}

U0 Main()
{
  I64 seen = 0;

  LogInit("logdemo");
  LogSetCallback(&Tap, &seen);
  LogInfo("starting up, level is %s", LogLevelName(LogLevel));
  LogWarn("disk %d%% full", 91);
  LogError("cannot open %s", "/etc/nothing");
  LogDebug("hidden unless HC_LOG_LEVEL=debug");

  LogSetSource(TRUE);
  LogAt(LOG_WARN, LOG_HERE, "with a source location");
  LogSetSource(FALSE);

  LogSetTimestamp(TRUE);
  LogInfo("with a timestamp");
  LogSetTimestamp(FALSE);

  if (LogSetFile("log-demo.txt")) {
    LogInfo("this line also goes to log-demo.txt");
    LogSetFile(NULL);
  }

  LogSetPrivacy(TRUE);
  LogInfo("user %{public}s from %s pin %{private}d", "alice", "10.0.0.1", 42);
  LogSetPrivacy(FALSE);

  LogSetLevel(LOG_TRACE);
  LogTrace("now trace is visible; %d messages reached the callback", seen);
  LogFini;
}
Main;
