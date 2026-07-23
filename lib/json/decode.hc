#ifndef AHOLYC_LIB_JSON_DECODE_HC
#define AHOLYC_LIB_JSON_DECODE_HC

// Heap-free, zero-copy JSON decoder.
//
// CJsonValue values point into the input buffer, so the buffer must remain
// alive and unchanged while values are used. Strings remain JSON-escaped in
// their slice; JsonValueCopyString decodes them into a caller-owned buffer.
//
//   CJsonDecoder decoder;
//   CJsonValue root;
//   JsonDecoderInit(&decoder, text);
//   if (!JsonDecode(&decoder, &root))
//     "JSON error at %d: %s\n", decoder.error_offset,
//       JsonDecodeErrorName(decoder.error);
//
// Parsing uses no heap. Its only variable storage is the native call stack,
// bounded by decoder.max_depth.

#define JSON_TYPE_INVALID 0
#define JSON_TYPE_NULL 1
#define JSON_TYPE_BOOL 2
#define JSON_TYPE_NUMBER 3
#define JSON_TYPE_STRING 4
#define JSON_TYPE_ARRAY 5
#define JSON_TYPE_OBJECT 6

#define JSON_DECODE_OK 0
#define JSON_DECODE_INVALID_ARGUMENT 1
#define JSON_DECODE_UNEXPECTED_END 2
#define JSON_DECODE_UNEXPECTED_TOKEN 3
#define JSON_DECODE_TRAILING_DATA 4
#define JSON_DECODE_INVALID_STRING 5
#define JSON_DECODE_INVALID_ESCAPE 6
#define JSON_DECODE_INVALID_UNICODE 7
#define JSON_DECODE_INVALID_UTF8 8
#define JSON_DECODE_INVALID_NUMBER 9
#define JSON_DECODE_EXPECTED_COLON 10
#define JSON_DECODE_EXPECTED_COMMA 11
#define JSON_DECODE_MAX_DEPTH 12

#ifndef JSON_DEFAULT_MAX_DEPTH
#define JSON_DEFAULT_MAX_DEPTH 128
#endif

class CJsonValue
{
  U8 *data;
  I64 length;
  I64 type;
};

class CJsonDecoder
{
  U8 *data;
  I64 length;
  I64 offset;
  I64 error;
  I64 error_offset;
  I64 max_depth;
};

Bool JsonDecodeFail(CJsonDecoder *decoder, I64 error)
{
  if (!decoder->error) {
    decoder->error = error;
    decoder->error_offset = decoder->offset;
  }
  return FALSE;
}

Bool JsonDecodeIsSpace(U8 ch)
{
  return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
}

U0 JsonDecodeSkipSpace(CJsonDecoder *decoder)
{
  while (decoder->offset < decoder->length &&
    JsonDecodeIsSpace(decoder->data[decoder->offset]))
    decoder->offset++;
}

I64 JsonDecodeHex(U8 ch)
{
  if (ch >= '0' && ch <= '9')
    return ch - '0';
  if (ch >= 'a' && ch <= 'f')
    return ch - 'a' + 10;
  if (ch >= 'A' && ch <= 'F')
    return ch - 'A' + 10;
  return -1;
}

