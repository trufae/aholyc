#ifndef AHOLYC_LIB_TEXT_ENCODING_HC
#define AHOLYC_LIB_TEXT_ENCODING_HC

#include "utf8.HC"

// A CText is a borrowed byte slice plus its encoding. TextInit accepts an
// explicit byte length; -1 scans for an encoded NUL. Pascal prefixes always
// count payload bytes, which keeps them independent of the payload encoding.

#define TEXT_ENCODING_UTF8 1
#define TEXT_ENCODING_UTF16_LE 2
#define TEXT_ENCODING_UTF16_BE 3
#define TEXT_ENCODING_UTF32_LE 4
#define TEXT_ENCODING_UTF32_BE 5
#define TEXT_ENCODING_ASCII 6
#define TEXT_ENCODING_LATIN1 7
#define TEXT_ENCODING_EBCDIC_037 8
#define TEXT_ENCODING_EBCDIC TEXT_ENCODING_EBCDIC_037

class CText
{
  U8 *data;
  I64 length;
  I64 encoding;
};

// IBM EBCDIC code page 037. Keeping this out of utf8.HC means JSON and other
// UTF-8-only users do not carry the conversion table in their output.
U16 TextEbcdic037ToRune[256] = {
  0x0000, 0x0001, 0x0002, 0x0003, 0x009C, 0x0009, 0x0086, 0x007F,
    0x0097, 0x008D, 0x008E, 0x000B, 0x000C, 0x000D, 0x000E, 0x000F,
    0x0010, 0x0011, 0x0012, 0x0013, 0x009D, 0x0085, 0x0008, 0x0087,
    0x0018, 0x0019, 0x0092, 0x008F, 0x001C, 0x001D, 0x001E, 0x001F,
    0x0080, 0x0081, 0x0082, 0x0083, 0x0084, 0x000A, 0x0017, 0x001B,
    0x0088, 0x0089, 0x008A, 0x008B, 0x008C, 0x0005, 0x0006, 0x0007,
    0x0090, 0x0091, 0x0016, 0x0093, 0x0094, 0x0095, 0x0096, 0x0004,
    0x0098, 0x0099, 0x009A, 0x009B, 0x0014, 0x0015, 0x009E, 0x001A,
    0x0020, 0x00A0, 0x00E2, 0x00E4, 0x00E0, 0x00E1, 0x00E3, 0x00E5,
    0x00E7, 0x00F1, 0x00A2, 0x002E, 0x003C, 0x0028, 0x002B, 0x007C,
    0x0026, 0x00E9, 0x00EA, 0x00EB, 0x00E8, 0x00ED, 0x00EE, 0x00EF,
    0x00EC, 0x00DF, 0x0021, 0x0024, 0x002A, 0x0029, 0x003B, 0x00AC,
    0x002D, 0x002F, 0x00C2, 0x00C4, 0x00C0, 0x00C1, 0x00C3, 0x00C5,
    0x00C7, 0x00D1, 0x00A6, 0x002C, 0x0025, 0x005F, 0x003E, 0x003F,
    0x00F8, 0x00C9, 0x00CA, 0x00CB, 0x00C8, 0x00CD, 0x00CE, 0x00CF,
    0x00CC, 0x0060, 0x003A, 0x0023, 0x0040, 0x0027, 0x003D, 0x0022,
    0x00D8, 0x0061, 0x0062, 0x0063, 0x0064, 0x0065, 0x0066, 0x0067,
    0x0068, 0x0069, 0x00AB, 0x00BB, 0x00F0, 0x00FD, 0x00FE, 0x00B1,
    0x00B0, 0x006A, 0x006B, 0x006C, 0x006D, 0x006E, 0x006F, 0x0070,
    0x0071, 0x0072, 0x00AA, 0x00BA, 0x00E6, 0x00B8, 0x00C6, 0x00A4,
    0x00B5, 0x007E, 0x0073, 0x0074, 0x0075, 0x0076, 0x0077, 0x0078,
    0x0079, 0x007A, 0x00A1, 0x00BF, 0x00D0, 0x00DD, 0x00DE, 0x00AE,
    0x005E, 0x00A3, 0x00A5, 0x00B7, 0x00A9, 0x00A7, 0x00B6, 0x00BC,
    0x00BD, 0x00BE, 0x005B, 0x005D, 0x00AF, 0x00A8, 0x00B4, 0x00D7,
    0x007B, 0x0041, 0x0042, 0x0043, 0x0044, 0x0045, 0x0046, 0x0047,
    0x0048, 0x0049, 0x00AD, 0x00F4, 0x00F6, 0x00F2, 0x00F3, 0x00F5,
    0x007D, 0x004A, 0x004B, 0x004C, 0x004D, 0x004E, 0x004F, 0x0050,
    0x0051, 0x0052, 0x00B9, 0x00FB, 0x00FC, 0x00F9, 0x00FA, 0x00FF,
    0x005C, 0x00F7, 0x0053, 0x0054, 0x0055, 0x0056, 0x0057, 0x0058,
    0x0059, 0x005A, 0x00B2, 0x00D4, 0x00D6, 0x00D2, 0x00D3, 0x00D5,
    0x0030, 0x0031, 0x0032, 0x0033, 0x0034, 0x0035, 0x0036, 0x0037,
    0x0038, 0x0039, 0x00B3, 0x00DB, 0x00DC, 0x00D9, 0x00DA, 0x009F
};

