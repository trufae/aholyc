#ifndef AHOLYC_LIB_IO_ENV_HC
#define AHOLYC_LIB_IO_ENV_HC

// Small, owned-string environment API.  EnvGet and EnvHome return MAlloc'd
// strings that callers must Free, so their values are safe to retain.

#ifdef IS_WINDOWS
extern U32 GetEnvironmentVariableA(U8 *name, U8 *value, U32 size);

U8 *EnvGet(U8 *name)
{
  U8 *value;
  U32 size = 256, length;

  if (!name || !name[0])
    return NULL;
  while (size <= 32768) {
    value = MAlloc(size);
    length = GetEnvironmentVariableA(name, value, size);
    if (length && length < size)
      return value;
    Free(value);
    if (!length)
      return NULL;
    size = length + 1;
  }
  return NULL;
}
#else
extern U8 *getenv(U8 *name);

U8 *EnvGet(U8 *name)
{
  U8 *value;

  if (!name || !name[0])
    return NULL;
  value = getenv(name);
  if (!value || !value[0])
    return NULL;
  return StrNew(value);
}
#endif

// The user's home directory, independent of the native backend.  Windows
// exposes it through USERPROFILE; POSIX shells use HOME.
U8 *EnvHome()
{
  U8 *home;

#ifdef IS_WINDOWS
  home = EnvGet("USERPROFILE");
  if (!home)
    home = EnvGet("HOME");
#else
  home = EnvGet("HOME");
#endif
  return home;
}

#endif
