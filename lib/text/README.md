# Text library

The library is split by cost:

- Include `strbuf.hc` for an allocating, small-string-optimized string
  builder. Its first 63 payload bytes are stored inline.
- Include `utf8.HC` for three strict UTF-8 primitives: `Utf8DecodeRune`,
  `Utf8EncodeRune`, and `Utf8Valid`.
- Include `encoding.HC` for `CText`, UTF-16/32, ASCII, Latin-1, EBCDIC 037,
  transcoding, and Pascal-string adapters. It includes `utf8.HC` itself.

In the encoding APIs, all string lengths and positions are byte counts. No
encoding function allocates, and an explicit-length buffer may contain NUL
bytes.

```c
#include "lib/text/encoding.HC"

U8 input[3] = {'a', 0, 'b'};
CText text;
TextInit(&text, input, sizeof(input));
```

Decode runes by advancing with the returned byte count:

```c
I64 position = 0;
I64 consumed;
I64 rune;

while (position < text.length) {
  consumed = TextDecodeRune(text.data + position,
    text.length - position, text.encoding, &rune);
  if (!consumed)
    break;
  position += consumed;
}
```

`TextConvert` returns the required byte count. Pass `NULL, 0` to size first;
with a short buffer it writes only complete runes and still returns the full
required count.

```c
I64 needed = TextConvert(&text, TEXT_ENCODING_UTF16_LE, NULL, 0);
U8 *utf16 = MAlloc(needed);
TextConvert(&text, TEXT_ENCODING_UTF16_LE, utf16, needed);
```

`TextInit(..., -1, encoding)` adapts an encoded NUL-terminated string.
`TextFromPascal` and `TextWritePascal` accept a 1, 2, or 4-byte length prefix
and an endianness flag instead of multiplying the API with format-specific
wrappers. Pascal lengths count payload bytes.

Build strings incrementally with `CStrBuf`. `StrBufPutN` preserves embedded
NUL bytes, and `StrBufTake` returns a `Free`-able allocation and resets the
builder for reuse.

```c
#include "lib/text/strbuf.hc"

CStrBuf buffer;
StrBufInit(&buffer);
StrBufPutS(&buffer, "answer=");
StrBufPrintf(&buffer, "%d", 42);
U8 *text = StrBufTake(&buffer);
Free(text);
```
