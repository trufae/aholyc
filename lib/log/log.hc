#ifndef AHOLYC_LIB_LOG_HC
#define AHOLYC_LIB_LOG_HC

// Portable logging for aholyc's native backends, in the spirit of
// radare2's r_log: one call site, several sinks.
//
// A message has a level and optionally a source location; it is formatted
// once and handed to every enabled target: stderr (colored on a tty), an
// append-only file, the platform's system log, and an application
// callback.  The system backend is chosen at compile time and abstracts
// syslog (Unix), os_log (macOS), the Windows Event Log, or GLib's g_log —
// the last is what GNOME applications want, and it works on any platform
// with GLib.  Define exactly one of LOG_SYSLOG, LOG_OSLOG, LOG_EVENTLOG,
// LOG_GLIB or LOG_NONE to override the host default (see backend.hc).
//
// Levels (lower is more severe; a message is emitted when its level is
// less than or equal to the threshold set with LogSetLevel):
//   LOG_FATAL LOG_CRITICAL LOG_ERROR LOG_WARN LOG_INFO LOG_DEBUG LOG_TRACE
// LOG_FATAL is written to every target and then the process exits with
// status 1 (GLib maps it to G_LOG_LEVEL_ERROR, which aborts by itself).
//
// Emitting:
//   U0   LogFatal/LogCritical/LogError/LogWarn/LogInfo/LogDebug/LogTrace(fmt, ...);
//   U0   LogMsg(level, fmt, ...);
//   U0   LogAt(level, file, line, fmt, ...);   // with a source location
//   Bool LogEnabled(level);                    // cheap check before formatting
// HolyC has no function-like macros, so LOG_HERE expands to
// `__FILE__, __LINE__` for LogAt: LogAt(LOG_ERROR, LOG_HERE, "bad %d", n);
//
// Configuration (every setter is optional; the first message auto-inits):
//   U0   LogInit(name=NULL);        // tag/ident/subsystem/domain; reads env
//   U0   LogFini();
//   U0   LogSetLevel(level);        // default LOG_INFO
//   I64  LogLevel();
//   U0   LogSetTarget(mask);        // LOG_TARGET_* bits, default STDERR
//   I64  LogTarget();
//   Bool LogSetFile(path);          // enables LOG_TARGET_FILE; NULL closes it
//   U0   LogSetCallback(fn, data);  // Bool (*)(I64 level, U8 *file, I64 line,
//                                   //           U8 *msg, U0 *data); TRUE = handled
//   U0   LogSetSource(on);          // prefix [file:line], default off
//   U0   LogSetTimestamp(on);       // prefix local time, default off
//   U0   LogSetColor(on);           // default: on when stderr is a terminal
//   U0   LogSetPrivacy(on);         // redact %s arguments, default off
//   U8  *LogLevelName(level);       // "ERROR", ...
//   I64  LogLevelParse(name);       // "error", "3", ... -> level, -1 if unknown
//
// Privacy, like Apple's os_log: with LogSetPrivacy(TRUE) every %s argument
// is rendered as <private> unless the specifier is annotated %{public}s;
// %{private}d (any conversion) forces redaction even when privacy is off.
// The annotations are always accepted and stripped, so formats can carry
// them unconditionally: LogInfo("user %{public}s from %s", name, ip);
//
// Environment (read by LogInit): HC_LOG_LEVEL (name or number), HC_LOG_FILE,
// HC_LOG_TARGET (comma list of stderr,file,system,none), HC_LOG_SOURCE,
// HC_LOG_TS, HC_LOG_COLOR, HC_LOG_PRIVACY (0/1).

#define LOG_FATAL    0
#define LOG_CRITICAL 1
#define LOG_ERROR    2
#define LOG_WARN     3
#define LOG_INFO     4
#define LOG_DEBUG    5
#define LOG_TRACE    6
#define LOG_LEVELS   7

