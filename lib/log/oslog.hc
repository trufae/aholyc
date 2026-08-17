// os_log (unified logging) system backend for macOS.
//
// os_log_with_type is a compiler macro in C, so this calls the function it
// expands to, _os_log_impl, with a hand-built argument buffer for the
// format "%{public}s".  The dso handle identifies the sending image; the
// main executable's mach header is what __dso_handle would be, and dladdr
// on one of our own functions yields it.  Messages are public so they show
// up unredacted in Console.app / `log stream`.
//
// Levels map to os_log types: FATAL and CRITICAL -> FAULT, ERROR -> ERROR,
// WARN -> DEFAULT, INFO -> INFO, DEBUG and TRACE -> DEBUG.
// @ldflags=-ldl

extern U8 *os_log_create(U8 *subsystem, U8 *category);
extern U0 _os_log_impl(U8 *dso, U8 *log, I64 type, U8 *format, U8 *buf,
  U32 size);
extern I64 dladdr(U8 *address, U8 *info);
extern U0 os_release(U8 *object);

#define LOG_OS_TYPE_DEFAULT 0
#define LOG_OS_TYPE_INFO    1
#define LOG_OS_TYPE_DEBUG   2
#define LOG_OS_TYPE_ERROR   16
#define LOG_OS_TYPE_FAULT   17

I64 log_oslog_type[LOG_LEVELS] = { 17, 17, 16, 0, 1, 2, 2 };
U8 *log_oslog_handle;
U8 *log_oslog_dso;

Bool LogNativeOpen(U8 *name)
{
  U8 *info[4];

  // Dl_info: dli_fname, dli_fbase, dli_sname, dli_saddr.
  MemSet(info, 0, 32);
  if (dladdr(&LogNativeOpen, info)(I32))
    log_oslog_dso = info[1];
  log_oslog_handle = os_log_create(name, "default");
  return log_oslog_handle != NULL;
}

U0 LogNativeWrite(I64 level, U8 *msg)
{
  U8 buf[12];
  U8 **slot = buf + 4;

  // Summary byte: 0x02 = has non-scalar items; then the argument count.
  // Each argument is a descriptor byte (0x22 = public string), a size byte,
  // and the payload — here the 8-byte pointer to the NUL-terminated text.
  buf[0] = 0x02;
  buf[1] = 1;
  buf[2] = 0x22;
  buf[3] = 8;
  *slot = msg;
  _os_log_impl(log_oslog_dso, log_oslog_handle, log_oslog_type[level],
    "%{public}s", buf, 12);
}

U0 LogNativeClose()
{
  if (log_oslog_handle)
    os_release(log_oslog_handle);
  log_oslog_handle = NULL;
}
