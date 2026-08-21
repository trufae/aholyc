# File I/O

`lib/io/file.hc` offers whole-file helpers on top of the C runtime's stdio,
so the same code runs on Linux, macOS and Windows:

```holyc
#include "lib/io/file.hc"

I64 size;
U8 *data = FileRead("input.bin", &size);   // heap buffer, NUL-terminated
if (data && FileWrite("copy.bin", data, size))
  "copied %d bytes\n", size;
Free(data);
if (FileExists("copy.bin"))
  "ok\n";
```

`FileWrite(path, text)` without a size writes a C string. Higher-level
libraries such as `lib/llm` and `lib/mcp` deliberately take bytes rather than paths; combine
them with these helpers.

## Child processes

`lib/io/process.hc` starts a command with piped stdin/stdout on
`posix_spawn` (Linux, macOS) or `CreateProcess` (Windows). The command line
runs through `/bin/sh -c` or `cmd.exe /C`, stderr is inherited, and reads and
writes are blocking with explicit byte lengths:

```holyc
#include "lib/io/process.hc"

CProcess process;
U8 buffer[256];
I64 size;

if (ProcessOpen(&process, "tr a-z A-Z")) {
  ProcessWrite(&process, "hello\n", 6);
  ProcessCloseInput(&process);                 // EOF for the child
  size = ProcessRead(&process, buffer, sizeof(buffer));
  "%d: exit=%d\n", size, ProcessClose(&process);
}
```

| Function | Purpose |
| --- | --- |
| `ProcessOpen(&p, command)` | Start the command; FALSE when the shell cannot be spawned. |
| `ProcessWrite(&p, data, size)` | Write all bytes to the child's stdin. |
| `ProcessRead(&p, buffer, capacity)` | Blocking read from its stdout: bytes, 0 at EOF, -1 on error. |
| `ProcessCloseInput(&p)` | Close stdin only, so the child sees EOF while its output is still read. |
| `ProcessClose(&p, timeout_ms=2000)` | Close both pipes, wait for exit, then SIGTERM the child's process group and finally SIGKILL it. Returns the exit code (-1 when terminated), also kept in `p.exit_code`. |

On POSIX the child leads its own process group so the shutdown sequence
reaches the programs the shell started; `ProcessOpen` also ignores `SIGPIPE`
so writing to a dead child fails instead of killing the caller. On Windows
the shutdown terminates the shell only.
# `lib/io`

`env.hc` provides owned environment strings across POSIX and Windows:

```c
#include "lib/io/env.hc"

U8 *home = EnvHome;  // MAlloc'd HOME / USERPROFILE value; Free when done
U8 *value = EnvGet("MY_SETTING");
SetEnv("MY_SETTING", "enabled");
SetEnv("MY_SETTING"); // value defaults to NULL, which unsets it
```

`EnvHome` uses `HOME` on POSIX and `GetEnvironmentVariableA("USERPROFILE")`
on Windows. `EnvGet` and `EnvHome` return `NULL` when unavailable.
`SetEnv` returns `TRUE` on success; a `NULL` value removes the variable.
