# lib/log

Portable logging for aholyc's native backends, modelled on radare2's
`r_log`: one call site, several sinks.  A message carries a level and
optionally a source location, is formatted once, and reaches every enabled
target — stderr (colored on a terminal), an append-only file, the
platform's system log, and an application callback.  Timestamps and
`[file:line]` prefixes are opt-in, like `R2_LOG_TS` and `R2_LOG_SRCLINE`.

## Levels

The common root of syslog, os_log, the Windows Event Log, GLib and r_log:

| lib/log        | syslog  | os_log  | Event Log   | GLib (`G_LOG_LEVEL_*`) |
|----------------|---------|---------|-------------|------------------------|
| `LOG_FATAL`    | ALERT   | FAULT   | ERROR       | ERROR (aborts)         |
| `LOG_CRITICAL` | CRIT    | FAULT   | ERROR       | CRITICAL               |
| `LOG_ERROR`    | ERR     | ERROR   | ERROR       | CRITICAL               |
| `LOG_WARN`     | WARNING | DEFAULT | WARNING     | WARNING                |
| `LOG_INFO`     | INFO    | INFO    | INFORMATION | INFO                   |
| `LOG_DEBUG`    | DEBUG   | DEBUG   | INFORMATION | DEBUG                  |
| `LOG_TRACE`    | DEBUG   | DEBUG   | INFORMATION | DEBUG                  |

Lower is more severe.  `LogSetLevel(level)` is the threshold (default
`LOG_INFO`); a message is emitted when its level is less than or equal to
it.  `LOG_FATAL` is written to every target and then the process exits with
status 1.

## Targets

`LogSetTarget(mask)` takes any combination of `LOG_TARGET_STDERR` (the
default), `LOG_TARGET_FILE` (see `LogSetFile`) and `LOG_TARGET_SYSTEM`; a
callback installed with `LogSetCallback` always runs first and can claim the
message by returning `TRUE`, which skips the other targets.

## Backends

The system target is one of these, chosen at compile time with a `-D`
flag; the host default is oslog on macOS, the Event Log on Windows and
syslog everywhere else.

| flag            | file          | writes to                                     |
|-----------------|---------------|-----------------------------------------------|
| `-DLOG_SYSLOG`  | `syslog.hc`   | `syslog(3)`, ident = the `LogInit` name        |
| `-DLOG_OSLOG`   | `oslog.hc`    | unified log via `_os_log_impl`, subsystem = name |
| `-DLOG_EVENTLOG`| `eventlog.hc` | `ReportEventA` under source = name, plus `OutputDebugStringA` |
| `-DLOG_GLIB`    | `glib.hc`     | `g_log` with domain = name (`@pkgconfig=glib-2.0`) |
| `-DLOG_NONE`    | `none.hc`     | nothing; keeps stderr/file/callback only      |

`-DLOG_GLIB` is what a GNOME application wants: messages go through GLib's
handlers, its journald writer and `G_MESSAGES_DEBUG` filtering under the
application's own domain, and it builds on any platform with GLib.

The OS layer (stderr, terminal detection, timestamps, files, environment)
is `posix.hc` on Linux/macOS/BSD and `windows.hc` on Windows; define
`LOG_POSIX` or `LOG_WINDOWS` to override the host default.

## API

```holyc
#include "lib/log/log.hc"

// Emitting
U0   LogFatal(U8 *fmt, ...);   LogCritical  LogError  LogWarn
U0   LogInfo(U8 *fmt, ...);    LogDebug     LogTrace
U0   LogMsg(I64 level, U8 *fmt, ...);
U0   LogAt(I64 level, U8 *file, I64 line, U8 *fmt, ...);
Bool LogEnabled(I64 level);          // cheap check before formatting

// Configuration (all optional; the first message auto-initializes)
U0   LogInit(U8 *name=NULL);         // tag for the system log; reads HC_LOG_*
U0   LogFini();
U0   LogSetLevel(I64 level);         I64 LogLevel();
U0   LogSetTarget(I64 mask);         I64 LogTarget();
Bool LogSetFile(U8 *path);           // enables LOG_TARGET_FILE; NULL closes
U0   LogSetRotate(I64 max_bytes, I64 keep=5); // in-process size rotation
U0   LogSetReopen(Bool on=TRUE);     // follow external logrotate (1/s)
Bool LogReopen();                    // reopen the file path now
U0   LogSetCallback(U0 *fn, U0 *data=NULL);
     // fn: Bool (*)(I64 level, U8 *file, I64 line, U8 *msg, U0 *data)
U0   LogSetSource(Bool on=TRUE);     // prefix [file:line] when known
U0   LogSetTimestamp(Bool on=TRUE);  // prefix "YYYY-MM-DD HH:MM:SS.mmm"
U0   LogSetColor(Bool on=TRUE);      // default: stderr is a terminal
U0   LogSetPrivacy(Bool on=TRUE);    // redact %s unless %{public}s
U8  *LogLevelName(I64 level);        // "ERROR", ...
I64  LogLevelParse(U8 *name);        // "warn", "3", ... or -1
```