Bool TextInit(CText *text, U8 *data, I64 length = -1,
  I64 encoding = TEXT_ENCODING_UTF8)
{
  I64 unit;
  I64 i;

  if (!text || length < -1 || encoding < TEXT_ENCODING_UTF8 ||
    encoding > TEXT_ENCODING_EBCDIC_037 || !data && length)
    return FALSE;
  if (length < 0) {
    if (!data)
      return FALSE;
    if (encoding == TEXT_ENCODING_UTF16_LE ||
      encoding == TEXT_ENCODING_UTF16_BE)
      unit = 2;
    else if (encoding == TEXT_ENCODING_UTF32_LE ||
      encoding == TEXT_ENCODING_UTF32_BE)
      unit = 4;
    else
      unit = 1;
    length = 0;
    for (;;) {
      for (i = 0; i < unit && !data[length + i]; i++) {}
      if (i == unit)
        break;
      length += unit;
    }
  }
  text->data = data;
  text->length = length;
  text->encoding = encoding;
  return TRUE;
}

// Returns bytes consumed, or zero for invalid/truncated input or an unknown
// encoding. UTF-16/32 are read bytewise and therefore need no alignment.
I64 TextDecodeRune(U8 *data, I64 length, I64 encoding, I64 *rune)
{
  I64 first;
  I64 second;
  I64 value;
  Bool big;

  if (!data || !rune || length < 1)
    return 0;
  if (encoding == TEXT_ENCODING_UTF8)
    return Utf8DecodeRune(data, length, rune);
  if (encoding == TEXT_ENCODING_ASCII) {
    if (data[0] > 0x7F)
      return 0;
    *rune = data[0];
    return 1;
  }
  if (encoding == TEXT_ENCODING_LATIN1) {
    *rune = data[0];
    return 1;
  }
  if (encoding == TEXT_ENCODING_EBCDIC_037) {
    *rune = TextEbcdic037ToRune[data[0]];
    return 1;
  }
  big = encoding == TEXT_ENCODING_UTF16_BE ||
    encoding == TEXT_ENCODING_UTF32_BE;
  if (encoding == TEXT_ENCODING_UTF16_LE ||
    encoding == TEXT_ENCODING_UTF16_BE) {
      if (length < 2)
        return 0;
      if (big)
        first = data[0] << 8 | data[1];
      else
        first = data[0] | data[1] << 8;
      if (first >= 0xD800 && first <= 0xDBFF) {
        if (length < 4)
          return 0;
        if (big)
          second = data[2] << 8 | data[3];
        else
          second = data[2] | data[3] << 8;
        if (second < 0xDC00 || second > 0xDFFF)
          return 0;
        *rune = 0x10000 + ((first - 0xD800) << 10) + second - 0xDC00;
        return 4;
      }
      if (first >= 0xDC00 && first <= 0xDFFF)
        return 0;
      *rune = first;
      return 2;
    }
  if (encoding != TEXT_ENCODING_UTF32_LE &&
    encoding != TEXT_ENCODING_UTF32_BE || length < 4)
    return 0;
  if (big)
    value = data[0] << 24 | data[1] << 16 | data[2] << 8 | data[3];
  else
    value = data[0] | data[1] << 8 | data[2] << 16 | data[3] << 24;
  if (value < 0 || value > RUNE_MAX ||
    value >= 0xD800 && value <= 0xDFFF)
    return 0;
  *rune = value;
  return 4;
}

