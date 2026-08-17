// Null system backend: LOG_TARGET_SYSTEM is accepted and discarded.  Useful
// for platforms without a system log or to keep a build free of libc log
// dependencies while still using the stderr, file and callback targets.

Bool LogNativeOpen(U8 *name)
{
  return TRUE;
}

U0 LogNativeWrite(I64 level, U8 *msg)
{
}

U0 LogNativeClose()
{
}
