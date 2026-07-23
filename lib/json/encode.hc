#ifndef AHOLYC_LIB_JSON_ENCODE_HC
#define AHOLYC_LIB_JSON_ENCODE_HC

// Heap-free JSON encoder writing into caller-owned memory.
//
// Capacity includes the trailing NUL. Pass NULL as the buffer to perform a
// count-only sizing pass; encoder.length then contains the required JSON byte
// count. The structural API inserts commas and colons automatically.
//
//   U8 output[128];
//   CJsonEncoder encoder;
//   JsonEncoderInit(&encoder, output, sizeof(output));
//   JsonEncodeObjectStart(&encoder);
//   JsonEncodeKey(&encoder, "answer");
//   JsonEncodeI64(&encoder, 42);
//   JsonEncodeObjectEnd(&encoder);
//   if (JsonEncoderFinish(&encoder) >= 0)
//     "%s\n", output;
//
// The encoder has a fixed 63-level structural stack encoded in three U64 bit
// fields. It never allocates.

#define JSON_ENCODE_OK 0
#define JSON_ENCODE_INVALID_ARGUMENT 1
#define JSON_ENCODE_NO_SPACE 2
#define JSON_ENCODE_INVALID_STATE 3
#define JSON_ENCODE_INVALID_UTF8 4
#define JSON_ENCODE_INVALID_NUMBER 5
#define JSON_ENCODE_MAX_DEPTH 6

#define JSON_ENCODER_MAX_DEPTH 63

class CJsonEncoder
{
  U8 *data;
  I64 capacity;
  I64 length;
  I64 error;
  I64 depth;
  U64 object_bits;
  U64 comma_bits;
  U64 value_bits;
  Bool root_written;
};

U0 JsonEncoderSetError(CJsonEncoder *encoder, I64 error)
{
  if (!encoder->error || encoder->error == JSON_ENCODE_NO_SPACE)
    encoder->error = error;
}

Bool JsonEncoderFatal(CJsonEncoder *encoder)
{
  return encoder->error && encoder->error != JSON_ENCODE_NO_SPACE;
}

U0 JsonEncoderPutByte(CJsonEncoder *encoder, U8 byte)
{
  if (encoder->data) {
    if (encoder->capacity > 0 && encoder->length < encoder->capacity - 1)
      encoder->data[encoder->length] = byte;
    else if (!encoder->error)
      encoder->error = JSON_ENCODE_NO_SPACE;
  }
  encoder->length++;
}

U0 JsonEncoderPutBytes(CJsonEncoder *encoder, U8 *data, I64 length)
{
  I64 available = 0;
  I64 copy = length;

  if (encoder->data) {
    if (encoder->capacity > 0 &&
      encoder->length < encoder->capacity - 1)
      available = encoder->capacity - 1 - encoder->length;
    if (copy > available)
      copy = available;
    if (copy > 0)
      MemCpy(encoder->data + encoder->length, data, copy);
    if (copy < length && !encoder->error)
      encoder->error = JSON_ENCODE_NO_SPACE;
  }
  encoder->length += length;
}

Bool JsonEncoderUtf8(U8 *data, I64 length)
{
  I64 i = 0;
  U8 first;
  U8 second;

  while (i < length) {
    first = data[i];
    if (first < 0x80) {
      i++;
    } else if (first >= 0xC2 && first <= 0xDF) {
      if (i + 1 >= length || data[i + 1] < 0x80 || data[i + 1] > 0xBF)
        return FALSE;
      i += 2;
    } else if (first >= 0xE0 && first <= 0xEF) {
      if (i + 2 >= length)
        return FALSE;
      second = data[i + 1];
      if (second < 0x80 || second > 0xBF ||
        data[i + 2] < 0x80 || data[i + 2] > 0xBF)
        return FALSE;
      if (first == 0xE0 && second < 0xA0 ||
        first == 0xED && second >= 0xA0)
        return FALSE;
      i += 3;
    } else if (first >= 0xF0 && first <= 0xF4) {
      if (i + 3 >= length)
        return FALSE;
      second = data[i + 1];
      if (second < 0x80 || second > 0xBF ||
        data[i + 2] < 0x80 || data[i + 2] > 0xBF ||
        data[i + 3] < 0x80 || data[i + 3] > 0xBF)
        return FALSE;
      if (first == 0xF0 && second < 0x90 ||
        first == 0xF4 && second > 0x8F)
        return FALSE;
      i += 4;
    } else {
      return FALSE;
    }
  }
  return TRUE;
}

