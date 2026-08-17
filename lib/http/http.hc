#ifndef AHOLYC_LIB_HTTP_HTTP_HC
#define AHOLYC_LIB_HTTP_HTTP_HC

// Pieces shared by the HTTP client and server: a growable byte buffer, URL
// parsing and percent coding, case-insensitive header helpers, and chunked
// transfer decoding. Applications include client.hc or server.hc.

#include "../net/socket.hc"

#ifndef HTTP_MAX_MESSAGE
#define HTTP_MAX_MESSAGE 268435456
#endif

class CHttpBuffer
{
  U8 *data;
  I64 length;
  I64 capacity;
};

class CHttpUrl
{
  Bool secure;
  Bool ipv6;
  U8 *host;
  I64 port;
  U8 *target;
};

U0 HttpBufferInit(CHttpBuffer *buffer)
{
  buffer->data = NULL;
  buffer->length = 0;
  buffer->capacity = 0;
}

U0 HttpBufferFree(CHttpBuffer *buffer)
{
  Free(buffer->data);
  HttpBufferInit(buffer);
}

Bool HttpBufferReserve(CHttpBuffer *buffer, I64 needed)
{
  U8 *data;
  I64 capacity;

  if (needed < 0 || needed > HTTP_MAX_MESSAGE)
    return FALSE;
  if (needed <= buffer->capacity)
    return TRUE;

  capacity = buffer->capacity;
  if (capacity < 256)
    capacity = 256;
  while (capacity < needed) {
    if (capacity > HTTP_MAX_MESSAGE / 2)
      capacity = HTTP_MAX_MESSAGE;
    else
      capacity *= 2;
    if (capacity < needed && capacity == HTTP_MAX_MESSAGE)
      return FALSE;
  }

  data = MAlloc(capacity);
  if (buffer->length)
    MemCpy(data, buffer->data, buffer->length);
  Free(buffer->data);
  buffer->data = data;
  buffer->capacity = capacity;
  return TRUE;
}

Bool HttpBufferAppend(CHttpBuffer *buffer, U8 *data, I64 size)
{
  if (size < 0 || size && !data)
    return FALSE;
  if (!HttpBufferReserve(buffer, buffer->length + size + 1))
    return FALSE;
  if (size)
    MemCpy(buffer->data + buffer->length, data, size);
  buffer->length += size;
  buffer->data[buffer->length] = 0;
  return TRUE;
}

Bool HttpBufferAppendString(CHttpBuffer *buffer, U8 *text)
{
  if (!text)
    return TRUE;
  return HttpBufferAppend(buffer, text, StrLen(text));
}

Bool HttpBufferAppendFormat(CHttpBuffer *buffer, U8 *format, ...)
{
  U8 *text = StrPrintJoin(NULL, format, argc, argv);
  Bool result = HttpBufferAppendString(buffer, text);

  Free(text);
  return result;
}

U8 *HttpBufferTake(CHttpBuffer *buffer, I64 *size=NULL)
{
  U8 *data;

  if (!buffer->data) {
    buffer->data = MAlloc(1);
    buffer->data[0] = 0;
    buffer->capacity = 1;
  }
  data = buffer->data;
  if (size)
    *size = buffer->length;
  buffer->data = NULL;
  buffer->length = 0;
  buffer->capacity = 0;
  return data;
}

U8 HttpAsciiLower(U8 character)
{
  if (character >= 'A' && character <= 'Z')
    return character + 'a' - 'A';
  return character;
}

Bool HttpStartsWithInsensitive(U8 *text, U8 *prefix)
{
  if (!text || !prefix)
    return FALSE;
  while (*prefix) {
    if (!*text || HttpAsciiLower(*text) != HttpAsciiLower(*prefix))
      return FALSE;
    text++;
    prefix++;
  }
  return TRUE;
}

Bool HttpEqualsInsensitive(U8 *left, U8 *right)
{
  if (!left || !right)
    return FALSE;
  while (*left && *right) {
    if (HttpAsciiLower(*left) != HttpAsciiLower(*right))
      return FALSE;
    left++;
    right++;
  }
  return !*left && !*right;
}

Bool HttpBytesEqualInsensitive(U8 *left, I64 left_size, U8 *right)
{
  I64 i;

  if (!left || !right || left_size != StrLen(right))
    return FALSE;
  for (i = 0; i < left_size; i++) {
    if (HttpAsciiLower(left[i]) != HttpAsciiLower(right[i]))
      return FALSE;
  }
  return TRUE;
}

