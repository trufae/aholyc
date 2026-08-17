#ifndef AHOLYC_LIB_TEXT_STRBUF_HC
#define AHOLYC_LIB_TEXT_STRBUF_HC

#include "strs.hc"

// Small-string optimized, binary-safe string builder. CStrBuf inherits CStrs,
// so [a, b) is always its current byte view and can be passed directly to the
// Strs APIs. *b is kept NUL for C-string interop, but b is authoritative and
// the payload may contain NUL bytes. The first 63 bytes are stored inline.

#define STRBUF_INLINE_CAPACITY 64

class CStrBuf : CStrs
{
  I64 capacity;
  U8 inline_data[STRBUF_INLINE_CAPACITY];
};

U0 StrBufInit(CStrBuf *buffer)
{
  buffer->a = buffer->inline_data;
  buffer->b = buffer->inline_data;
  buffer->capacity = STRBUF_INLINE_CAPACITY;
  buffer->inline_data[0] = 0;
}

// Reserve room for additional payload bytes and the trailing NUL. Capacity
// doubles for ordinary appends; a single large append grows exactly as much
// as needed.
Bool StrBufReserve(CStrBuf *buffer, I64 additional)
{
  U8 *data;
  I64 length;
  I64 needed;
  I64 capacity;

  if (!StrsValid(buffer) || additional < 0)
    return FALSE;
  length = StrsLen(buffer);
  if (!buffer->a || buffer->capacity <= length ||
    additional > I64_MAX - length - 1)
    return FALSE;
  needed = length + additional + 1;
  if (needed <= buffer->capacity)
    return TRUE;

  capacity = needed;
  if (buffer->capacity <= I64_MAX / 2 && buffer->capacity * 2 > capacity)
    capacity = buffer->capacity * 2;
  data = MAlloc(capacity);
  MemCpy(data, buffer->a, length + 1);
  if (buffer->a != buffer->inline_data)
    Free(buffer->a);
  buffer->a = data;
  buffer->b = data + length;
  buffer->capacity = capacity;
  return TRUE;
}

Bool StrBufPutStrs(CStrBuf *buffer, CStrs *text)
{
  U8 *source_data;
  I64 source_offset = -1;
  I64 buffer_length;
  I64 length;
  U64 source;
  U64 start;

  if (!StrsValid(buffer) || !StrsValid(text) || !buffer->a)
    return FALSE;
  length = StrsLen(text);
  if (!length)
    return TRUE;
  source_data = text->a;

  // Preserve a source slice into the buffer if reserving moves its storage.
  buffer_length = StrsLen(buffer);
  source = source_data(U64);
  start = buffer->a(U64);
  if (source >= start && source - start <= buffer_length &&
    length <= buffer_length - (source - start))
    source_offset = source - start;
  if (!StrBufReserve(buffer, length))
    return FALSE;
  if (source_offset >= 0)
    source_data = buffer->a + source_offset;
  MemCpy(buffer->b, source_data, length);
  buffer->b += length;
  *buffer->b = 0;
  return TRUE;
}

Bool StrBufPutN(CStrBuf *buffer, U8 *text, I64 length)
{
  CStrs slice;

  if (!StrsInitN(&slice, text, length))
    return FALSE;
  return StrBufPutStrs(buffer, &slice);
}

Bool StrBufPutS(CStrBuf *buffer, U8 *text)
{
  CStrs slice;

  if (!text || !StrsInitS(&slice, text))
    return FALSE;
  return StrBufPutStrs(buffer, &slice);
}

Bool StrBufPutC(CStrBuf *buffer, I64 character)
{
  if (!buffer || !StrBufReserve(buffer, 1))
    return FALSE;
  *buffer->b++ = character;
  *buffer->b = 0;
  return TRUE;
}

Bool StrBufPrintf(CStrBuf *buffer, U8 *format, ...)
{
  U8 *text;
  Bool result;

  if (!buffer || !format)
    return FALSE;
  text = StrPrintJoin(NULL, format, argc, argv);
  result = StrBufPutS(buffer, text);
  Free(text);
  return result;
}

U0 StrBufClear(CStrBuf *buffer)
{
  if (!StrsValid(buffer) || !buffer->a || buffer->capacity < 1)
    return;
  buffer->b = buffer->a;
  *buffer->b = 0;
}

U0 StrBufFini(CStrBuf *buffer)
{
  if (!buffer)
    return;
  if (buffer->a && buffer->a != buffer->inline_data)
    Free(buffer->a);
  StrBufInit(buffer);
}

/* @inline */ Bool StrBufView(CStrBuf *buffer, CStrs *view)
{
  if (!StrsValid(buffer) || !view)
    return FALSE;
  view->a = buffer->a;
  view->b = buffer->b;
  return TRUE;
}

// Transfer a heap buffer without copying. Inline data is copied to a new
// allocation so the result always belongs to the caller and can be Free'd.
U8 *StrBufTake(CStrBuf *buffer, I64 *length=NULL)
{
  U8 *data;
  I64 size;

  if (!StrsValid(buffer) || !buffer->a)
    return NULL;
  size = StrsLen(buffer);
  if (buffer->capacity <= size)
    return NULL;
  if (buffer->a == buffer->inline_data) {
    data = MAlloc(size + 1);
    MemCpy(data, buffer->a, size + 1);
  } else {
    data = buffer->a;
  }
  StrBufInit(buffer);
  if (length)
    *length = size;
  return data;
}

Bool StrBufTakeStrs(CStrBuf *buffer, CStrs *result)
{
  U8 *data;
  I64 length;

  if (!result)
    return FALSE;
  data = StrBufTake(buffer, &length);
  if (!data) {
    result->a = NULL;
    result->b = NULL;
    return FALSE;
  }
  StrsInitN(result, data, length);
  return TRUE;
}

#endif