Bool JsonDecodeUtf8(CJsonDecoder *decoder)
{
  U8 *data = decoder->data;
  I64 i = decoder->offset;
  I64 length = decoder->length;
  U8 first;
  U8 second;

  if (i >= length)
    return JsonDecodeFail(decoder, JSON_DECODE_UNEXPECTED_END);
  first = data[i];
  if (first < 0x80) {
    decoder->offset++;
    return TRUE;
  }
  if (first >= 0xC2 && first <= 0xDF) {
    if (i + 1 >= length || data[i + 1] < 0x80 || data[i + 1] > 0xBF)
      return JsonDecodeFail(decoder, JSON_DECODE_INVALID_UTF8);
    decoder->offset += 2;
    return TRUE;
  }
  if (first >= 0xE0 && first <= 0xEF) {
    if (i + 2 >= length)
      return JsonDecodeFail(decoder, JSON_DECODE_INVALID_UTF8);
    second = data[i + 1];
    if (second < 0x80 || second > 0xBF ||
      data[i + 2] < 0x80 || data[i + 2] > 0xBF)
      return JsonDecodeFail(decoder, JSON_DECODE_INVALID_UTF8);
    if (first == 0xE0 && second < 0xA0)
      return JsonDecodeFail(decoder, JSON_DECODE_INVALID_UTF8);
    if (first == 0xED && second >= 0xA0)
      return JsonDecodeFail(decoder, JSON_DECODE_INVALID_UTF8);
    decoder->offset += 3;
    return TRUE;
  }
  if (first >= 0xF0 && first <= 0xF4) {
    if (i + 3 >= length)
      return JsonDecodeFail(decoder, JSON_DECODE_INVALID_UTF8);
    second = data[i + 1];
    if (second < 0x80 || second > 0xBF ||
      data[i + 2] < 0x80 || data[i + 2] > 0xBF ||
      data[i + 3] < 0x80 || data[i + 3] > 0xBF)
      return JsonDecodeFail(decoder, JSON_DECODE_INVALID_UTF8);
    if (first == 0xF0 && second < 0x90)
      return JsonDecodeFail(decoder, JSON_DECODE_INVALID_UTF8);
    if (first == 0xF4 && second > 0x8F)
      return JsonDecodeFail(decoder, JSON_DECODE_INVALID_UTF8);
    decoder->offset += 4;
    return TRUE;
  }
  return JsonDecodeFail(decoder, JSON_DECODE_INVALID_UTF8);
}

Bool JsonDecodeScanHex4(CJsonDecoder *decoder, I64 *codepoint)
{
  I64 i;
  I64 digit;
  I64 value = 0;

  if (decoder->offset + 4 > decoder->length)
    return JsonDecodeFail(decoder, JSON_DECODE_INVALID_UNICODE);
  for (i = 0; i < 4; i++) {
    digit = JsonDecodeHex(decoder->data[decoder->offset++]);
    if (digit < 0)
      return JsonDecodeFail(decoder, JSON_DECODE_INVALID_UNICODE);
    value = value << 4 | digit;
  }
  *codepoint = value;
  return TRUE;
}

Bool JsonDecodeScanString(CJsonDecoder *decoder)
{
  U8 ch;
  I64 high;
  I64 low;
  Bool simple_escape;

  if (decoder->offset >= decoder->length ||
    decoder->data[decoder->offset] != '"')
    return JsonDecodeFail(decoder, JSON_DECODE_UNEXPECTED_TOKEN);
  decoder->offset++;
  while (decoder->offset < decoder->length) {
    ch = decoder->data[decoder->offset];
    if (ch == '"') {
      decoder->offset++;
      return TRUE;
    }
    if (ch < 0x20)
      return JsonDecodeFail(decoder, JSON_DECODE_INVALID_STRING);
    if (ch != '\\') {
      if (!JsonDecodeUtf8(decoder))
        return FALSE;
    } else {
      decoder->offset++;
      if (decoder->offset >= decoder->length)
        return JsonDecodeFail(decoder, JSON_DECODE_INVALID_ESCAPE);
      ch = decoder->data[decoder->offset++];
      simple_escape = ch == '"' || ch == '\\' || ch == '/' || ch == 'b' ||
        ch == 'f' || ch == 'n' || ch == 'r' || ch == 't';
      if (!simple_escape) {
        if (ch != 'u') {
          return JsonDecodeFail(decoder, JSON_DECODE_INVALID_ESCAPE);
        } else if (!JsonDecodeScanHex4(decoder, &high)) {
          return FALSE;
        } else if (high >= 0xD800 && high <= 0xDBFF) {
          if (decoder->offset + 2 > decoder->length ||
            decoder->data[decoder->offset] != '\\' ||
            decoder->data[decoder->offset + 1] != 'u')
            return JsonDecodeFail(decoder, JSON_DECODE_INVALID_UNICODE);
          decoder->offset += 2;
          if (!JsonDecodeScanHex4(decoder, &low))
            return FALSE;
          if (low < 0xDC00 || low > 0xDFFF)
            return JsonDecodeFail(decoder, JSON_DECODE_INVALID_UNICODE);
        } else if (high >= 0xDC00 && high <= 0xDFFF) {
          return JsonDecodeFail(decoder, JSON_DECODE_INVALID_UNICODE);
        }
      }
    }
  }
  return JsonDecodeFail(decoder, JSON_DECODE_UNEXPECTED_END);
}

