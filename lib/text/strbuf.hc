#ifndef AHOLYC_LIB_TEXT_STRBUF_HC
#define AHOLYC_LIB_TEXT_STRBUF_HC

// Small-string optimized, binary-safe string builder. The data pointer is
// always NUL terminated, while length is authoritative and may include NUL
// bytes. A freshly initialized buffer stores its first 63 bytes inline.

#define STRBUF_INLINE_CAPACITY 64

class CStrBuf
{
  U8 *data;
  I64 length;
  I64 capacity;
  U8 inline_data[STRBUF_INLINE_CAPACITY];
};

U0 StrBufInit(CStrBuf *buffer)
{
  buffer->data = buffer->inline_data;
  buffer->length = 0;
  buffer->capacity = STRBUF_INLINE_CAPACITY;
  buffer->inline_data[0] = 0;
}

// Reserve room for additional payload bytes and the trailing NUL. Capacity
// doubles for ordinary appends; a single large append grows exactly as much
// as needed.
Bool StrBufReserve(CStrBuf *buffer, I64 additional)
{
  U8 *data;
  I64 needed;
  I64 capacity;

  if (!buffer || additional < 0 || buffer->length < 0 ||
    buffer->capacity <= buffer->length || !buffer->data ||
    additional > I64_MAX - buffer->length - 1)
    return FALSE;
  needed = buffer->length + additional + 1;
  if (needed <= buffer->capacity)
    return TRUE;

  capacity = needed;
  if (buffer->capacity <= I64_MAX / 2 && buffer->capacity * 2 > capacity)
    capacity = buffer->capacity * 2;
  data = MAlloc(capacity);
  MemCpy(data, buffer->data, buffer->length + 1);
  if (buffer->data != buffer->inline_data)
    Free(buffer->data);
  buffer->data = data;
  buffer->capacity = capacity;
  return TRUE;
}

Bool StrBufPutN(CStrBuf *buffer, U8 *text, I64 length)
{
  I64 source_offset = -1;
  U64 source;
  U64 start;

  if (!buffer || !buffer->data || buffer->length < 0 ||
    buffer->capacity <= buffer->length || length < 0 || length && !text)
    return FALSE;
  if (!length)
    return TRUE;

  // Preserve a source slice into the buffer if reserving moves its storage.
  source = text(U64);
  start = buffer->data(U64);
  if (source >= start && source - start <= buffer->length &&
    length <= buffer->length - (source - start))
    source_offset = source - start;
  if (!StrBufReserve(buffer, length))
    return FALSE;
  if (source_offset >= 0)
    text = buffer->data + source_offset;
  MemCpy(buffer->data + buffer->length, text, length);
  buffer->length += length;
  buffer->data[buffer->length] = 0;
  return TRUE;
}

Bool StrBufPutS(CStrBuf *buffer, U8 *text)
{
  if (!text)
    return FALSE;
  return StrBufPutN(buffer, text, StrLen(text));
}

Bool StrBufPutC(CStrBuf *buffer, I64 character)
{
  if (!buffer || !StrBufReserve(buffer, 1))
    return FALSE;
  buffer->data[buffer->length++] = character;
  buffer->data[buffer->length] = 0;
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
  if (!buffer || !buffer->data || buffer->capacity < 1)
    return;
  buffer->length = 0;
  buffer->data[0] = 0;
}

U0 StrBufFini(CStrBuf *buffer)
{
  if (!buffer)
    return;
  if (buffer->data && buffer->data != buffer->inline_data)
    Free(buffer->data);
  StrBufInit(buffer);
}

// Transfer a heap buffer without copying. Inline data is copied to a new
// allocation so the result always belongs to the caller and can be Free'd.
U8 *StrBufTake(CStrBuf *buffer, I64 *length=NULL)
{
  U8 *data;
  I64 size;

  if (!buffer || !buffer->data || buffer->length < 0 ||
    buffer->capacity <= buffer->length)
    return NULL;
  size = buffer->length;
  if (buffer->data == buffer->inline_data) {
    data = MAlloc(size + 1);
    MemCpy(data, buffer->data, size + 1);
  } else {
    data = buffer->data;
  }
  StrBufInit(buffer);
  if (length)
    *length = size;
  return data;
}

#endif
