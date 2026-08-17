#include "../lib/text/strbuf.hc"

U0 StrBufExample()
{
  CStrBuf buffer;
  CStrs text;
  U8 binary[3] = {'a', 0, 'b'};
  I64 length;
  I64 i;

  StrBufInit(&buffer);
  StrBufPutS(&buffer, "small=");
  StrBufPrintf(&buffer, "%d", 42);
  StrBufPutC(&buffer, ' ');
  for (i = 0; i < 12; i++)
    StrBufPutS(&buffer, "abcdefgh");
  StrBufPutN(&buffer, binary, sizeof(binary));
  StrBufPutStrs(&buffer, &buffer);
  StrBufTakeStrs(&buffer, &text);
  length = StrsLen(&text);
  "length=%d prefix=%.8s binary=%d,%d,%d reset=%d\n", length, text.a,
    text.a[length / 2 - 3], text.a[length / 2 - 2],
    text.a[length / 2 - 1], StrsLen(&buffer);
  Free(text.a);
  StrBufFini(&buffer);
}

StrBufExample;