Bool JsonDecodeScanNumber(CJsonDecoder *decoder)
{
  I64 start = decoder->offset;
  U8 ch;

  if (decoder->offset < decoder->length &&
    decoder->data[decoder->offset] == '-')
    decoder->offset++;
  if (decoder->offset >= decoder->length)
    return JsonDecodeFail(decoder, JSON_DECODE_INVALID_NUMBER);

  ch = decoder->data[decoder->offset];
  if (ch == '0') {
    decoder->offset++;
    if (decoder->offset < decoder->length &&
      decoder->data[decoder->offset] >= '0' &&
      decoder->data[decoder->offset] <= '9')
      return JsonDecodeFail(decoder, JSON_DECODE_INVALID_NUMBER);
  } else if (ch >= '1' && ch <= '9') {
    while (decoder->offset < decoder->length &&
      decoder->data[decoder->offset] >= '0' &&
      decoder->data[decoder->offset] <= '9')
      decoder->offset++;
  } else {
    return JsonDecodeFail(decoder, JSON_DECODE_INVALID_NUMBER);
  }

  if (decoder->offset < decoder->length &&
    decoder->data[decoder->offset] == '.') {
      decoder->offset++;
      if (decoder->offset >= decoder->length ||
        decoder->data[decoder->offset] < '0' ||
        decoder->data[decoder->offset] > '9')
        return JsonDecodeFail(decoder, JSON_DECODE_INVALID_NUMBER);
      while (decoder->offset < decoder->length &&
        decoder->data[decoder->offset] >= '0' &&
        decoder->data[decoder->offset] <= '9')
        decoder->offset++;
    }

  if (decoder->offset < decoder->length &&
    (decoder->data[decoder->offset] == 'e' ||
      decoder->data[decoder->offset] == 'E')) {
        decoder->offset++;
        if (decoder->offset < decoder->length &&
          (decoder->data[decoder->offset] == '+' ||
            decoder->data[decoder->offset] == '-'))
          decoder->offset++;
        if (decoder->offset >= decoder->length ||
          decoder->data[decoder->offset] < '0' ||
          decoder->data[decoder->offset] > '9')
          return JsonDecodeFail(decoder, JSON_DECODE_INVALID_NUMBER);
        while (decoder->offset < decoder->length &&
          decoder->data[decoder->offset] >= '0' &&
          decoder->data[decoder->offset] <= '9')
          decoder->offset++;
      }
  if (decoder->offset == start)
    return JsonDecodeFail(decoder, JSON_DECODE_INVALID_NUMBER);
  return TRUE;
}

Bool JsonDecodeLiteral(CJsonDecoder *decoder, U8 *literal)
{
  I64 size = StrLen(literal);

  if (decoder->offset + size > decoder->length ||
    MemCmp(decoder->data + decoder->offset, literal, size))
    return JsonDecodeFail(decoder, JSON_DECODE_UNEXPECTED_TOKEN);
  decoder->offset += size;
  return TRUE;
}

