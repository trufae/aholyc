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

# Directories

`lib/io/dir.hc` lists directories straight from the kernel's own records
(`getdents64` on Linux, `getdirentries64` on Darwin, `FindFirstFile` on
Windows) into caller-owned storage. Listing never allocates, copies a name,
or builds a path: entries are borrowed views that stay valid until the
`DirRead` that refills the scratch, `DirRewind`, or `DirClose`.

```holyc
#include "lib/io/dir.hc"

CDirBuf dir;                       // CDir plus a DIR_BUFFER_SIZE scratch
CDirEntry entry;
if (DirOpen(&dir, "assets")) {
  while (DirRead(&dir, &entry) > 0)
    "%s%s\n", entry.name, entry.type == DIR_TYPE_DIR ? "/" : "";
  DirClose(&dir);
}

DirCreate("out/cache/images", TRUE); // mkdir -p
DirRemove("out/cache", TRUE);        // rm -rf
```

| Function | Purpose |
| --- | --- |
| `DirOpenBuf(&dir, path, scratch, size)` | Open for listing into any buffer of at least `DIR_SCRATCH_MIN` bytes; 0 or a negative error. |
| `DirOpen(&dir, path)` | The same through the buffer inside a `CDirBuf`; TRUE on success, the error stays in `dir.error`. |
| `DirRead(&dir, &entry)` | Next entry other than `.` and `..`: 1, 0 at the end, or a negative error. `entry` carries `name`, `name_length`, `type` (`DIR_TYPE_*`, the POSIX `d_type` values) and `inode`. |
| `DirNext(&dir)` | The next name or NULL; `dir.error` tells the end from a failure. |
| `DirRewind(&dir)`, `DirClose(&dir)` | Restart or release the handle; close is idempotent and still reports a failure. |
| `DirIsDir(path)`, `DirExists(path)` | TRUE for a directory the caller can open, following links. |
| `DirForEach(path, callback, user=NULL)` | Calls `callback(path, &entry, user)` per entry: 1 after the last one, 0 once the callback returns FALSE, negative on error. |
| `DirCreateEx(path, recursive=FALSE)`, `DirCreate` | `mkdir`, or with `recursive` `mkdir -p`, which accepts existing directories and creates each component relative to its parent's descriptor. |
| `DirRemoveEx(path, force=FALSE)`, `DirRemove` | `rmdir`, or with `force` `rm -rf`. |

Errors are native negative codes (`-errno`, `-GetLastError()` on Windows).
`DIR_ERROR_NOT_FOUND`, `DIR_ERROR_EXISTS`, `DIR_ERROR_NOT_DIR`,
`DIR_ERROR_NOT_EMPTY`, `DIR_ERROR_INVALID`, `DIR_ERROR_CLOSED` and
`DIR_ERROR_RECORD` name the ones callers branch on; the `Ex` forms return
them and the Bool wrappers only report success.

Removal never follows links. POSIX traversal opens each subdirectory with
`O_NOFOLLOW` relative to its parent's descriptor and unlinks symbolic links
as leaves; a link given as the root is refused with `DIR_ERROR_NOT_DIR`.
Windows deletes reparse points (junctions and symbolic links) without
entering them. One `DIR_BUFFER_SIZE` scratch serves the whole POSIX walk and
each level holds only a descriptor; Windows keeps one find state per level
and a single `DIR_PATH_CAPACITY` path workspace.

Backends: Linux (x86-64, arm64, riscv64) and Darwin call the kernel through
`lib/syscall` when assembly is enabled and through libc's thin stubs under
`-fno-asm` or when `DIR_LIBC` is defined; Windows uses the Win32 ANSI APIs.
`DIR_WINDOWS` and `DIR_POSIX` override the compiler host for cross builds.
The BSDs are rejected at compile time until their record layouts get
adapters (`doc/rfc/dir.md`).

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
