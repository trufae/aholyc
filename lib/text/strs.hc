#ifndef AHOLYC_LIB_TEXT_STRS_HC
#define AHOLYC_LIB_TEXT_STRS_HC

// Borrowed byte slice. The half-open [a, b) representation makes length,
// consumption, and subslicing allocation-free. Bytes need not end in NUL and
// may contain NUL. The owner of the underlying storage must outlive the slice.

class CStrs
{
  U8 *a;
  U8 *b;
};

/* @inline */ Bool StrsValid(CStrs *slice)
{
  return slice && (!slice->a && !slice->b || slice->a && slice->b >= slice->a);
}

/* @inline */ Bool StrsInit(CStrs *slice, U8 *a, U8 *b)
{
  if (!slice)
    return FALSE;
  if (a && b >= a || !a && !b) {
    slice->a = a;
    slice->b = b;
    return TRUE;
  }
  slice->a = NULL;
  slice->b = NULL;
  return FALSE;
}

/* @inline */ Bool StrsInitN(CStrs *slice, U8 *data, I64 length)
{
  if (!slice)
    return FALSE;
  if (length < 0 || !data && length) {
    slice->a = NULL;
    slice->b = NULL;
    return FALSE;
  }
  slice->a = data;
  slice->b = data + length;
  return TRUE;
}

// Convenience adapter for a NUL-terminated string. Prefer StrsInitN on hot
// paths and whenever the byte count is already known.
/* @inline */ Bool StrsInitS(CStrs *slice, U8 *string)
{
  return StrsInitN(slice, string, StrLen(string));
}

/* @inline */ I64 StrsLen(CStrs *slice)
{
  if (!slice || !slice->a || slice->b <= slice->a)
    return 0;
  return slice->b - slice->a;
}

/* @inline */ Bool StrsEmpty(CStrs *slice)
{
  return !slice || !slice->a || slice->b <= slice->a;
}

/* @inline */ I64 StrsAt(CStrs *slice, I64 index)
{
  if (index < 0 || index >= StrsLen(slice))
    return 0;
  return slice->a[index];
}

/* @inline */ I64 StrsLast(CStrs *slice)
{
  if (StrsEmpty(slice))
    return 0;
  return slice->b[-1];
}

// Bounds are clamped, so requesting beyond either edge is cheap and safe.
/* @inline */ Bool StrsSub(CStrs *slice, I64 from, I64 to, CStrs *result)
{
  U8 *a;
  I64 length;

  if (!StrsValid(slice) || !result)
    return FALSE;
  a = slice->a;
  length = StrsLen(slice);
  if (from < 0)
    from = 0;
  if (to < 0)
    to = 0;
  if (from > length)
    from = length;
  if (to > length)
    to = length;
  if (to < from)
    to = from;
  if (!a) {
    result->a = NULL;
    result->b = NULL;
  } else {
    result->a = a + from;
    result->b = a + to;
  }
  return TRUE;
}

/* @inline */ Bool StrsAdvance(CStrs *slice, I64 amount)
{
  if (!StrsValid(slice) || amount < 0)
    return FALSE;
  if (amount > StrsLen(slice)) {
    slice->a = slice->b;
    return FALSE;
  }
  slice->a += amount;
  return TRUE;
}

/* @inline */ Bool StrsEquals(CStrs *a, CStrs *b)
{
  I64 length = StrsLen(a);

  return length == StrsLen(b) && (!length || !MemCmp(a->a, b->a, length));
}

/* @inline */ Bool StrsStartsWith(CStrs *slice, CStrs *prefix)
{
  I64 length = StrsLen(prefix);

  return length <= StrsLen(slice) &&
    (!length || !MemCmp(slice->a, prefix->a, length));
}

/* @inline */ Bool StrsEndsWith(CStrs *slice, CStrs *suffix)
{
  I64 length = StrsLen(suffix);
  I64 slice_length = StrsLen(slice);

  return length <= slice_length &&
    (!length || !MemCmp(slice->b - length, suffix->a, length));
}

/* @inline */ Bool StrsEqualsS(CStrs *slice, U8 *string)
{
  CStrs other;

  StrsInitS(&other, string);
  return StrsEquals(slice, &other);
}

/* @inline */ Bool StrsStartsWithS(CStrs *slice, U8 *prefix)
{
  CStrs other;

  StrsInitS(&other, prefix);
  return StrsStartsWith(slice, &other);
}

/* @inline */ Bool StrsEndsWithS(CStrs *slice, U8 *suffix)
{
  CStrs other;

  StrsInitS(&other, suffix);
  return StrsEndsWith(slice, &other);
}

U8 *StrsFind(CStrs *slice, CStrs *needle)
{
  I64 length;

  if (!StrsValid(slice) || !StrsValid(needle))
    return NULL;
  length = StrsLen(needle);
  if (!length)
    return slice->a;
  return MemMem(slice->a, StrsLen(slice), needle->a, length);
}

/* @inline */ U8 *StrsFindC(CStrs *slice, I64 character)
{
  if (!StrsValid(slice))
    return NULL;
  return MemChr(slice->a, character, StrsLen(slice));
}

