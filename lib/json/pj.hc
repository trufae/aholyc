#ifndef AHOLYC_LIB_JSON_PJ_HC
#define AHOLYC_LIB_JSON_PJ_HC

// Growable JSON builder in the style of radare2's PJ. Commas and colons are
// inserted automatically, strings are escaped by lib/json's encoder, and the
// result lives in a CStrBuf so documents of any size can be composed without
// a sizing pass. Every call returns the builder so calls can be chained.
//
//   CPj *pj = PjNew;
//   PjO(pj);
//   PjKs(pj, "name", "aholyc");
//   PjKa(pj, "tags");
//   PjS(pj, "holyc");
//   PjEnd(pj);
//   PjEnd(pj);
//   U8 *json = PjDrain(pj);   // {"name":"aholyc","tags":["holyc"]}
//
// A builder used without an enclosing PjO/PjA emits bare comma-separated
// values, which PjJ can splice into another document later. Use the
// heap-free CJsonEncoder from encode.hc when the output must land in a
// caller-owned buffer.

#include "encode.hc"
#include "../text/strbuf.hc"

#define PJ_MAX_DEPTH 128

class CPj
{
  CStrBuf sb;
  Bool is_first;
  Bool is_key;
  I64 level;
  U8 braces[PJ_MAX_DEPTH];
};

CPj *PjNew()
{
  CPj *pj = CAlloc(sizeof(CPj));

  StrBufInit(&pj->sb);
  pj->is_first = TRUE;
  return pj;
}

U0 PjFree(CPj *pj)
{
  if (pj) {
    StrBufFini(&pj->sb);
    Free(pj);
  }
}

U0 PjReset(CPj *pj)
{
  StrBufClear(&pj->sb);
  pj->is_first = TRUE;
  pj->is_key = FALSE;
  pj->level = 0;
}

// Borrowed view of the JSON text built so far.
U8 *PjString(CPj *pj)
{
  return pj->sb.a;
}

// Take the JSON text and free the builder. Caller frees the result.
U8 *PjDrain(CPj *pj)
{
  U8 *text = StrBufTake(&pj->sb);

  PjFree(pj);
  return text;
}

U0 PjRaw(CPj *pj, U8 *text)
{
  StrBufPutS(&pj->sb, text);
}

U0 PjComma(CPj *pj)
{
  if (!pj->is_key && !pj->is_first)
    StrBufPutC(&pj->sb, ',');
  pj->is_first = FALSE;
  pj->is_key = FALSE;
}

CPj *PjBegin(CPj *pj, U8 open, U8 close)
{
  PjComma(pj);
  if (pj->level < PJ_MAX_DEPTH) {
    StrBufPutC(&pj->sb, open);
    pj->braces[pj->level++] = close;
    pj->is_first = TRUE;
  }
  return pj;
}

CPj *PjO(CPj *pj)
{
  return PjBegin(pj, '{', '}');
}

CPj *PjA(CPj *pj)
{
  return PjBegin(pj, '[', ']');
}

CPj *PjEnd(CPj *pj)
{
  if (pj->level > 0) {
    StrBufPutC(&pj->sb, pj->braces[--pj->level]);
    pj->is_first = FALSE;
  }
  pj->is_key = FALSE;
  return pj;
}

// Append a JSON string using the escaper from encode.hc: a sizing pass, then
// the real write straight into the reserved tail of the buffer.
CPj *PjS(CPj *pj, U8 *text)
{
  CJsonEncoder encoder;
  I64 length;

  PjComma(pj);
  JsonEncoderInit(&encoder, NULL, 0);
  JsonEncodeString(&encoder, text);
  length = JsonEncoderFinish(&encoder);
  if (length > 0 && StrBufReserve(&pj->sb, length)) {
    JsonEncoderInit(&encoder, pj->sb.b, length + 1);
    JsonEncodeString(&encoder, text);
    JsonEncoderFinish(&encoder);
    pj->sb.b += length;
  } else {
    PjRaw(pj, "\"\"");
  }
  return pj;
}

// Append raw JSON text as one value; the caller guarantees it is valid.
CPj *PjJ(CPj *pj, U8 *json)
{
  if (json && *json) {
    PjComma(pj);
    PjRaw(pj, json);
  }
  return pj;
}

CPj *PjN(CPj *pj, I64 number)
{
  PjComma(pj);
  StrBufPrintf(&pj->sb, "%d", number);
  return pj;
}

CPj *PjD(CPj *pj, F64 number)
{
  CJsonEncoder encoder;
  U8 text[64];

  JsonEncoderInit(&encoder, text, sizeof(text));
  JsonEncodeF64(&encoder, number);
  if (JsonEncoderFinish(&encoder) < 0)
    return PjS(pj, "NaN");
  return PjJ(pj, text);
}

CPj *PjB(CPj *pj, Bool value)
{
  if (value)
    return PjJ(pj, "true");
  return PjJ(pj, "false");
}

CPj *PjNull(CPj *pj)
{
  return PjJ(pj, "null");
}

CPj *PjK(CPj *pj, U8 *key)
{
  pj->is_key = FALSE;
  PjS(pj, key);
  StrBufPutC(&pj->sb, ':');
  pj->is_first = FALSE;
  pj->is_key = TRUE;
  return pj;
}

CPj *PjKs(CPj *pj, U8 *key, U8 *value)
{
  return PjS(PjK(pj, key), value);
}

CPj *PjKn(CPj *pj, U8 *key, I64 number)
{
  return PjN(PjK(pj, key), number);
}

CPj *PjKd(CPj *pj, U8 *key, F64 number)
{
  return PjD(PjK(pj, key), number);
}

CPj *PjKb(CPj *pj, U8 *key, Bool value)
{
  return PjB(PjK(pj, key), value);
}

CPj *PjKnull(CPj *pj, U8 *key)
{
  return PjNull(PjK(pj, key));
}

CPj *PjKj(CPj *pj, U8 *key, U8 *json)
{
  return PjJ(PjK(pj, key), json);
}

CPj *PjKo(CPj *pj, U8 *key)
{
  return PjO(PjK(pj, key));
}

CPj *PjKa(CPj *pj, U8 *key)
{
  return PjA(PjK(pj, key));
}

#endif
