#ifndef AHOLYC_LIB_IO_REPLACE_HC
#define AHOLYC_LIB_IO_REPLACE_HC

#include "file.hc"
#include "../text/strs.hc"

extern I32 rename(U8 *from, U8 *to);
extern I32 remove(U8 *path);
#ifdef IS_WINDOWS
extern I32 MoveFileExA(U8 *from, U8 *to, U32 flags);
#endif

#ifdef IS_WINDOWS
extern U32 GetFullPathNameA(U8 *path, U32 length, U8 *out, U8 **part);
#else
extern U8 *realpath(U8 *path, U8 *out);
#endif

Bool FileSamePath(U8 *a, U8 *b)
{
  U8 left[4096], right[4096];

  if (!a || !b || !*a || !*b) return FALSE;
  if (!StrCmp(a, b)) return TRUE;
  #ifdef IS_WINDOWS
  I64 n = GetFullPathNameA(a, sizeof(left), left, NULL);
  I64 m = GetFullPathNameA(b, sizeof(right), right, NULL);
  if (!n || !m || n >= sizeof(left) || m >= sizeof(right)) return FALSE;
  I64 i;
  for (i = 0; left[i]; i++) if (left[i] >= 'A' && left[i] <= 'Z') left[i] += 32;
  for (i = 0; right[i]; i++) if (right[i] >= 'A' && right[i] <= 'Z') right[i] += 32;
  #else
  if (!realpath(a, left) || !realpath(b, right)) return FALSE;
  #endif
  return !StrCmp(left, right);
}

// Write beside the destination, then replace it. A failed write never truncates
// the original. Exclusive creation protects other writers' temporary files.
Bool FileReplace(U8 *path, CStrs *text)
{
  U8 *temporary = NULL, *stream = NULL;
  I64 i;
  Bool ok;

  if (!path || !StrsValid(text)) return FALSE;
  for (i = 0; i < 100 && !stream; i++) {
    Free(temporary);
    temporary = MStrPrint("%s.aholyc-%X.tmp", path, RandI64);
    stream = fopen(temporary, "wbx");
  }
  if (!stream) { Free(temporary); return FALSE; }
  ok = fwrite(text->a, 1, StrsLen(text), stream) == StrsLen(text);
  if (fclose(stream)(I32)) ok = FALSE;
  if (ok) {
    #ifdef IS_WINDOWS
    ok = MoveFileExA(temporary, path, 1)(I32) != 0;
    #else
    ok = !rename(temporary, path)(I32);
    #endif
  }
  if (!ok) remove(temporary);
  Free(temporary);
  return ok;
}

#endif