#define LOG_TARGET_NONE   0
#define LOG_TARGET_STDERR 1
#define LOG_TARGET_FILE   2
#define LOG_TARGET_SYSTEM 4
#define LOG_TARGET_ALL    7

#define LOG_HERE __FILE__, __LINE__

I64 log_level = LOG_INFO;
I64 log_target = LOG_TARGET_STDERR;
Bool log_source;
Bool log_timestamp;
Bool log_color;
Bool log_color_set;
Bool log_started;
Bool log_system_open;
U8 *log_name;
U8 *log_file_path;
U8 *log_file_handle;
Bool (*log_callback)(I64 level, U8 *file, I64 line, U8 *msg, U0 *data);
U0 *log_callback_data;
Bool log_in_fatal;
Bool log_privacy;

#define LOG_REDACTED "<private>"

U8 *log_level_names[LOG_LEVELS] = {
  "FATAL", "CRITICAL", "ERROR", "WARN", "INFO", "DEBUG", "TRACE"
};

// SGR color per level: fatal/critical bold red, error red, warn yellow,
// info green, debug cyan, trace magenta.
U8 *log_level_colors[LOG_LEVELS] = {
  "\x1B[1;91m", "\x1B[1;31m", "\x1B[31m", "\x1B[33m", "\x1B[32m", "\x1B[36m",
    "\x1B[35m"
};

// The OS layer (stderr, tty detection, time, files) and the system backend
// (syslog/os_log/Event Log/GLib/none) are selected in backend.hc.  Each
// provides:
//   U0   LogOsWrite(U8 *text, I64 len);            // to stderr
//   Bool LogOsIsTty();                              // stderr is a terminal
//   U0   LogOsTimestamp(U8 *buf);                   // "YYYY-MM-DD HH:MM:SS.mmm"
//   U8  *LogOsFileOpen(U8 *path);                   // append mode, NULL on error
//   U0   LogOsFileWrite(U8 *handle, U8 *text, I64 len);
//   U0   LogOsFileClose(U8 *handle);
//   U8  *LogOsGetEnv(U8 *name);
//   Bool LogNativeOpen(U8 *name);
//   U0   LogNativeWrite(I64 level, U8 *msg);        // one message, no newline
//   U0   LogNativeClose();
#include "backend.hc"

public U8 *LogLevelName(I64 level)
{
  if (level < 0)
    level = 0;
  if (level >= LOG_LEVELS)
    level = LOG_LEVELS - 1;
  return log_level_names[level];
}

Bool LogStrEqNoCase(U8 *a, U8 *b)
{
  I64 i = 0;
  I64 x, y;

  while (a[i] || b[i]) {
    x = a[i];
    y = b[i];
    if (x >= 'A' && x <= 'Z')
      x += 32;
    if (y >= 'A' && y <= 'Z')
      y += 32;
    if (x != y)
      return FALSE;
    i++;
  }
  return TRUE;
}

// Accepts a level name ("warn", "WARNING", "err") or a number.
public I64 LogLevelParse(U8 *name)
{
  I64 i, value = 0;

  if (!name || !*name)
    return -1;
  if (*name >= '0' && *name <= '9') {
    for (i = 0; name[i] >= '0' && name[i] <= '9'; i++)
      value = value * 10 + name[i] - '0';
    if (name[i])
      return -1;
    if (value >= LOG_LEVELS)
      value = LOG_LEVELS - 1;
    return value;
  }
  for (i = 0; i < LOG_LEVELS; i++)
    if (LogStrEqNoCase(name, log_level_names[i]))
      return i;
  if (LogStrEqNoCase(name, "warning"))
    return LOG_WARN;
  if (LogStrEqNoCase(name, "err"))
    return LOG_ERROR;
  if (LogStrEqNoCase(name, "crit"))
    return LOG_CRITICAL;
  if (LogStrEqNoCase(name, "verbose"))
    return LOG_TRACE;
  return -1;
}