Bool JsonDecodeScanValue(CJsonDecoder *decoder, I64 depth, CJsonValue *value)
{
  I64 start;
  I64 type;
  U8 ch;
  CJsonValue child;

  JsonDecodeSkipSpace(decoder);
  if (decoder->offset >= decoder->length)
    return JsonDecodeFail(decoder, JSON_DECODE_UNEXPECTED_END);
  start = decoder->offset;
  ch = decoder->data[decoder->offset];

  if (ch == '"') {
    type = JSON_TYPE_STRING;
    if (!JsonDecodeScanString(decoder))
      return FALSE;
  } else if (ch == '-' || ch >= '0' && ch <= '9') {
    type = JSON_TYPE_NUMBER;
    if (!JsonDecodeScanNumber(decoder))
      return FALSE;
  } else if (ch == 'n') {
    type = JSON_TYPE_NULL;
    if (!JsonDecodeLiteral(decoder, "null"))
      return FALSE;
  } else if (ch == 't') {
    type = JSON_TYPE_BOOL;
    if (!JsonDecodeLiteral(decoder, "true"))
      return FALSE;
  } else if (ch == 'f') {
    type = JSON_TYPE_BOOL;
    if (!JsonDecodeLiteral(decoder, "false"))
      return FALSE;
  } else if (ch == '[') {
    type = JSON_TYPE_ARRAY;
    if (depth >= decoder->max_depth)
      return JsonDecodeFail(decoder, JSON_DECODE_MAX_DEPTH);
    decoder->offset++;
    JsonDecodeSkipSpace(decoder);
    if (decoder->offset < decoder->length &&
      decoder->data[decoder->offset] == ']') {
        decoder->offset++;
      } else {
        for (;;) {
          if (!JsonDecodeScanValue(decoder, depth + 1, &child))
            return FALSE;
          JsonDecodeSkipSpace(decoder);
          if (decoder->offset >= decoder->length)
            return JsonDecodeFail(decoder, JSON_DECODE_UNEXPECTED_END);
          ch = decoder->data[decoder->offset++];
          if (ch == ']')
            break;
          if (ch != ',')
            return JsonDecodeFail(decoder, JSON_DECODE_EXPECTED_COMMA);
          JsonDecodeSkipSpace(decoder);
        }
      }
  } else if (ch == '{') {
    type = JSON_TYPE_OBJECT;
    if (depth >= decoder->max_depth)
      return JsonDecodeFail(decoder, JSON_DECODE_MAX_DEPTH);
    decoder->offset++;
    JsonDecodeSkipSpace(decoder);
    if (decoder->offset < decoder->length &&
      decoder->data[decoder->offset] == '}') {
        decoder->offset++;
      } else {
        for (;;) {
          if (!JsonDecodeScanString(decoder))
            return FALSE;
          JsonDecodeSkipSpace(decoder);
          if (decoder->offset >= decoder->length ||
            decoder->data[decoder->offset] != ':')
            return JsonDecodeFail(decoder, JSON_DECODE_EXPECTED_COLON);
          decoder->offset++;
          if (!JsonDecodeScanValue(decoder, depth + 1, &child))
            return FALSE;
          JsonDecodeSkipSpace(decoder);
          if (decoder->offset >= decoder->length)
            return JsonDecodeFail(decoder, JSON_DECODE_UNEXPECTED_END);
          ch = decoder->data[decoder->offset++];
          if (ch == '}')
            break;
          if (ch != ',')
            return JsonDecodeFail(decoder, JSON_DECODE_EXPECTED_COMMA);
          JsonDecodeSkipSpace(decoder);
        }
      }
  } else {
    return JsonDecodeFail(decoder, JSON_DECODE_UNEXPECTED_TOKEN);
  }

  if (value) {
    value->data = decoder->data + start;
    value->length = decoder->offset - start;
    value->type = type;
  }
  return TRUE;
}