HolyC has no function-like macros, so the source location cannot be
captured behind `LogError(...)` the way `R_LOG_ERROR` does it.  `LogAt`
takes it explicitly and `LOG_HERE` expands to `__FILE__, __LINE__`:

```holyc
LogAt(LOG_ERROR, LOG_HERE, "cannot open %s", path);
// ERROR: [main.hc:12] cannot open /etc/nothing   (with LogSetSource)
```

## Files, rotation and thread safety

The file target is opened append-only (`O_APPEND` / `FILE_APPEND_DATA`,
shared with delete on Windows) and every line is written with a single
`write`/`WriteFile`, which the kernel appends atomically — lines never
interleave, even with other processes writing the same file, and a
`logrotate copytruncate` is followed cleanly.

All sinks are written under one internal spinlock built on the prelude's
atomic `LBts`/`LBtr` (no dependency on lib/thread); messages are formatted
outside it and the callback runs outside it, so a callback may log.  The
level/target/flag setters are plain word stores.

Rotation is optional and comes in two flavours:

```holyc
LogSetRotate(10 * 1024 * 1024, 5);  // this process rotates: file -> file.1 .. file.5
LogSetReopen(TRUE);                 // follow an external logrotate: the path is
                                    // reopened at most once a second before a write
LogReopen;                          // or reopen right now, e.g. from a SIGHUP handler
```

`LogSetRotate` renames under the lock (`rename(2)` / `MoveFileEx` are
atomic), so no line is lost in-process; it is per process by design —
several processes sharing one file should use an external logrotate with
`copytruncate`, or `create` plus `LogSetReopen`/`LogReopen`.  Env:
`HC_LOG_ROTATE=10M,5`, `HC_LOG_REOPEN=1`.

`tests/`-style check used while developing: 8 threads × 2000 lines with
64 KB rotation produce exactly 16000 intact lines across 13 files.

## Privacy

`LogSetPrivacy(TRUE)` (or `HC_LOG_PRIVACY=1`) redacts every `%s` argument
to `<private>` in every target, the way Apple's os_log hides dynamic
strings by default; scalars stay visible.  Specifiers can opt in or out with
os_log's annotations, which are always accepted and stripped:

```holyc
LogSetPrivacy(TRUE);
LogInfo("user %{public}s from %s pin %{private}04d", name, ip, pin);
// INFO: user alice from <private> pin <private>
```

`%{public}s` is shown even in privacy mode; `%{private}…` (any conversion)
is redacted even when privacy is off.  Redaction happens before formatting,
so the hidden values never reach a file, syslog, os_log or a callback.

## Environment

`LogInit` (or the first message) reads: `HC_LOG_LEVEL` (a name or number),
`HC_LOG_TARGET` (comma-separated `stderr`, `file`, `system`, `all`, or
`none`), `HC_LOG_FILE`, `HC_LOG_SOURCE`, `HC_LOG_TS`, `HC_LOG_COLOR`,
`HC_LOG_PRIVACY`, `HC_LOG_REOPEN` (`0`/`1`), `HC_LOG_ROTATE` (`10M,5`).  Environment values override what the program set before
`LogInit`.

## Example

```holyc
#include "lib/log/log.hc"

U0 Main()
{
  LogInit("myapp");
  LogInfo("starting, level %s", LogLevelName(LogLevel));
  LogWarn("disk %d%% full", 91);
  LogAt(LOG_ERROR, LOG_HERE, "cannot open %s", "/etc/nothing");
  LogFini;
}
Main;
```

See `examples/log.hc` for targets, file output, timestamps and a callback.
The JS backend is not supported (no libc).