public U0 LogSetLevel(I64 level)
{
  if (level < 0)
    level = 0;
  if (level >= LOG_LEVELS)
    level = LOG_LEVELS - 1;
  log_level = level;
}

public I64 LogLevel()
{
  return log_level;
}

public Bool LogEnabled(I64 level)
{
  return level <= log_level;
}

public U0 LogSetTarget(I64 mask)
{
  log_target = mask & LOG_TARGET_ALL;
}

public I64 LogTarget()
{
  return log_target;
}

public U0 LogSetSource(Bool on=TRUE)
{
  log_source = on;
}

public U0 LogSetTimestamp(Bool on=TRUE)
{
  log_timestamp = on;
}

public U0 LogSetColor(Bool on=TRUE)
{
  log_color = on;
  log_color_set = TRUE;
}

public U0 LogSetPrivacy(Bool on=TRUE)
{
  log_privacy = on;
}

public U0 LogSetCallback(U0 *fn, U0 *data=NULL)
{
  log_callback = fn;
  log_callback_data = data;
}

// Opens path for appending and enables LOG_TARGET_FILE; NULL closes the
// current file and disables the target.
public Bool LogSetFile(U8 *path)
{
  if (log_file_handle) {
    LogOsFileClose(log_file_handle);
    log_file_handle = NULL;
  }
  Free(log_file_path);
  log_file_path = NULL;
  if (!path || !*path) {
    log_target &= ~LOG_TARGET_FILE;
    return TRUE;
  }
  log_file_handle = LogOsFileOpen(path);
  if (!log_file_handle) {
    log_target &= ~LOG_TARGET_FILE;
    return FALSE;
  }
  log_file_path = StrNew(path);
  log_target |= LOG_TARGET_FILE;
  return TRUE;
}

// "stderr,file,system" -> mask; "none" or "" -> 0; unknown words ignored.
I64 LogTargetParse(U8 *list)
{
  I64 mask = 0, i = 0, start;
  U8 word[16];
  I64 wl;

  while (list[i]) {
    start = i;
    while (list[i] && list[i] != ',' && list[i] != ' ')
      i++;
    wl = i - start;
    if (wl > 15)
      wl = 15;
    MemCpy(word, list + start, wl);
    word[wl] = 0;
    if (LogStrEqNoCase(word, "stderr") || LogStrEqNoCase(word, "console"))
      mask |= LOG_TARGET_STDERR;
    else if (LogStrEqNoCase(word, "file"))
      mask |= LOG_TARGET_FILE;
    else if (LogStrEqNoCase(word, "system") || LogStrEqNoCase(word, "syslog"))
      mask |= LOG_TARGET_SYSTEM;
    else if (LogStrEqNoCase(word, "all"))
      mask |= LOG_TARGET_ALL;
    if (list[i])
      i++;
  }
  return mask;
}

Bool LogEnvBool(U8 *name, Bool current)
{
  U8 *value = LogOsGetEnv(name);

  if (!value || !*value)
    return current;
  return *value != '0' && *value != 'n' && *value != 'N' && *value != 'f' &&
    *value != 'F';
}

public U0 LogFini()
{
  if (log_system_open)
    LogNativeClose;
  log_system_open = FALSE;
  LogSetFile(NULL);
  Free(log_name);
  log_name = NULL;
  log_started = FALSE;
}

// name is the tag seen by the system log (syslog ident, os_log subsystem,
// Event Log source, GLib domain).  It also reads the HC_LOG_* environment.
public U0 LogInit(U8 *name=NULL)
{
  U8 *value;
  I64 level;

  if (log_started)
    LogFini;
  log_started = TRUE;
  if (!name)
    name = "aholyc";
  log_name = StrNew(name);
  value = LogOsGetEnv("HC_LOG_LEVEL");
  if (value) {
    level = LogLevelParse(value);
    if (level >= 0)
      log_level = level;
  }
  value = LogOsGetEnv("HC_LOG_TARGET");
  if (value)
    log_target = LogTargetParse(value);
  value = LogOsGetEnv("HC_LOG_FILE");
  if (value && *value)
    LogSetFile(value);
  log_source = LogEnvBool("HC_LOG_SOURCE", log_source);
  log_timestamp = LogEnvBool("HC_LOG_TS", log_timestamp);
  log_privacy = LogEnvBool("HC_LOG_PRIVACY", log_privacy);
  value = LogOsGetEnv("HC_LOG_COLOR");
  if (value && *value)
    LogSetColor(LogEnvBool("HC_LOG_COLOR", log_color));
  if (!log_color_set)
    log_color = LogOsIsTty;
}