U0 JsonDecoderInit(CJsonDecoder *decoder, U8 *data, I64 length = -1)
{
  decoder->data = data;
  if (length < 0 && data)
    decoder->length = StrLen(data);
  else
    decoder->length = length;
  decoder->offset = 0;
  decoder->error = JSON_DECODE_OK;
  decoder->error_offset = 0;
  decoder->max_depth = JSON_DEFAULT_MAX_DEPTH;
}

Bool JsonDecode(CJsonDecoder *decoder, CJsonValue *value)
{
  if (!decoder || !value || !decoder->data || decoder->length < 0) {
    if (decoder)
      JsonDecodeFail(decoder, JSON_DECODE_INVALID_ARGUMENT);
    return FALSE;
  }
  decoder->offset = 0;
  decoder->error = JSON_DECODE_OK;
  decoder->error_offset = 0;
  if (decoder->max_depth < 1)
    decoder->max_depth = JSON_DEFAULT_MAX_DEPTH;
  if (!JsonDecodeScanValue(decoder, 0, value))
    return FALSE;
  JsonDecodeSkipSpace(decoder);
  if (decoder->offset != decoder->length)
    return JsonDecodeFail(decoder, JSON_DECODE_TRAILING_DATA);
  return TRUE;
}

Bool JsonValueAsBool(CJsonValue *value, Bool *result)
{
  if (!value || !result || value->type != JSON_TYPE_BOOL)
    return FALSE;
  *result = value->length == 4;
  return TRUE;
}

Bool JsonValueAsI64(CJsonValue *value, I64 *result)
{
  I64 i;
  I64 digit;
  I64 limit;
  I64 multiply_limit;
  I64 number = 0;
  Bool negative;

  if (!value || !result || value->type != JSON_TYPE_NUMBER ||
    value->length < 1)
    return FALSE;
  if (value->length == 20 &&
    !MemCmp(value->data, "-9223372036854775808", 20)) {
      *result = I64_MIN;
      return TRUE;
    }
  i = 0;
  negative = value->data[i] == '-';
  if (negative)
    i++;
  if (negative)
    limit = I64_MIN;
  else
    limit = -I64_MAX;
  multiply_limit = limit / 10;
  for (; i < value->length; i++) {
    if (value->data[i] < '0' || value->data[i] > '9')
      return FALSE;
    digit = value->data[i] - '0';
    if (number < multiply_limit)
      return FALSE;
    number *= 10;
    if (number < limit + digit)
      return FALSE;
    number -= digit;
  }
  if (negative)
    *result = number;
  else
    *result = -number;
  return TRUE;
}

F64 JsonDecodePow10(I64 exponent)
{
  F64 result = 1.0;
  F64 base;
  I64 power;

  if (exponent < 0) {
    base = 0.1;
    power = -exponent;
  } else {
    base = 10.0;
    power = exponent;
  }
  while (power) {
    if (power & 1)
      result *= base;
    base *= base;
    power >>= 1;
  }
  return result;
}