U8 *HttpSlice(U8 *text, I64 start, I64 finish)
{
  U8 *result;

  if (!text || start < 0 || finish < start)
    return NULL;
  result = MAlloc(finish - start + 1);
  if (finish > start)
    MemCpy(result, text + start, finish - start);
  result[finish - start] = 0;
  return result;
}

Bool HttpParsePort(U8 *text, I64 start, I64 finish, I64 *port)
{
  I64 i;
  I64 value = 0;

  if (start >= finish)
    return FALSE;
  for (i = start; i < finish; i++) {
    if (text[i] < '0' || text[i] > '9')
      return FALSE;
    value = value * 10 + text[i] - '0';
    if (value > 65535)
      return FALSE;
  }
  if (!value)
    return FALSE;
  *port = value;
  return TRUE;
}

Bool HttpHostIsSafe(U8 *host)
{
  U8 *cursor = host;

  if (!cursor || !*cursor)
    return FALSE;
  while (*cursor) {
    if (*cursor <= 32 || *cursor == 127 || *cursor == '@')
      return FALSE;
    cursor++;
  }
  return TRUE;
}

Bool HttpTargetIsSafe(U8 *target)
{
  U8 *cursor = target;

  if (!cursor || *cursor != '/')
    return FALSE;
  while (*cursor) {
    if (*cursor <= 32 || *cursor == 127)
      return FALSE;
    cursor++;
  }
  return TRUE;
}

U0 HttpUrlFree(CHttpUrl *url)
{
  if (!url)
    return;
  Free(url->host);
  Free(url->target);
  MemSet(url, 0, sizeof(CHttpUrl));
}

Bool HttpUrlParse(U8 *text, CHttpUrl *url)
{
  I64 length;
  I64 authority_start;
  I64 authority_finish;
  I64 fragment;
  I64 i;
  I64 close_bracket = -1;
  I64 colon = -1;
  I64 colon_count = 0;
  CHttpBuffer target;

  MemSet(url, 0, sizeof(CHttpUrl));
  if (HttpStartsWithInsensitive(text, "https://")) {
    url->secure = TRUE;
    url->port = 443;
    authority_start = 8;
  } else if (HttpStartsWithInsensitive(text, "http://")) {
    url->secure = FALSE;
    url->port = 80;
    authority_start = 7;
  } else {
    return FALSE;
  }

  length = StrLen(text);
  authority_finish = authority_start;
  while (authority_finish < length &&
    text[authority_finish] != '/' &&
    text[authority_finish] != '?' &&
    text[authority_finish] != '#')
    authority_finish++;
  if (authority_finish == authority_start)
    return FALSE;

  if (text[authority_start] == '[') {
    for (i = authority_start + 1; i < authority_finish; i++) {
      if (text[i] == ']' && close_bracket < 0)
        close_bracket = i;
    }
    if (close_bracket < 0)
      return FALSE;
    url->ipv6 = TRUE;
    url->host = HttpSlice(text, authority_start + 1, close_bracket);
    if (close_bracket + 1 < authority_finish) {
      if (text[close_bracket + 1] != ':' ||
        !HttpParsePort(text, close_bracket + 2, authority_finish,
          &url->port)) {
            HttpUrlFree(url);
            return FALSE;
          }
    }
  } else {
    for (i = authority_start; i < authority_finish; i++) {
      if (text[i] == ':') {
        colon = i;
        colon_count++;
      }
      if (text[i] == '@') {
        HttpUrlFree(url);
        return FALSE;
      }
    }
    if (colon_count > 1) {
      HttpUrlFree(url);
      return FALSE;
    }
    if (colon_count == 1) {
      url->host = HttpSlice(text, authority_start, colon);
      if (!HttpParsePort(text, colon + 1, authority_finish, &url->port)) {
        HttpUrlFree(url);
        return FALSE;
      }
    } else {
      url->host = HttpSlice(text, authority_start, authority_finish);
    }
  }

  if (!HttpHostIsSafe(url->host)) {
    HttpUrlFree(url);
    return FALSE;
  }

  fragment = authority_finish;
  while (fragment < length && text[fragment] != '#')
    fragment++;

  if (authority_finish == fragment) {
    url->target = StrNew("/");
  } else if (text[authority_finish] == '?') {
    HttpBufferInit(&target);
    HttpBufferAppendString(&target, "/");
    if (!HttpBufferAppend(&target, text + authority_finish,
        fragment - authority_finish)) {
          HttpBufferFree(&target);
          HttpUrlFree(url);
          return FALSE;
        }
    url->target = HttpBufferTake(&target);
  } else {
    url->target = HttpSlice(text, authority_finish, fragment);
  }

  if (!HttpTargetIsSafe(url->target)) {
    HttpUrlFree(url);
    return FALSE;
  }
  return TRUE;
}

