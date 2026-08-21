#ifndef AHOLYC_LIB_IO_ENV_HC
#define AHOLYC_LIB_IO_ENV_HC

// Small environment API. EnvGet and EnvHome return MAlloc'd strings that
// callers must Free, so their values are safe to retain.

#ifdef IS_WINDOWS
extern U32 GetEnvironmentVariableA(U8 *name, U8 *value, U32 size);
extern Bool SetEnvironmentVariableA(U8 *name, U8 *value);

// Set name to value. Omitting value, or passing NULL, removes name.
Bool SetEnv(U8 *name, U8 *value = NULL)
{
  if (!name || !name[0])
    return FALSE;
  return SetEnvironmentVariableA(name, value);
}

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
extern I64 setenv(U8 *name, U8 *value, I64 overwrite);
extern I64 unsetenv(U8 *name);

// Set name to value. Omitting value, or passing NULL, removes name.
Bool SetEnv(U8 *name, U8 *value = NULL)
{
  if (!name || !name[0])
    return FALSE;
  if (!value)
    return unsetenv(name) == 0;
  return setenv(name, value, TRUE) == 0;
}

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
