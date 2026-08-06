#ifndef AHOLYC_LIB_TEXT_UTF8_HC
#define AHOLYC_LIB_TEXT_UTF8_HC

// Strict, allocation-free UTF-8 primitives. All lengths are byte counts;
// buffers need not be NUL terminated. Decode/encode return the byte count, or
// zero for an invalid rune, invalid sequence, or insufficient output space.

#define RUNE_REPLACEMENT 0xFFFD
#define RUNE_MAX 0x10FFFF

I64 Utf8DecodeRune(U8 *data, I64 length, I64 *rune)
{
  I64 value;
  U8 first;
  U8 second;

  if (!data || !rune || length < 1)
    return 0;
  first = data[0];
  if (first < 0x80) {
    *rune = first;
    return 1;
  }
  if (first >= 0xC2 && first <= 0xDF) {
    if (length < 2 || data[1] < 0x80 || data[1] > 0xBF)
      return 0;
    *rune = (first & 0x1F) << 6 | data[1] & 0x3F;
    return 2;
  }
  if (first >= 0xE0 && first <= 0xEF) {
    if (length < 3)
      return 0;
    second = data[1];
    if (second < 0x80 || second > 0xBF ||
      data[2] < 0x80 || data[2] > 0xBF ||
      first == 0xE0 && second < 0xA0 ||
      first == 0xED && second >= 0xA0)
      return 0;
    value = (first & 15) << 12 | (second & 0x3F) << 6 |
      data[2] & 0x3F;
    *rune = value;
    return 3;
  }
  if (first >= 0xF0 && first <= 0xF4) {
    if (length < 4)
      return 0;
    second = data[1];
    if (second < 0x80 || second > 0xBF ||
      data[2] < 0x80 || data[2] > 0xBF ||
      data[3] < 0x80 || data[3] > 0xBF ||
      first == 0xF0 && second < 0x90 ||
      first == 0xF4 && second > 0x8F)
      return 0;
    value = (first & 7) << 18 | (second & 0x3F) << 12 |
      (data[2] & 0x3F) << 6 | data[3] & 0x3F;
    *rune = value;
    return 4;
  }
  return 0;
}

I64 Utf8EncodeRune(I64 rune, U8 *output, I64 capacity = 4)
{
  I64 count;

  if (rune < 0 || rune > RUNE_MAX ||
    rune >= 0xD800 && rune <= 0xDFFF)
    return 0;
  if (rune <= 0x7F)
    count = 1;
  else if (rune <= 0x7FF)
    count = 2;
  else if (rune <= 0xFFFF)
    count = 3;
  else
    count = 4;
  if (!output)
    return count;
  if (capacity < count)
    return 0;
  if (count == 1) {
    output[0] = rune;
  } else if (count == 2) {
    output[0] = 0xC0 | rune >> 6;
    output[1] = 0x80 | rune & 0x3F;
  } else if (count == 3) {
    output[0] = 0xE0 | rune >> 12;
    output[1] = 0x80 | rune >> 6 & 0x3F;
    output[2] = 0x80 | rune & 0x3F;
  } else {
    output[0] = 0xF0 | rune >> 18;
    output[1] = 0x80 | rune >> 12 & 0x3F;
    output[2] = 0x80 | rune >> 6 & 0x3F;
    output[3] = 0x80 | rune & 0x3F;
  }
  return count;
}

// rune_count is optional, avoiding a second public counting API.
Bool Utf8Valid(U8 *data, I64 length, I64 *rune_count = NULL)
{
  I64 position = 0;
  I64 count = 0;
  I64 consumed;
  I64 rune;

  if (length < 0 || length && !data)
    return FALSE;
  while (position < length) {
    consumed = Utf8DecodeRune(data + position, length - position, &rune);
    if (!consumed)
      return FALSE;
    position += consumed;
    count++;
  }
  if (rune_count)
    *rune_count = count;
  return TRUE;
}

#endif