Bool HttpUrlByteIsUnreserved(U8 value)
{
  return value >= 'A' && value <= 'Z' ||
    value >= 'a' && value <= 'z' ||
    value >= '0' && value <= '9' ||
    value == '-' || value == '.' || value == '_' || value == '~';
}

U8 HttpHexDigit(I64 value)
{
  if (value < 10)
    return '0' + value;
  return 'A' + value - 10;
}

I64 HttpHexValue(U8 value)
{
  if (value >= '0' && value <= '9')
    return value - '0';
  value = HttpAsciiLower(value);
  if (value >= 'a' && value <= 'f')
    return value - 'a' + 10;
  return -1;
}

U8 *HttpUrlEncodeMode(U8 *data, I64 size, Bool form)
{
  U8 *result;
  I64 i;
  I64 output = 0;

  if (!data)
    return NULL;
  if (size < 0)
    size = StrLen(data);
  if (size > (HTTP_MAX_MESSAGE - 1) / 3)
    return NULL;

  result = MAlloc(size * 3 + 1);
  for (i = 0; i < size; i++) {
    if (HttpUrlByteIsUnreserved(data[i])) {
      result[output++] = data[i];
    } else if (form && data[i] == ' ') {
      result[output++] = '+';
    } else {
      result[output++] = '%';
      result[output++] = HttpHexDigit(data[i] >> 4);
      result[output++] = HttpHexDigit(data[i] & 15);
    }
  }
  result[output] = 0;
  return result;
}

U8 *HttpUrlEncode(U8 *data, I64 size=-1)
{
  return HttpUrlEncodeMode(data, size, FALSE);
}

U8 *HttpFormEncode(U8 *data, I64 size=-1)
{
  return HttpUrlEncodeMode(data, size, TRUE);
}

U8 *HttpUrlDecodeMode(U8 *data, I64 size, I64 *decoded_size, Bool form)
{
  U8 *result;
  I64 i = 0;
  I64 output = 0;
  I64 high;
  I64 low;

  if (!data)
    return NULL;
  if (size < 0)
    size = StrLen(data);
  result = MAlloc(size + 1);

  while (i < size) {
    if (data[i] == '%') {
      if (i + 2 >= size) {
        Free(result);
        return NULL;
      }
      high = HttpHexValue(data[i + 1]);
      low = HttpHexValue(data[i + 2]);
      if (high < 0 || low < 0) {
        Free(result);
        return NULL;
      }
      result[output++] = high << 4 | low;
      i += 3;
    } else {
      if (form && data[i] == '+')
        result[output++] = ' ';
      else
        result[output++] = data[i];
      i++;
    }
  }
  result[output] = 0;
  if (decoded_size)
    *decoded_size = output;
  return result;
}

U8 *HttpUrlDecode(U8 *data, I64 size=-1, I64 *decoded_size=NULL)
{
  return HttpUrlDecodeMode(data, size, decoded_size, FALSE);
}

U8 *HttpFormDecode(U8 *data, I64 size=-1, I64 *decoded_size=NULL)
{
  return HttpUrlDecodeMode(data, size, decoded_size, TRUE);
}

// TRUE when the raw "Name: value\r\n" header lines already carry name.
Bool HttpHeadersHave(U8 *headers, U8 *name)
{
  U8 *cursor = headers;
  I64 length = StrLen(name);

  while (cursor && *cursor) {
    if (HttpBytesEqualInsensitive(cursor, length, name) &&
      cursor[length] == ':')
      return TRUE;
    while (*cursor && *cursor != '\n')
      cursor++;
    if (*cursor)
      cursor++;
  }
  return FALSE;
}

Bool HttpMethodIsSafe(U8 *method)
{
  U8 *cursor = method;

  if (!cursor || !*cursor)
    return FALSE;
  while (*cursor) {
    if (!(*cursor >= 'A' && *cursor <= 'Z') && *cursor != '-')
      return FALSE;
    cursor++;
  }
  return TRUE;
}

I64 HttpFindHeaderEnd(U8 *data, I64 size)
{
  I64 i;

  for (i = 0; i + 3 < size; i++) {
    if (data[i] == '\r' && data[i + 1] == '\n' &&
      data[i + 2] == '\r' && data[i + 3] == '\n')
      return i + 4;
  }
  return -1;
}