// Returns bytes produced. A NULL output performs a sizing probe.
I64 TextEncodeRune(I64 rune, I64 encoding, U8 *output, I64 capacity = 4)
{
  I64 count;
  I64 value;
  I64 i;
  Bool big;

  if (rune < 0 || rune > RUNE_MAX ||
    rune >= 0xD800 && rune <= 0xDFFF)
    return 0;
  if (encoding == TEXT_ENCODING_UTF8)
    return Utf8EncodeRune(rune, output, capacity);
  if (encoding == TEXT_ENCODING_ASCII || encoding == TEXT_ENCODING_LATIN1) {
    if (encoding == TEXT_ENCODING_ASCII && rune > 0x7F ||
      encoding == TEXT_ENCODING_LATIN1 && rune > 0xFF)
      return 0;
    if (output && capacity < 1)
      return 0;
    if (output)
      output[0] = rune;
    return 1;
  }
  if (encoding == TEXT_ENCODING_EBCDIC_037) {
    for (i = 0; i < 256 && TextEbcdic037ToRune[i] != rune; i++) {}
    if (i == 256 || output && capacity < 1)
      return 0;
    if (output)
      output[0] = i;
    return 1;
  }
  big = encoding == TEXT_ENCODING_UTF16_BE ||
    encoding == TEXT_ENCODING_UTF32_BE;
  if (encoding == TEXT_ENCODING_UTF16_LE ||
    encoding == TEXT_ENCODING_UTF16_BE) {
      if (rune <= 0xFFFF)
        count = 2;
      else
        count = 4;
      if (!output)
        return count;
      if (capacity < count)
        return 0;
      if (count == 2) {
        if (big) {
          output[0] = rune >> 8;
          output[1] = rune;
        } else {
          output[0] = rune;
          output[1] = rune >> 8;
        }
      } else {
        value = rune - 0x10000;
        if (big) {
          output[0] = (0xD800 + (value >> 10)) >> 8;
          output[1] = 0xD800 + (value >> 10);
          output[2] = (0xDC00 + (value & 0x3FF)) >> 8;
          output[3] = 0xDC00 + (value & 0x3FF);
        } else {
          output[0] = 0xD800 + (value >> 10);
          output[1] = (0xD800 + (value >> 10)) >> 8;
          output[2] = 0xDC00 + (value & 0x3FF);
          output[3] = (0xDC00 + (value & 0x3FF)) >> 8;
        }
      }
      return count;
    }
  if (encoding != TEXT_ENCODING_UTF32_LE &&
    encoding != TEXT_ENCODING_UTF32_BE)
    return 0;
  if (!output)
    return 4;
  if (capacity < 4)
    return 0;
  if (big) {
    output[0] = rune >> 24;
    output[1] = rune >> 16;
    output[2] = rune >> 8;
    output[3] = rune;
  } else {
    output[0] = rune;
    output[1] = rune >> 8;
    output[2] = rune >> 16;
    output[3] = rune >> 24;
  }
  return 4;
}

// rune_count is optional, avoiding a separate counting API.
Bool TextValid(CText *text, I64 *rune_count = NULL)
{
  I64 position = 0;
  I64 count = 0;
  I64 consumed;
  I64 rune;

  if (!text || text->length < 0 || text->length && !text->data ||
    text->encoding < TEXT_ENCODING_UTF8 ||
    text->encoding > TEXT_ENCODING_EBCDIC_037)
    return FALSE;
  while (position < text->length) {
    consumed = TextDecodeRune(text->data + position,
      text->length - position, text->encoding, &rune);
    if (!consumed)
      return FALSE;
    position += consumed;
    count++;
  }
  if (rune_count)
    *rune_count = count;
  return TRUE;
}

