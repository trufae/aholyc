// OS layer shared by Linux, macOS and the BSDs: stderr, terminal detection,
// wall-clock timestamps, append-only files, renames and the environment.
//
// int-returning libc functions are narrowed with (I32): aholyc widens
// extern returns to I64 and the upper register half is undefined.
//
// Files are opened O_APPEND and every line is one write(2): the kernel
// performs the seek-to-end and the write atomically, so lines from other
// threads or processes never interleave inside a line, and a truncation by
// `logrotate copytruncate` is followed cleanly.

extern I64 write(I64 fd, U8 *buffer, I64 count);
extern I64 open(U8 *path, I64 flags, I64 mode);
extern I64 close(I64 fd);
extern I64 lseek(I64 fd, I64 offset, I64 whence);
extern I64 rename(U8 *from, U8 *to);
extern I64 unlink(U8 *path);
extern I64 isatty(I64 fd);
extern I64 sched_yield();
extern U8 *getenv(U8 *name);
extern I64 clock_gettime(I64 clock, U8 *timespec);
extern U8 *localtime_r(U8 *time, U8 *tm);
extern I64 strftime(U8 *buf, I64 max, U8 *fmt, U8 *tm);

#define LOG_CLOCK_REALTIME 0
#define LOG_O_WRONLY 1
#ifdef IS_LINUX
#define LOG_O_CREAT  0x40
#define LOG_O_APPEND 0x400
#define LOG_CLOCK_MONOTONIC 1
#else
#define LOG_O_CREAT  0x200
#define LOG_O_APPEND 0x8
#ifdef IS_MACOS
#define LOG_CLOCK_MONOTONIC 6
#else
#define LOG_CLOCK_MONOTONIC 4
#endif
#endif
#define LOG_SEEK_END 2
#define LOG_MODE_644 0x1A4  // HolyC has no octal literals

// Exactly one write(2) per line, never a retry: a second write for the
// remainder could interleave with another writer, which is worse than a
// truncated line, and regular files only short-write when the disk is full.
U0 LogOsWrite(U8 *text, I64 len)
{
  write(2, text, len);
}

Bool LogOsIsTty()
{
  return isatty(2)(I32) != 0;
}

U8 *LogOsGetEnv(U8 *name)
{
  return getenv(name);
}

// Give the CPU away while waiting for the log lock.
U0 LogOsYield()
{
  sched_yield;
}

// Monotonic milliseconds, for throttling the reopen check.
I64 LogOsMs()
{
  I64 stamp[2];

  if (clock_gettime(LOG_CLOCK_MONOTONIC, stamp)(I32))
    return 0;
  return stamp[0] * 1000 + stamp[1] / 1000000;
}

// "YYYY-MM-DD HH:MM:SS.mmm"; buf holds at least 32 bytes.
U0 LogOsTimestamp(U8 *buf)
{
  I64 stamp[2];
  U8 tm[128];
  I64 ms, n;

  if (clock_gettime(LOG_CLOCK_REALTIME, stamp)(I32)) {
    StrCpy(buf, "0000-00-00 00:00:00.000");
    return;
  }
  ms = stamp[1] / 1000000;
  MemSet(tm, 0, 128);
  if (!localtime_r(stamp, tm)) {
    StrPrint(buf, "%d.%03d", stamp[0], ms);
    return;
  }
  n = strftime(buf, 24, "%Y-%m-%d %H:%M:%S", tm);
  StrPrint(buf + n, ".%03d", ms);
}

// Handles are file descriptors offset by one so that 0 means failure.
U8 *LogOsFileOpen(U8 *path)
{
  I64 fd = open(path, LOG_O_WRONLY | LOG_O_CREAT | LOG_O_APPEND, LOG_MODE_644)(I32);

  if (fd < 0)
    return NULL;
  return (fd + 1)(U8 *);
}

I64 LogOsFileSize(U8 *handle)
{
  I64 size = lseek(handle(I64) - 1, 0, LOG_SEEK_END);

  if (size < 0)
    return 0;
  return size;
}

// One write per line, no retry (see LogOsWrite).
U0 LogOsFileWrite(U8 *handle, U8 *text, I64 len)
{
  write(handle(I64) - 1, text, len);
}

U0 LogOsFileClose(U8 *handle)
{
  close(handle(I64) - 1);
}

// rename(2) is atomic and replaces an existing destination.
Bool LogOsFileRename(U8 *from, U8 *to)
{
  return rename(from, to)(I32) == 0;
}

U0 LogOsFileDelete(U8 *path)
{
  unlink(path);
}