Bool JsonValueAsF64(CJsonValue *value, F64 *result)
{
  I64 i = 0;
  I64 kept = 0;
  I64 scale = 0;
  I64 exponent = 0;
  I64 exponent_sign = 1;
  I64 digit;
  Bool negative;
  Bool fraction = FALSE;
  Bool started = FALSE;
  F64 number = 0.0;

  if (!value || !result || value->type != JSON_TYPE_NUMBER ||
    value->length < 1)
    return FALSE;
  negative = value->data[i] == '-';
  if (negative)
    i++;

  while (i < value->length && value->data[i] != 'e' &&
    value->data[i] != 'E') {
      if (value->data[i] == '.') {
        fraction = TRUE;
        i++;
      } else {
        digit = value->data[i++] - '0';
        if (!started && !digit) {
          if (fraction && scale > -10000)
            scale--;
        } else {
          started = TRUE;
          if (kept < 18) {
            number = number * 10.0 + digit;
            kept++;
            if (fraction && scale > -10000)
              scale--;
          } else if (!fraction && scale < 10000) {
            scale++;
          }
        }
      }
    }

  if (i < value->length) {
    i++;
    if (i < value->length && value->data[i] == '+') {
      i++;
    } else if (i < value->length && value->data[i] == '-') {
      exponent_sign = -1;
      i++;
    }
    while (i < value->length) {
      digit = value->data[i++] - '0';
      if (exponent < 10000)
        exponent = exponent * 10 + digit;
      if (exponent > 10000)
        exponent = 10000;
    }
  }
  exponent *= exponent_sign;
  if (exponent > 0 && scale > 10000 - exponent)
    scale = 10000;
  else if (exponent < 0 && scale < -10000 - exponent)
    scale = -10000;
  else
    scale += exponent;

  if (!started) {
    if (negative)
      number = -number;
    *result = number;
    return TRUE;
  }
  number *= JsonDecodePow10(scale);
  if (negative)
    number = -number;
  if (number != number || number != 0.0 && number == number * 0.5)
    return FALSE;
  *result = number;
  return TRUE;
}

I64 JsonValueHex4(CJsonValue *value, I64 position)
{
  I64 i;
  I64 digit;
  I64 result = 0;

  if (position < 0 || position + 4 > value->length)
    return -1;
  for (i = 0; i < 4; i++) {
    digit = JsonDecodeHex(value->data[position + i]);
    if (digit < 0)
      return -1;
    result = result << 4 | digit;
  }
  return result;
}

I64 JsonValueCodepointBytes(I64 codepoint, U8 *bytes)
{
  if (codepoint <= 0x7F) {
    bytes[0] = codepoint;
    return 1;
  }
  if (codepoint <= 0x7FF) {
    bytes[0] = 0xC0 | codepoint >> 6;
    bytes[1] = 0x80 | codepoint & 0x3F;
    return 2;
  }
  if (codepoint <= 0xFFFF) {
    bytes[0] = 0xE0 | codepoint >> 12;
    bytes[1] = 0x80 | codepoint >> 6 & 0x3F;
    bytes[2] = 0x80 | codepoint & 0x3F;
    return 3;
  }
  bytes[0] = 0xF0 | codepoint >> 18;
  bytes[1] = 0x80 | codepoint >> 12 & 0x3F;
  bytes[2] = 0x80 | codepoint >> 6 & 0x3F;
  bytes[3] = 0x80 | codepoint & 0x3F;
  return 4;
}

Bool JsonValueCopyString(CJsonValue *value, U8 *output, I64 capacity,
  I64 *decoded_length = NULL)
{
  I64 i = 1;
  I64 out = 0;
  I64 j;
  I64 count;
  I64 codepoint;
  I64 low;
  U8 ch;
  U8 bytes[4];

  if (!value || value->type != JSON_TYPE_STRING || value->length < 2 ||
    capacity < 0)
    return FALSE;
  while (i < value->length - 1) {
    ch = value->data[i++];
    if (ch != '\\') {
      if (output && out < capacity)
        output[out] = ch;
      out++;
    } else {
      ch = value->data[i++];
      if (ch == 'u') {
        codepoint = JsonValueHex4(value, i);
        i += 4;
        if (codepoint >= 0xD800 && codepoint <= 0xDBFF) {
          i += 2;
          low = JsonValueHex4(value, i);
          i += 4;
          codepoint = 0x10000 + ((codepoint - 0xD800) << 10) +
            low - 0xDC00;
        }
        count = JsonValueCodepointBytes(codepoint, bytes);
        for (j = 0; j < count; j++) {
          if (output && out < capacity)
            output[out] = bytes[j];
          out++;
        }
      } else {
        if (ch == 'b')
          ch = '\b';
        else if (ch == 'f')
          ch = '\f';
        else if (ch == 'n')
          ch = '\n';
        else if (ch == 'r')
          ch = '\r';
        else if (ch == 't')
          ch = '\t';
        if (output && out < capacity)
          output[out] = ch;
        out++;
      }
    }
  }
  if (decoded_length)
    *decoded_length = out;
  if (!output)
    return TRUE;
  if (out >= capacity)
    return FALSE;
  output[out] = 0;
  return TRUE;
}