U64 JsonEncoderLevelBit(CJsonEncoder *encoder)
{
  U64 bit = 1;

  bit <<= encoder->depth - 1;
  return bit;
}

Bool JsonEncoderBeforeValue(CJsonEncoder *encoder)
{
  U64 bit;

  if (JsonEncoderFatal(encoder))
    return FALSE;
  if (!encoder->depth) {
    if (encoder->root_written) {
      JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_STATE);
      return FALSE;
    }
    encoder->root_written = TRUE;
    return TRUE;
  }

  bit = JsonEncoderLevelBit(encoder);
  if (encoder->object_bits & bit) {
    if (!(encoder->value_bits & bit)) {
      JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_STATE);
      return FALSE;
    }
    encoder->value_bits &= ~bit;
    encoder->comma_bits |= bit;
  } else {
    if (encoder->comma_bits & bit)
      JsonEncoderPutByte(encoder, ',');
    encoder->comma_bits |= bit;
  }
  return !JsonEncoderFatal(encoder);
}

U0 JsonEncoderQuoteUnchecked(CJsonEncoder *encoder, U8 *text, I64 length)
{
  I64 i;
  I64 start = 0;
  U8 ch;
  U8 *hex = "0123456789abcdef";

  JsonEncoderPutByte(encoder, '"');
  for (i = 0; i < length; i++) {
    ch = text[i];
    if (ch == '"' || ch == '\\') {
      JsonEncoderPutBytes(encoder, text + start, i - start);
      JsonEncoderPutByte(encoder, '\\');
      JsonEncoderPutByte(encoder, ch);
      start = i + 1;
    } else if (ch == '\b') {
      JsonEncoderPutBytes(encoder, text + start, i - start);
      JsonEncoderPutBytes(encoder, "\\b", 2);
      start = i + 1;
    } else if (ch == '\f') {
      JsonEncoderPutBytes(encoder, text + start, i - start);
      JsonEncoderPutBytes(encoder, "\\f", 2);
      start = i + 1;
    } else if (ch == '\n') {
      JsonEncoderPutBytes(encoder, text + start, i - start);
      JsonEncoderPutBytes(encoder, "\\n", 2);
      start = i + 1;
    } else if (ch == '\r') {
      JsonEncoderPutBytes(encoder, text + start, i - start);
      JsonEncoderPutBytes(encoder, "\\r", 2);
      start = i + 1;
    } else if (ch == '\t') {
      JsonEncoderPutBytes(encoder, text + start, i - start);
      JsonEncoderPutBytes(encoder, "\\t", 2);
      start = i + 1;
    } else if (ch < 0x20) {
      JsonEncoderPutBytes(encoder, text + start, i - start);
      JsonEncoderPutBytes(encoder, "\\u00", 4);
      JsonEncoderPutByte(encoder, hex[ch >> 4]);
      JsonEncoderPutByte(encoder, hex[ch & 15]);
      start = i + 1;
    }
  }
  JsonEncoderPutBytes(encoder, text + start, length - start);
  JsonEncoderPutByte(encoder, '"');
}

U0 JsonEncoderInit(CJsonEncoder *encoder, U8 *data, I64 capacity = 0)
{
  encoder->data = data;
  encoder->capacity = capacity;
  encoder->length = 0;
  encoder->error = JSON_ENCODE_OK;
  encoder->depth = 0;
  encoder->object_bits = 0;
  encoder->comma_bits = 0;
  encoder->value_bits = 0;
  encoder->root_written = FALSE;
  if (data && capacity < 1)
    encoder->error = JSON_ENCODE_NO_SPACE;
  if (data && capacity > 0)
    data[0] = 0;
}

