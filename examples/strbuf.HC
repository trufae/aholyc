#include "../lib/text/strbuf.hc"

U0 StrBufExample()
{
  CStrBuf buffer;
  U8 binary[3] = {'a', 0, 'b'};
  U8 *text;
  I64 length;
  I64 i;

  StrBufInit(&buffer);
  StrBufPutS(&buffer, "small=");
  StrBufPrintf(&buffer, "%d", 42);
  StrBufPutC(&buffer, ' ');
  for (i = 0; i < 12; i++)
    StrBufPutS(&buffer, "abcdefgh");
  StrBufPutN(&buffer, binary, sizeof(binary));
  StrBufPutN(&buffer, buffer.data, buffer.length);
  text = StrBufTake(&buffer, &length);
  "length=%d prefix=%.8s binary=%d,%d,%d reset=%d\n", length, text,
    text[length / 2 - 3], text[length / 2 - 2], text[length / 2 - 1],
    buffer.length;
  Free(text);
  StrBufFini(&buffer);
}

StrBufExample;
