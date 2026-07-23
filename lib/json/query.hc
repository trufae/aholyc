#ifndef AHOLYC_LIB_JSON_QUERY_HC
#define AHOLYC_LIB_JSON_QUERY_HC

// Constant-memory lookup over zero-copy values from decode.hc.
//
//   CJsonValue item;
//   JsonArrayGet(&array, 3, &item);
//   JsonPathGet(&root, "$.users[2].name", &item);
//
// Paths support an optional '$', dot members, decimal array indexes, and
// quoted bracket members: $["a.b"][0]. Quoted bracket names are literal UTF-8
// (backslash escapes in the path itself are intentionally not interpreted).

#include "decode.hc"

Bool JsonArrayGet(CJsonValue *array, I64 index, CJsonValue *result)
{
  CJsonDecoder decoder;
  CJsonValue value;
  I64 current = 0;

  if (!array || !result || array->type != JSON_TYPE_ARRAY || index < 0)
    return FALSE;
  JsonDecoderInit(&decoder, array->data, array->length);
  decoder.offset = 1;
  JsonDecodeSkipSpace(&decoder);
  if (decoder.offset >= decoder.length ||
    decoder.data[decoder.offset] == ']')
    return FALSE;
  for (;;) {
    if (!JsonDecodeScanValue(&decoder, 0, &value))
      return FALSE;
    if (current++ == index) {
      *result = value;
      return TRUE;
    }
    JsonDecodeSkipSpace(&decoder);
    if (decoder.offset >= decoder.length ||
      decoder.data[decoder.offset] == ']')
      return FALSE;
    decoder.offset++;
  }
}

I64 JsonArrayLength(CJsonValue *array)
{
  CJsonDecoder decoder;
  CJsonValue value;
  I64 count = 0;

  if (!array || array->type != JSON_TYPE_ARRAY)
    return -1;
  JsonDecoderInit(&decoder, array->data, array->length);
  decoder.offset = 1;
  JsonDecodeSkipSpace(&decoder);
  if (decoder.offset < decoder.length &&
    decoder.data[decoder.offset] == ']')
    return 0;
  for (;;) {
    if (!JsonDecodeScanValue(&decoder, 0, &value))
      return -1;
    count++;
    JsonDecodeSkipSpace(&decoder);
    if (decoder.offset >= decoder.length)
      return -1;
    if (decoder.data[decoder.offset] == ']')
      return count;
    decoder.offset++;
  }
}

Bool JsonObjectGetN(CJsonValue *object, U8 *key, I64 key_length,
  CJsonValue *result)
{
  CJsonDecoder decoder;
  CJsonValue name;
  CJsonValue value;

  if (!object || !result || object->type != JSON_TYPE_OBJECT || !key ||
    key_length < 0)
    return FALSE;
  JsonDecoderInit(&decoder, object->data, object->length);
  decoder.offset = 1;
  JsonDecodeSkipSpace(&decoder);
  if (decoder.offset >= decoder.length ||
    decoder.data[decoder.offset] == '}')
    return FALSE;
  for (;;) {
    name.data = decoder.data + decoder.offset;
    name.type = JSON_TYPE_STRING;
    if (!JsonDecodeScanString(&decoder))
      return FALSE;
    name.length = decoder.data + decoder.offset - name.data;
    JsonDecodeSkipSpace(&decoder);
    decoder.offset++;
    if (!JsonDecodeScanValue(&decoder, 0, &value))
      return FALSE;
    if (JsonValueStringEqualsN(&name, key, key_length)) {
      *result = value;
      return TRUE;
    }
    JsonDecodeSkipSpace(&decoder);
    if (decoder.offset >= decoder.length ||
      decoder.data[decoder.offset] == '}')
      return FALSE;
    decoder.offset++;
    JsonDecodeSkipSpace(&decoder);
  }
}

Bool JsonObjectGet(CJsonValue *object, U8 *key, CJsonValue *result)
{
  if (!key)
    return FALSE;
  return JsonObjectGetN(object, key, StrLen(key), result);
}

I64 JsonObjectLength(CJsonValue *object)
{
  CJsonDecoder decoder;
  CJsonValue value;
  I64 count = 0;

  if (!object || object->type != JSON_TYPE_OBJECT)
    return -1;
  JsonDecoderInit(&decoder, object->data, object->length);
  decoder.offset = 1;
  JsonDecodeSkipSpace(&decoder);
  if (decoder.offset < decoder.length &&
    decoder.data[decoder.offset] == '}')
    return 0;
  for (;;) {
    if (!JsonDecodeScanString(&decoder))
      return -1;
    JsonDecodeSkipSpace(&decoder);
    decoder.offset++;
    if (!JsonDecodeScanValue(&decoder, 0, &value))
      return -1;
    count++;
    JsonDecodeSkipSpace(&decoder);
    if (decoder.offset >= decoder.length)
      return -1;
    if (decoder.data[decoder.offset] == '}')
      return count;
    decoder.offset++;
    JsonDecodeSkipSpace(&decoder);
  }
}

Bool JsonPathGetN(CJsonValue *root, U8 *path, I64 path_length,
  CJsonValue *result)
{
  CJsonValue current;
  I64 i = 0;
  I64 start;
  I64 index;
  I64 digit;
  U8 quote;

  if (!root || !path || path_length < 0 || !result)
    return FALSE;
  current = *root;
  if (i < path_length && path[i] == '$')
    i++;

  while (i < path_length) {
    if (path[i] == '.') {
      i++;
      start = i;
      while (i < path_length && path[i] != '.' && path[i] != '[')
        i++;
      if (i == start ||
        !JsonObjectGetN(&current, path + start, i - start, &current))
        return FALSE;
    } else if (path[i] == '[') {
      i++;
      while (i < path_length && JsonDecodeIsSpace(path[i]))
        i++;
      if (i >= path_length)
        return FALSE;
      if (path[i] == '"' || path[i] == '\'') {
        quote = path[i++];
        start = i;
        while (i < path_length && path[i] != quote) {
          if (path[i] == '\\')
            return FALSE;
          i++;
        }
        if (i >= path_length ||
          !JsonObjectGetN(&current, path + start, i - start, &current))
          return FALSE;
        i++;
      } else {
        if (path[i] < '0' || path[i] > '9')
          return FALSE;
        index = 0;
        while (i < path_length && path[i] >= '0' && path[i] <= '9') {
          digit = path[i++] - '0';
          if (index > (I64_MAX - digit) / 10)
            return FALSE;
          index = index * 10 + digit;
        }
        if (!JsonArrayGet(&current, index, &current))
          return FALSE;
      }
      while (i < path_length && JsonDecodeIsSpace(path[i]))
        i++;
      if (i >= path_length || path[i++] != ']')
        return FALSE;
      if (i < path_length && path[i] != '.' && path[i] != '[')
        return FALSE;
    } else {
      // A bare first member makes "users[0].name" valid as well as "$.users".
      start = i;
      while (i < path_length && path[i] != '.' && path[i] != '[')
        i++;
      if (i == start ||
        !JsonObjectGetN(&current, path + start, i - start, &current))
        return FALSE;
    }
  }
  *result = current;
  return TRUE;
}

Bool JsonPathGet(CJsonValue *root, U8 *path, CJsonValue *result)
{
  if (!path)
    return FALSE;
  return JsonPathGetN(root, path, StrLen(path), result);
}

#endif