Bool JsonEncodeKeyN(CJsonEncoder *encoder, U8 *key, I64 length)
{
  U64 bit;

  if (!encoder || length < 0 || length && !key) {
    if (encoder)
      JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_ARGUMENT);
    return FALSE;
  }
  if (JsonEncoderFatal(encoder))
    return FALSE;
  if (length && !JsonEncoderUtf8(key, length)) {
    JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_UTF8);
    return FALSE;
  }
  if (!encoder->depth) {
    JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_STATE);
    return FALSE;
  }
  bit = JsonEncoderLevelBit(encoder);
  if (!(encoder->object_bits & bit) || encoder->value_bits & bit) {
    JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_STATE);
    return FALSE;
  }
  if (encoder->comma_bits & bit)
    JsonEncoderPutByte(encoder, ',');
  JsonEncoderQuoteUnchecked(encoder, key, length);
  JsonEncoderPutByte(encoder, ':');
  encoder->value_bits |= bit;
  return !encoder->error;
}

Bool JsonEncodeKey(CJsonEncoder *encoder, U8 *key)
{
  if (!key) {
    if (encoder)
      JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_ARGUMENT);
    return FALSE;
  }
  return JsonEncodeKeyN(encoder, key, StrLen(key));
}

Bool JsonEncodeObjectStart(CJsonEncoder *encoder)
{
  U64 bit;

  if (!encoder)
    return FALSE;
  if (encoder->depth >= JSON_ENCODER_MAX_DEPTH) {
    JsonEncoderSetError(encoder, JSON_ENCODE_MAX_DEPTH);
    return FALSE;
  }
  if (!JsonEncoderBeforeValue(encoder))
    return FALSE;
  JsonEncoderPutByte(encoder, '{');
  encoder->depth++;
  bit = JsonEncoderLevelBit(encoder);
  encoder->object_bits |= bit;
  encoder->comma_bits &= ~bit;
  encoder->value_bits &= ~bit;
  return !encoder->error;
}

Bool JsonEncodeObjectEnd(CJsonEncoder *encoder)
{
  U64 bit;

  if (!encoder || !encoder->depth) {
    if (encoder)
      JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_STATE);
    return FALSE;
  }
  bit = JsonEncoderLevelBit(encoder);
  if (!(encoder->object_bits & bit) || encoder->value_bits & bit) {
    JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_STATE);
    return FALSE;
  }
  JsonEncoderPutByte(encoder, '}');
  encoder->object_bits &= ~bit;
  encoder->comma_bits &= ~bit;
  encoder->value_bits &= ~bit;
  encoder->depth--;
  return !encoder->error;
}

Bool JsonEncodeArrayStart(CJsonEncoder *encoder)
{
  U64 bit;

  if (!encoder)
    return FALSE;
  if (encoder->depth >= JSON_ENCODER_MAX_DEPTH) {
    JsonEncoderSetError(encoder, JSON_ENCODE_MAX_DEPTH);
    return FALSE;
  }
  if (!JsonEncoderBeforeValue(encoder))
    return FALSE;
  JsonEncoderPutByte(encoder, '[');
  encoder->depth++;
  bit = JsonEncoderLevelBit(encoder);
  encoder->object_bits &= ~bit;
  encoder->comma_bits &= ~bit;
  encoder->value_bits &= ~bit;
  return !encoder->error;
}

Bool JsonEncodeArrayEnd(CJsonEncoder *encoder)
{
  U64 bit;

  if (!encoder || !encoder->depth) {
    if (encoder)
      JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_STATE);
    return FALSE;
  }
  bit = JsonEncoderLevelBit(encoder);
  if (encoder->object_bits & bit) {
    JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_STATE);
    return FALSE;
  }
  JsonEncoderPutByte(encoder, ']');
  encoder->comma_bits &= ~bit;
  encoder->value_bits &= ~bit;
  encoder->depth--;
  return !encoder->error;
}