// Converts complete runes only and returns the required output byte count.
// A NULL output is a sizing pass. If capacity is short, a whole-rune prefix is
// written and the larger required count is returned. -1 means invalid source
// text, an unknown encoding, overflow, or an unrepresentable target rune.
I64 TextConvert(CText *text, I64 encoding, U8 *output, I64 capacity)
{
  U8 bytes[4];
  I64 position = 0;
  I64 total = 0;
  I64 consumed;
  I64 produced;
  I64 rune;

  if (!text || text->length < 0 || text->length && !text->data ||
    text->encoding < TEXT_ENCODING_UTF8 ||
    text->encoding > TEXT_ENCODING_EBCDIC_037 ||
    encoding < TEXT_ENCODING_UTF8 ||
    encoding > TEXT_ENCODING_EBCDIC_037 || capacity < 0)
    return -1;
  while (position < text->length) {
    consumed = TextDecodeRune(text->data + position,
      text->length - position, text->encoding, &rune);
    if (!consumed)
      return -1;
    produced = TextEncodeRune(rune, encoding, bytes, sizeof(bytes));
    if (!produced || total > I64_MAX - produced)
      return -1;
    if (output && total <= capacity && produced <= capacity - total)
      MemCpy(output + total, bytes, produced);
    position += consumed;
    total += produced;
  }
  return total;
}

Bool TextFromPascal(CText *text, U8 *data, I64 available,
  I64 prefix_bytes = 1, Bool big_endian = FALSE,
  I64 encoding = TEXT_ENCODING_UTF8)
{
  I64 length;

  if (!data || available < prefix_bytes ||
    prefix_bytes != 1 && prefix_bytes != 2 && prefix_bytes != 4)
    return FALSE;
  if (prefix_bytes == 1)
    length = data[0];
  else if (prefix_bytes == 2 && big_endian)
    length = data[0] << 8 | data[1];
  else if (prefix_bytes == 2)
    length = data[0] | data[1] << 8;
  else if (big_endian)
    length = data[0] << 24 | data[1] << 16 | data[2] << 8 | data[3];
  else
    length = data[0] | data[1] << 8 | data[2] << 16 | data[3] << 24;
  if (length > available - prefix_bytes)
    return FALSE;
  return TextInit(text, data + prefix_bytes, length, encoding);
}

// Returns the required prefix+payload size, even if capacity is too small.
// No bytes are written unless the complete Pascal string fits.
I64 TextWritePascal(CText *text, U8 *output, I64 capacity,
  I64 prefix_bytes = 1, Bool big_endian = FALSE)
{
  I64 maximum;
  I64 total;

  if (!text || text->length < 0 || text->length && !text->data ||
    text->encoding < TEXT_ENCODING_UTF8 ||
    text->encoding > TEXT_ENCODING_EBCDIC_037 || capacity < 0 ||
    prefix_bytes != 1 && prefix_bytes != 2 && prefix_bytes != 4)
    return -1;
  if (prefix_bytes == 1)
    maximum = U8_MAX;
  else if (prefix_bytes == 2)
    maximum = U16_MAX;
  else
    maximum = U32_MAX;
  if (text->length > maximum || text->length > I64_MAX - prefix_bytes)
    return -1;
  total = prefix_bytes + text->length;
  if (!output || capacity < total)
    return total;
  if (prefix_bytes == 1) {
    output[0] = text->length;
  } else if (prefix_bytes == 2 && big_endian) {
    output[0] = text->length >> 8;
    output[1] = text->length;
  } else if (prefix_bytes == 2) {
    output[0] = text->length;
    output[1] = text->length >> 8;
  } else if (big_endian) {
    output[0] = text->length >> 24;
    output[1] = text->length >> 16;
    output[2] = text->length >> 8;
    output[3] = text->length;
  } else {
    output[0] = text->length;
    output[1] = text->length >> 8;
    output[2] = text->length >> 16;
    output[3] = text->length >> 24;
  }
  if (text->length)
    MemCpy(output + prefix_bytes, text->data, text->length);
  return total;
}

#endif
