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
- Include `markdown.hc` for the Markdown layout engine (titles, rules,
  tables, code blocks, emphasis, wrapping) that streams text and style
  events to callbacks, and `md_ansi.hc` for the terminal backend that
  turns them into plain or ANSI colored text.

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

`markdown.hc` is a port of radare2's `r_str_md2txt` split in two: the
engine parses and lays out the text at `md.width` columns (75 by default)
and calls back with text slices and `MD_STYLE_*` on/off events (bold, italic,
strike, code, code block line, title and title mark with the heading level,
banner, rule, table border). It never allocates and never emits escape codes;
`md.utf8` selects box drawing for rules and tables and `md.slide_titles`
draws headings as full width bands. Each backend is a separate include, so a
program includes the engine plus the backend it wants and passes the
backend's callbacks to `MarkdownInit`. `md_ansi.hc` collects the output in a
`CStrBuf`, with `color` and `attrs` flags; a `lib/ui` backend can implement
the same two callbacks on top of widgets.

```c
#include "lib/text/markdown.hc"
#include "lib/text/md_ansi.hc"

CMdAnsi ansi;
CMarkdown md;
MdAnsiInit(&ansi, TRUE);           // colors; MdAnsiInit(&ansi, FALSE, FALSE) is plain
MarkdownInit(&md, &MdAnsiText, &MdAnsiStyle, &ansi);
md.utf8 = TRUE;
MarkdownRender(&md, "# Title\n\nHello **world**\n");
PutS(ansi.out.a);
MdAnsiFini(&ansi);
```

A backend is two functions reading `md->user`:

```c
U0 MyText(CMarkdown *md, CStrs *text) { ... }
U0 MyStyle(CMarkdown *md, I64 style, I64 on) { ... }

MarkdownInit(&md, &MyText, &MyStyle, my_widget);
MarkdownRenderStrs(&md, &slice);   // any [a, b) slice, no NUL needed
```
