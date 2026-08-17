# Text library

The library is split by cost:

- Include `strs.hc` for allocation-free borrowed byte slices, bounded search,
  comparison, trimming, tokenization, and splitting.
- Include `strbuf.hc` for an allocating, small-string-optimized string
  builder. It inherits the byte-slice representation, and its first 63 payload
  bytes are stored inline.
- Include `utf8.HC` for three strict UTF-8 primitives: `Utf8DecodeRune`,
  `Utf8EncodeRune`, and `Utf8Valid`.
- Include `base64.hc` for RFC 4648 Base64 encoding and strict decoding. The
  caller-buffer APIs support a count-only pass and preserve binary data.
- Include `encoding.HC` for `CText`, UTF-16/32, ASCII, Latin-1, EBCDIC 037,
  transcoding, and Pascal-string adapters. It includes `utf8.HC` itself.

`CStrs` is the common non-owning representation. It stores the half-open byte
range `[a, b)`, so its length, consumption, and subslicing require no scan or
allocation. `MemChr`, `MemMem`, and `MemCmp` back the hot search and comparison
operations.

```c
#include "lib/text/strs.hc"

U8 input[3] = {'a', 0, 'b'};
CStrs bytes;
StrsInitN(&bytes, input, sizeof(input));
```

In the encoding APIs, all string lengths and positions are byte counts. No
encoding function allocates, and an explicit-length slice may contain NUL
bytes. `CText` inherits `CStrs` and adds only the encoding tag.

```c
#include "lib/text/encoding.HC"

U8 input[3] = {'a', 0, 'b'};
CStrs bytes;
CText text;
StrsInitN(&bytes, input, sizeof(input));
TextInitStrs(&text, &bytes);
```

Decode runes by advancing with the returned byte count:

```c
U8 *position = text.a;
I64 consumed;
I64 rune;

while (position < text.b) {
  consumed = TextDecodeRune(position, text.b - position,
    text.encoding, &rune);
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

Build strings incrementally with `CStrBuf`. `StrBufPutStrs` appends a slice,
and `StrBufPutN` preserves embedded NUL bytes. `StrBufTakeStrs` returns a slice
whose `a` pointer is a `Free`-able allocation and resets the builder for reuse.

```c
#include "lib/text/strbuf.hc"

CStrBuf buffer;
CStrs text;
StrBufInit(&buffer);
StrBufPutS(&buffer, "answer=");
StrBufPrintf(&buffer, "%d", 42);
StrBufTakeStrs(&buffer, &text);
Free(text.a);
```
