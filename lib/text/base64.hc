#ifndef AHOLYC_LIB_TEXT_BASE64_HC
#define AHOLYC_LIB_TEXT_BASE64_HC

// RFC 4648 base64 for binary data. Encode output is NUL-terminated for
// convenience; decoded output is binary and decoded_length is authoritative.

I64 Base64EncodedLength(I64 length)
{
  I64 groups;

  if (length < 0 || length > I64_MAX - 2)
    return -1;
  groups = (length + 2) / 3;
  if (groups > I64_MAX / 4)
    return -1;
  return groups * 4;
}

Bool Base64Encode(U8 *data, I64 length, U8 *output, I64 capacity,
  I64 *encoded_length=NULL)
{
  U8 *alphabet =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  I64 needed = Base64EncodedLength(length);
  I64 input = 0;
  I64 result = 0;
  U64 value;
  I64 remaining;

  if (needed < 0 || length && !data || capacity < 0)
    return FALSE;
  if (encoded_length)
    *encoded_length = needed;
  if (!output)
    return TRUE;
  if (capacity <= needed)
    return FALSE;

  while (input < length) {
    remaining = length - input;
    value = data[input++] << 16;
    if (remaining > 1)
      value |= data[input++] << 8;
    if (remaining > 2)
      value |= data[input++];

    output[result++] = alphabet[value >> 18 & 63];
    output[result++] = alphabet[value >> 12 & 63];
    if (remaining > 1)
      output[result++] = alphabet[value >> 6 & 63];
    else
      output[result++] = '=';
    if (remaining > 2)
      output[result++] = alphabet[value & 63];
    else
      output[result++] = '=';
  }
  output[result] = 0;
  return TRUE;
}

U8 *Base64EncodeAlloc(U8 *data, I64 length, I64 *encoded_length=NULL)
{
  I64 needed = Base64EncodedLength(length);
  U8 *result;

  if (needed < 0 || length && !data)
    return NULL;
  result = MAlloc(needed + 1);
  if (!Base64Encode(data, length, result, needed + 1, encoded_length)) {
    Free(result);
    return NULL;
  }
  return result;
}

I64 Base64Value(U8 character)
{
  if (character >= 'A' && character <= 'Z')
    return character - 'A';
  if (character >= 'a' && character <= 'z')
    return character - 'a' + 26;
  if (character >= '0' && character <= '9')
    return character - '0' + 52;
  if (character == '+')
    return 62;
  if (character == '/')
    return 63;
  return -1;
}

Bool Base64Decode(U8 *text, I64 length, U8 *output, I64 capacity,
  I64 *decoded_length=NULL)
{
  I64 i;
  I64 result = 0;
  I64 a;
  I64 b;
  I64 c;
  I64 d;
  I64 needed;
  I64 padding = 0;

  if (length < 0 || length && !text || capacity < 0 || length & 3)
    return FALSE;
  if (length) {
    if (text[length - 1] == '=')
      padding++;
    if (length > 1 && text[length - 2] == '=')
      padding++;
  }
  needed = length / 4 * 3 - padding;
  if (decoded_length)
    *decoded_length = needed;
  if (output && capacity < needed)
    return FALSE;

  for (i = 0; i < length; i += 4) {
    a = Base64Value(text[i]);
    b = Base64Value(text[i + 1]);
    if (a < 0 || b < 0)
      return FALSE;

    if (text[i + 2] == '=') {
      if (i + 4 != length || text[i + 3] != '=' || b & 15)
        return FALSE;
      c = 0;
      d = 0;
    } else {
      c = Base64Value(text[i + 2]);
      if (c < 0)
        return FALSE;
      if (text[i + 3] == '=') {
        if (i + 4 != length || c & 3)
          return FALSE;
        d = 0;
      } else {
        d = Base64Value(text[i + 3]);
        if (d < 0)
          return FALSE;
      }
    }

    if (output)
      output[result] = a << 2 | b >> 4;
    result++;
    if (text[i + 2] != '=') {
      if (output)
        output[result] = b << 4 | c >> 2;
      result++;
    }
    if (text[i + 3] != '=') {
      if (output)
        output[result] = c << 6 | d;
      result++;
    }
  }
  return TRUE;
}

U8 *Base64DecodeAlloc(U8 *text, I64 length, I64 *decoded_length=NULL)
{
  I64 needed;
  U8 *result;

  if (!Base64Decode(text, length, NULL, 0, &needed))
    return NULL;
  result = MAlloc(needed + 1);
  if (!Base64Decode(text, length, result, needed, decoded_length)) {
    Free(result);
    return NULL;
  }
  result[needed] = 0;
  return result;
}

#endif
