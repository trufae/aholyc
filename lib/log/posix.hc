// OS layer shared by Linux, macOS and the BSDs: stderr, terminal detection,
// wall-clock timestamps, append-only files and the environment.
//
// int-returning libc functions are narrowed with (I32): aholyc widens
// extern returns to I64 and the upper register half is undefined.
// Files go through stdio so open flags need no per-OS values.

extern I64 write(I64 fd, U8 *buffer, I64 count);
extern I64 isatty(I64 fd);
extern U8 *getenv(U8 *name);
extern I64 clock_gettime(I64 clock, U8 *timespec);
extern U8 *localtime_r(U8 *time, U8 *tm);
extern I64 strftime(U8 *buf, I64 max, U8 *fmt, U8 *tm);
extern U8 *fopen(U8 *path, U8 *mode);
extern I64 fwrite(U8 *data, I64 size, I64 count, U8 *stream);
extern I64 fflush(U8 *stream);
extern I64 fclose(U8 *stream);

#define LOG_CLOCK_REALTIME 0

U0 LogOsWrite(U8 *text, I64 len)
{
  I64 done = 0, n;

  while (done < len) {
    n = write(2, text + done, len - done);
    if (n <= 0)
      break;
    done += n;
  }
}

Bool LogOsIsTty()
{
  return isatty(2)(I32) != 0;
}

U8 *LogOsGetEnv(U8 *name)
{
  return getenv(name);
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

U8 *LogOsFileOpen(U8 *path)
{
  return fopen(path, "a");
}

U0 LogOsFileWrite(U8 *handle, U8 *text, I64 len)
{
  fwrite(text, 1, len, handle);
  fflush(handle);
}

U0 LogOsFileClose(U8 *handle)
{
  fclose(handle);
}