// Strip the directory so locations read as [file.hc:12].
U8 *LogBaseName(U8 *path)
{
  U8 *base = path;
  I64 i;

  for (i = 0; path[i]; i++)
    if (path[i] == '/' || path[i] == '\\')
      base = path + i + 1;
  return base;
}

// The message body shared by every target: "[file:line] text" or "text".
U8 *LogBody(U8 *file, I64 line, U8 *text)
{
  if (log_source && file)
    return MStrPrint("[%s:%d] %s", LogBaseName(file), line, text);
  return StrNew(text);
}

// The line written to stderr and to the file, without color when plain.
U8 *LogLine(I64 level, U8 *body, Bool color)
{
  U8 stamp[32];
  U8 *ts = "";
  U8 *sep = "";
  U8 *on = "";
  U8 *off = "";

  if (log_timestamp) {
    LogOsTimestamp(stamp);
    ts = stamp;
    sep = " ";
  }
  if (color) {
    on = log_level_colors[level];
    off = "\x1B[0m";
  }
  return MStrPrint("%s%s%s%s:%s %s\n", ts, sep, on, LogLevelName(level), off,
    body);
}

U0 LogEmit(I64 level, U8 *file, I64 line, U8 *text)
{
  U8 *body, *out;

  if (!log_started)
    LogInit;
  if (log_callback && log_callback(level, file, line, text, log_callback_data))
    return;
  body = LogBody(file, line, text);
  if (log_target & LOG_TARGET_STDERR) {
    out = LogLine(level, body, log_color);
    LogOsWrite(out, StrLen(out));
    Free(out);
  }
  if (log_target & LOG_TARGET_FILE && log_file_handle) {
    out = LogLine(level, body, FALSE);
    LogOsFileWrite(log_file_handle, out, StrLen(out));
    Free(out);
  }
  if (log_target & LOG_TARGET_SYSTEM) {
    if (!log_system_open)
      log_system_open = LogNativeOpen(log_name);
    if (log_system_open)
      LogNativeWrite(level, body);
  }
  Free(body);
}

// Does fmt carry a %{public}/%{private} annotation?
Bool LogHasAnnotation(U8 *fmt)
{
  I64 i;

  for (i = 0; fmt[i]; i++)
    if (fmt[i] == '%' && fmt[i + 1] == '{')
      return TRUE;
  return FALSE;
}