// Find a header in a raw block of "Name: value\r\n" lines whose first line
// is the status or request line. Returns an allocated trimmed value or NULL.
U8 *HttpHeaderFind(U8 *headers, I64 headers_length, U8 *name)
{
  I64 position = 0;
  I64 line_start;
  I64 line_finish;
  I64 colon;
  I64 value_start;
  I64 value_finish;

  if (!headers || !name)
    return NULL;

  // Skip the status line.
  while (position + 1 < headers_length &&
    !(headers[position] == '\r' &&
      headers[position + 1] == '\n'))
    position++;
  position += 2;

  while (position < headers_length) {
    line_start = position;
    line_finish = line_start;
    while (line_finish + 1 < headers_length &&
      !(headers[line_finish] == '\r' &&
        headers[line_finish + 1] == '\n'))
      line_finish++;
    if (line_finish == line_start)
      return NULL;

    colon = line_start;
    while (colon < line_finish && headers[colon] != ':')
      colon++;
    if (colon < line_finish &&
      HttpBytesEqualInsensitive(headers + line_start,
        colon - line_start, name)) {
          value_start = colon + 1;
          while (value_start < line_finish &&
            (headers[value_start] == ' ' ||
              headers[value_start] == '\t'))
            value_start++;
          value_finish = line_finish;
          while (value_finish > value_start &&
            (headers[value_finish - 1] == ' ' ||
              headers[value_finish - 1] == '\t'))
            value_finish--;
          return HttpSlice(headers, value_start, value_finish);
        }
    position = line_finish + 2;
  }
  return NULL;
}

Bool HttpValueHasToken(U8 *value, U8 *token)
{
  I64 start = 0;
  I64 finish;
  I64 length;

  if (!value || !token)
    return FALSE;
  length = StrLen(value);
  while (start < length) {
    while (start < length &&
      (value[start] == ' ' || value[start] == '\t' ||
        value[start] == ','))
      start++;
    finish = start;
    while (finish < length && value[finish] != ',')
      finish++;
    while (finish > start &&
      (value[finish - 1] == ' ' || value[finish - 1] == '\t'))
      finish--;
    if (HttpBytesEqualInsensitive(value + start, finish - start, token))
      return TRUE;
    start = finish + 1;
  }
  return FALSE;
}

Bool HttpParseDecimal(U8 *text, I64 *value)
{
  I64 result = 0;
  U8 *cursor = text;

  if (!cursor || !*cursor)
    return FALSE;
  while (*cursor) {
    if (*cursor < '0' || *cursor > '9')
      return FALSE;
    result = result * 10 + *cursor - '0';
    if (result > HTTP_MAX_MESSAGE)
      return FALSE;
    cursor++;
  }
  *value = result;
  return TRUE;
}

U8 *HttpDecodeChunked(U8 *encoded, I64 encoded_size, I64 *decoded_size)
{
  CHttpBuffer decoded;
  I64 position = 0;
  I64 digit;
  I64 chunk_size;
  Bool have_digit;

  HttpBufferInit(&decoded);
  while (position < encoded_size) {
    chunk_size = 0;
    have_digit = FALSE;
    while (position < encoded_size &&
      encoded[position] != '\r' && encoded[position] != ';') {
        digit = HttpHexValue(encoded[position]);
        if (digit < 0) {
          HttpBufferFree(&decoded);
          return NULL;
        }
        have_digit = TRUE;
        chunk_size = chunk_size << 4 | digit;
        if (chunk_size > HTTP_MAX_MESSAGE) {
          HttpBufferFree(&decoded);
          return NULL;
        }
        position++;
      }
    if (!have_digit) {
      HttpBufferFree(&decoded);
      return NULL;
    }
    while (position < encoded_size && encoded[position] != '\r')
      position++;
    if (position + 1 >= encoded_size ||
      encoded[position] != '\r' || encoded[position + 1] != '\n') {
        HttpBufferFree(&decoded);
        return NULL;
      }
    position += 2;

    if (!chunk_size)
      return HttpBufferTake(&decoded, decoded_size);
    if (position + chunk_size + 2 > encoded_size ||
      encoded[position + chunk_size] != '\r' ||
      encoded[position + chunk_size + 1] != '\n' ||
      !HttpBufferAppend(&decoded, encoded + position, chunk_size)) {
        HttpBufferFree(&decoded);
        return NULL;
      }
    position += chunk_size + 2;
  }
  HttpBufferFree(&decoded);
  return NULL;
}

#endif