Bool JsonValueStringEqualsN(CJsonValue *value, U8 *text, I64 text_length)
{
  I64 i = 1;
  I64 text_offset = 0;
  I64 j;
  I64 count;
  I64 codepoint;
  I64 low;
  U8 ch;
  U8 bytes[4];

  if (!value || value->type != JSON_TYPE_STRING || value->length < 2 ||
    !text || text_length < 0)
    return FALSE;
  while (i < value->length - 1) {
    ch = value->data[i++];
    if (ch != '\\') {
      if (text_offset >= text_length || text[text_offset++] != ch)
        return FALSE;
    } else {
      ch = value->data[i++];
      if (ch == 'u') {
        codepoint = JsonValueHex4(value, i);
        i += 4;
        if (codepoint >= 0xD800 && codepoint <= 0xDBFF) {
          i += 2;
          low = JsonValueHex4(value, i);
          i += 4;
          codepoint = 0x10000 + ((codepoint - 0xD800) << 10) +
            low - 0xDC00;
        }
        count = JsonValueCodepointBytes(codepoint, bytes);
        for (j = 0; j < count; j++) {
          if (text_offset >= text_length ||
            text[text_offset++] != bytes[j])
            return FALSE;
        }
      } else {
        if (ch == 'b')
          ch = '\b';
        else if (ch == 'f')
          ch = '\f';
        else if (ch == 'n')
          ch = '\n';
        else if (ch == 'r')
          ch = '\r';
        else if (ch == 't')
          ch = '\t';
        if (text_offset >= text_length || text[text_offset++] != ch)
          return FALSE;
      }
    }
  }
  return text_offset == text_length;
}

Bool JsonValueStringEquals(CJsonValue *value, U8 *text)
{
  if (!text)
    return FALSE;
  return JsonValueStringEqualsN(value, text, StrLen(text));
}

U8 *JsonDecodeTypeName(I64 type)
{
  switch (type) {
    case JSON_TYPE_NULL:
      return "null";
    case JSON_TYPE_BOOL:
      return "boolean";
    case JSON_TYPE_NUMBER:
      return "number";
    case JSON_TYPE_STRING:
      return "string";
    case JSON_TYPE_ARRAY:
      return "array";
    case JSON_TYPE_OBJECT:
      return "object";
  }
  return "invalid";
}

U8 *JsonDecodeErrorName(I64 error)
{
  switch (error) {
    case JSON_DECODE_OK:
      return "ok";
    case JSON_DECODE_INVALID_ARGUMENT:
      return "invalid argument";
    case JSON_DECODE_UNEXPECTED_END:
      return "unexpected end of input";
    case JSON_DECODE_UNEXPECTED_TOKEN:
      return "unexpected token";
    case JSON_DECODE_TRAILING_DATA:
      return "trailing data";
    case JSON_DECODE_INVALID_STRING:
      return "invalid string";
    case JSON_DECODE_INVALID_ESCAPE:
      return "invalid escape";
    case JSON_DECODE_INVALID_UNICODE:
      return "invalid unicode escape";
    case JSON_DECODE_INVALID_UTF8:
      return "invalid UTF-8";
    case JSON_DECODE_INVALID_NUMBER:
      return "invalid number";
    case JSON_DECODE_EXPECTED_COLON:
      return "expected colon";
    case JSON_DECODE_EXPECTED_COMMA:
      return "expected comma or container end";
    case JSON_DECODE_MAX_DEPTH:
      return "maximum nesting depth exceeded";
  }
  return "unknown error";
}

#endif