// Rewrite fmt for the privacy rules: %{public}/%{private} annotations are
// stripped, and every specifier that must be hidden (any %s when privacy is
// on, anything marked %{private}) is replaced by the literal <private> with
// its argument dropped from the list.  Returns a MAlloc'd format; *out_argc
// and out_argv (room for argc entries) receive the surviving arguments.
U8 *LogRedactFormat(U8 *fmt, I64 argc, I64 *argv, I64 *out_argc, I64 *out_argv)
{
  I64 in = 0, out = 0, arg = 0, kept = 0, start;
  I64 len = StrLen(fmt);
  U8 *res = MAlloc(len * StrLen(LOG_REDACTED) + 1);
  I64 mode;  // 0 default, 1 public, 2 private
  U8 conv;

  while (fmt[in]) {
    if (fmt[in] != '%') {
      res[out++] = fmt[in++];
    } else if (fmt[in + 1] == '%') {
      res[out++] = '%';
      res[out++] = '%';
      in += 2;
    } else {
      start = in;
      in++;
      mode = 0;
      if (fmt[in] == '{') {
        if (!MemCmp(fmt + in, "{public}", 8)) {
          mode = 1;
          in += 8;
        } else if (!MemCmp(fmt + in, "{private}", 9)) {
          mode = 2;
          in += 9;
        } else {
          // Unknown annotation: skip to the closing brace.
          while (fmt[in] && fmt[in] != '}')
            in++;
          if (fmt[in])
            in++;
        }
      }
      while (fmt[in] == '-' || fmt[in] == '0' || fmt[in] == '+' ||
        fmt[in] == ' ' || fmt[in] == '.' || (fmt[in] >= '0' && fmt[in] <= '9'))
        in++;
      conv = fmt[in];
      if (conv)
        in++;
      if (conv == 's' && mode == 0 && log_privacy)
        mode = 2;
      if (mode == 2) {
        MemCpy(res + out, LOG_REDACTED, StrLen(LOG_REDACTED));
        out += StrLen(LOG_REDACTED);
        arg++;
      } else {
        // Copy the specifier without its annotation.
        res[out++] = '%';
        start++;
        if (fmt[start] == '{') {
          while (fmt[start] != '}')
            start++;
          start++;
        }
        while (start < in)
          res[out++] = fmt[start++];
        if (conv && arg < argc)
          out_argv[kept++] = argv[arg];
        arg++;
      }
    }
  }
  res[out] = 0;
  *out_argc = kept;
  return res;
}

U0 LogDispatch(I64 level, U8 *file, I64 line, U8 *fmt, I64 argc, I64 *argv)
{
  U8 *text, *safe;
  I64 kept;
  I64 *kept_argv;

  if (level < 0)
    level = 0;
  if (level >= LOG_LEVELS)
    level = LOG_LEVELS - 1;
  if (level > log_level)
    return;
  if (log_privacy || LogHasAnnotation(fmt)) {
    kept_argv = MAlloc(8 * (argc + 1));
    safe = LogRedactFormat(fmt, argc, argv, &kept, kept_argv);
    text = StrPrintJoin(NULL, safe, kept, kept_argv);
    Free(safe);
    Free(kept_argv);
  } else
    text = StrPrintJoin(NULL, fmt, argc, argv);
  LogEmit(level, file, line, text);
  Free(text);
  if (level == LOG_FATAL && !log_in_fatal) {
    log_in_fatal = TRUE;
    LogFini;
    Exit(1);
  }
}

public U0 LogAt(I64 level, U8 *file, I64 line, U8 *fmt, ...)
{
  LogDispatch(level, file, line, fmt, argc, argv);
}

public U0 LogMsg(I64 level, U8 *fmt, ...)
{
  LogDispatch(level, NULL, 0, fmt, argc, argv);
}

public U0 LogFatal(U8 *fmt, ...)
{
  LogDispatch(LOG_FATAL, NULL, 0, fmt, argc, argv);
}

public U0 LogCritical(U8 *fmt, ...)
{
  LogDispatch(LOG_CRITICAL, NULL, 0, fmt, argc, argv);
}

public U0 LogError(U8 *fmt, ...)
{
  LogDispatch(LOG_ERROR, NULL, 0, fmt, argc, argv);
}

public U0 LogWarn(U8 *fmt, ...)
{
  LogDispatch(LOG_WARN, NULL, 0, fmt, argc, argv);
}

public U0 LogInfo(U8 *fmt, ...)
{
  LogDispatch(LOG_INFO, NULL, 0, fmt, argc, argv);
}

public U0 LogDebug(U8 *fmt, ...)
{
  LogDispatch(LOG_DEBUG, NULL, 0, fmt, argc, argv);
}

public U0 LogTrace(U8 *fmt, ...)
{
  LogDispatch(LOG_TRACE, NULL, 0, fmt, argc, argv);
}

#endif