U8 *StrsFindAny(CStrs *slice, CStrs *set)
{
  U8 *p;
  U8 *q;

  if (!StrsValid(slice) || !StrsValid(set) || StrsEmpty(set))
    return NULL;
  if (StrsLen(set) == 1)
    return MemChr(slice->a, set->a[0], StrsLen(slice));
  for (p = slice->a; p < slice->b; p++) {
    for (q = set->a; q < set->b; q++) {
      if (*p == *q)
        return p;
    }
  }
  return NULL;
}

U8 *StrsFindAnyS(CStrs *slice, U8 *set)
{
  CStrs characters;

  StrsInitS(&characters, set);
  return StrsFindAny(slice, &characters);
}

/* @inline */ Bool StrsHasC(CStrs *set, I64 character)
{
  U8 *p;

  if (!StrsValid(set))
    return FALSE;
  for (p = set->a; p < set->b; p++) {
    if (*p == character)
      return TRUE;
  }
  return FALSE;
}

U0 StrsSkipChars(CStrs *slice, CStrs *set)
{
  if (!StrsValid(slice) || !StrsValid(set))
    return;
  while (slice->a < slice->b && StrsHasC(set, *slice->a))
    slice->a++;
}

U0 StrsTrimChars(CStrs *slice, CStrs *set)
{
  if (!StrsValid(slice) || !StrsValid(set))
    return;
  while (slice->a < slice->b && StrsHasC(set, *slice->a))
    slice->a++;
  while (slice->b > slice->a && StrsHasC(set, slice->b[-1]))
    slice->b--;
}

/* @inline */ Bool StrsIsSpace(I64 character)
{
  return character == ' ' || character >= '\t' && character <= '\r';
}

U0 StrsTrim(CStrs *slice)
{
  if (!StrsValid(slice))
    return;
  while (slice->a < slice->b && StrsIsSpace(*slice->a))
    slice->a++;
  while (slice->b > slice->a && StrsIsSpace(slice->b[-1]))
    slice->b--;
}

/* @inline */ Bool StrsIsIdent(I64 character)
{
  return character >= 'a' && character <= 'z' ||
    character >= 'A' && character <= 'Z' ||
    character >= '0' && character <= '9' || character == '_';
}

Bool StrsTakeIdent(CStrs *slice, CStrs *result)
{
  if (!StrsValid(slice) || !result || result == slice)
    return FALSE;
  result->a = slice->a;
  while (slice->a < slice->b && StrsIsIdent(*slice->a))
    slice->a++;
  result->b = slice->a;
  return !StrsEmpty(result);
}

Bool StrsNextToken(CStrs *slice, CStrs *separators, CStrs *result)
{
  if (!StrsValid(slice) || !StrsValid(separators) || !result ||
    result == slice)
    return FALSE;
  StrsSkipChars(slice, separators);
  if (StrsEmpty(slice)) {
    result->a = slice->b;
    result->b = slice->b;
    return FALSE;
  }
  result->a = slice->a;
  while (slice->a < slice->b && !StrsHasC(separators, *slice->a))
    slice->a++;
  result->b = slice->a;
  return TRUE;
}

Bool StrsSplitC(CStrs *slice, I64 separator, CStrs *head, CStrs *tail)
{
  U8 *position;
  U8 *end;

  if (!StrsValid(slice) || !head || !tail || head == tail)
    return FALSE;
  end = slice->b;
  position = StrsFindC(slice, separator);
  head->a = slice->a;
  if (!position) {
    head->b = end;
    tail->a = end;
    tail->b = end;
    return FALSE;
  }
  head->b = position;
  tail->a = position + 1;
  tail->b = end;
  return TRUE;
}

Bool StrsSplitAny(CStrs *slice, CStrs *separators, CStrs *head, CStrs *tail)
{
  U8 *position;
  U8 *end;

  if (!StrsValid(slice) || !StrsValid(separators) || !head || !tail ||
    head == tail)
    return FALSE;
  end = slice->b;
  position = StrsFindAny(slice, separators);
  head->a = slice->a;
  if (!position) {
    head->b = end;
    tail->a = end;
    tail->b = end;
    return FALSE;
  }
  head->b = position;
  tail->a = position + 1;
  tail->b = end;
  return TRUE;
}

Bool StrsSplit(CStrs *slice, CStrs *separator, CStrs *head, CStrs *tail)
{
  U8 *position;
  U8 *end;
  I64 length;

  if (!StrsValid(slice) || !StrsValid(separator) || !head || !tail ||
    head == tail)
    return FALSE;
  end = slice->b;
  length = StrsLen(separator);
  if (length)
    position = StrsFind(slice, separator);
  else
    position = NULL;
  head->a = slice->a;
  if (!position) {
    head->b = end;
    tail->a = end;
    tail->b = end;
    return FALSE;
  }
  head->b = position;
  tail->a = position + length;
  tail->b = end;
  return TRUE;
}

U8 *StrsDup(CStrs *slice)
{
  U8 *result;
  I64 length;

  if (!StrsValid(slice))
    return NULL;
  length = StrsLen(slice);
  result = MAlloc(length + 1);
  if (length)
    MemCpy(result, slice->a, length);
  result[length] = 0;
  return result;
}

#endif