Bool JsonEncodeStringN(CJsonEncoder *encoder, U8 *text, I64 length)
{
  if (!encoder || length < 0 || length && !text) {
    if (encoder)
      JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_ARGUMENT);
    return FALSE;
  }
  if (length && !JsonEncoderUtf8(text, length)) {
    JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_UTF8);
    return FALSE;
  }
  if (!JsonEncoderBeforeValue(encoder))
    return FALSE;
  JsonEncoderQuoteUnchecked(encoder, text, length);
  return !encoder->error;
}

Bool JsonEncodeString(CJsonEncoder *encoder, U8 *text)
{
  if (!text) {
    if (encoder)
      JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_ARGUMENT);
    return FALSE;
  }
  return JsonEncodeStringN(encoder, text, StrLen(text));
}

Bool JsonEncodeI64(CJsonEncoder *encoder, I64 value)
{
  U8 digits[24];
  I64 i = sizeof(digits);
  U64 magnitude;

  if (!encoder)
    return FALSE;
  if (!JsonEncoderBeforeValue(encoder))
    return FALSE;
  if (value == I64_MIN) {
    JsonEncoderPutBytes(encoder, "-9223372036854775808", 20);
    return !encoder->error;
  }
  if (value < 0)
    magnitude = -value;
  else
    magnitude = value;
  digits[--i] = '0' + magnitude % 10;
  magnitude /= 10;
  while (magnitude) {
    digits[--i] = '0' + magnitude % 10;
    magnitude /= 10;
  }
  if (value < 0)
    digits[--i] = '-';
  JsonEncoderPutBytes(encoder, digits + i, sizeof(digits) - i);
  return !encoder->error;
}

Bool JsonEncodeF64(CJsonEncoder *encoder, F64 value)
{
  U8 number[64];
  I64 length;

  if (!encoder)
    return FALSE;
  StrPrint(number, "%.17g", value);
  length = StrLen(number);
  if (!length || number[0] == 'n' || number[0] == 'N' ||
    number[0] == 'i' || number[0] == 'I' ||
    number[0] == '-' && (number[1] == 'n' || number[1] == 'N' ||
      number[1] == 'i' || number[1] == 'I')) {
        JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_NUMBER);
        return FALSE;
      }
  if (!JsonEncoderBeforeValue(encoder))
    return FALSE;
  JsonEncoderPutBytes(encoder, number, length);
  return !encoder->error;
}

Bool JsonEncodeBool(CJsonEncoder *encoder, Bool value)
{
  if (!encoder)
    return FALSE;
  if (!JsonEncoderBeforeValue(encoder))
    return FALSE;
  if (value)
    JsonEncoderPutBytes(encoder, "true", 4);
  else
    JsonEncoderPutBytes(encoder, "false", 5);
  return !encoder->error;
}

Bool JsonEncodeNull(CJsonEncoder *encoder)
{
  if (!encoder)
    return FALSE;
  if (!JsonEncoderBeforeValue(encoder))
    return FALSE;
  JsonEncoderPutBytes(encoder, "null", 4);
  return !encoder->error;
}

I64 JsonEncoderFinish(CJsonEncoder *encoder)
{
  I64 terminator;

  if (!encoder)
    return -1;
  if (encoder->depth || !encoder->root_written)
    JsonEncoderSetError(encoder, JSON_ENCODE_INVALID_STATE);
  if (encoder->data && encoder->capacity > 0) {
    terminator = encoder->length;
    if (terminator >= encoder->capacity)
      terminator = encoder->capacity - 1;
    encoder->data[terminator] = 0;
  }
  if (encoder->error)
    return -1;
  return encoder->length;
}

U8 *JsonEncodeErrorName(I64 error)
{
  switch (error) {
    case JSON_ENCODE_OK:
      return "ok";
    case JSON_ENCODE_INVALID_ARGUMENT:
      return "invalid argument";
    case JSON_ENCODE_NO_SPACE:
      return "output buffer is too small";
    case JSON_ENCODE_INVALID_STATE:
      return "invalid encoder state";
    case JSON_ENCODE_INVALID_UTF8:
      return "invalid UTF-8";
    case JSON_ENCODE_INVALID_NUMBER:
      return "number is not finite";
    case JSON_ENCODE_MAX_DEPTH:
      return "maximum nesting depth exceeded";
  }
  return "unknown error";
}

#endif
