// Win32 OS layer: stderr through the console/file handle, terminal
// detection (and ANSI color enablement) through GetConsoleMode, local time
// from GetLocalTime, append-only files through CreateFileA.  int-returning
// Win32 functions are narrowed with (I32) like everywhere else in lib/.
//
// Files are opened for FILE_APPEND_DATA with full sharing (including
// delete, so external tools can rotate them) and every line is one
// WriteFile, which appends atomically like O_APPEND does on POSIX.

extern U8 *GetStdHandle(I64 which);
extern I64 GetConsoleMode(U8 *handle, U32 *mode);
extern I64 SetConsoleMode(U8 *handle, U32 mode);
extern I64 WriteFile(U8 *handle, U8 *data, U32 count, U32 *written,
  U8 *overlapped);
extern U8 *CreateFileA(U8 *path, U32 access, U32 share, U8 *security,
  U32 disposition, U32 flags, U8 *template);
extern I64 CloseHandle(U8 *handle);
extern I64 GetFileSizeEx(U8 *handle, I64 *size);
extern I64 MoveFileExA(U8 *from, U8 *to, U32 flags);
extern I64 DeleteFileA(U8 *path);
extern I64 GetTickCount64();
extern I64 SwitchToThread();
extern U0 GetLocalTime(U8 *systemtime);
extern U8 *getenv(U8 *name);

#define LOG_WIN_STDERR          -12
#define LOG_WIN_VT              0x4
#define LOG_WIN_APPEND_DATA     0x4
#define LOG_WIN_SHARE_ALL       0x7
#define LOG_WIN_OPEN_ALWAYS     4
#define LOG_WIN_ATTR_NORMAL     0x80
#define LOG_WIN_INVALID_HANDLE  -1
#define LOG_WIN_REPLACE_EXISTING 0x1

U0 LogOsWrite(U8 *text, I64 len)
{
  U32 written = 0;
  U8 *handle = GetStdHandle(LOG_WIN_STDERR);

  if (handle && handle != LOG_WIN_INVALID_HANDLE(U8 *))
    WriteFile(handle, text, len, &written, NULL);
}

// True for a console; also turns on virtual terminal processing so the
// SGR color sequences render on Windows 10+.
Bool LogOsIsTty()
{
  U32 mode = 0;
  U8 *handle = GetStdHandle(LOG_WIN_STDERR);

  if (!handle || handle == LOG_WIN_INVALID_HANDLE(U8 *))
    return FALSE;
  if (!GetConsoleMode(handle, &mode)(I32))
    return FALSE;
  return SetConsoleMode(handle, mode | LOG_WIN_VT)(I32) != 0;
}

U8 *LogOsGetEnv(U8 *name)
{
  return getenv(name);
}

I64 LogOsMs()
{
  return GetTickCount64;
}

U0 LogOsYield()
{
  SwitchToThread;
}

// "YYYY-MM-DD HH:MM:SS.mmm" from SYSTEMTIME (eight U16 fields).
U0 LogOsTimestamp(U8 *buf)
{
  U16 st[8];

  GetLocalTime(st);
  StrPrint(buf, "%04d-%02d-%02d %02d:%02d:%02d.%03d", st[0], st[1], st[3],
    st[4], st[5], st[6], st[7]);
}

U8 *LogOsFileOpen(U8 *path)
{
  U8 *handle = CreateFileA(path, LOG_WIN_APPEND_DATA, LOG_WIN_SHARE_ALL, NULL,
    LOG_WIN_OPEN_ALWAYS, LOG_WIN_ATTR_NORMAL, NULL);

  if (handle == LOG_WIN_INVALID_HANDLE(U8 *))
    return NULL;
  return handle;
}

I64 LogOsFileSize(U8 *handle)
{
  I64 size = 0;

  if (!GetFileSizeEx(handle, &size)(I32))
    return 0;
  return size;
}

U0 LogOsFileWrite(U8 *handle, U8 *text, I64 len)
{
  U32 written = 0;

  WriteFile(handle, text, len, &written, NULL);
}

U0 LogOsFileClose(U8 *handle)
{
  CloseHandle(handle);
}

Bool LogOsFileRename(U8 *from, U8 *to)
{
  return MoveFileExA(from, to, LOG_WIN_REPLACE_EXISTING)(I32) != 0;
}

U0 LogOsFileDelete(U8 *path)
{
  DeleteFileA(path);
}
