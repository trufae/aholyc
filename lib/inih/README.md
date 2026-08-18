# inih

Callback based INI parser modeled after [inih](https://github.com/benhoyt/inih).
It never touches the heap: the input is a borrowed `CStrs` slice from
`lib/text/strs.hc` and the handler receives `section`, `name` and `value` as
slices into it, so nothing is copied or NUL-terminated.

- `[section]` headers; names before any header get an empty section
- `name = value` pairs with surrounding whitespace stripped
- `;` and `#` comment lines, blank lines and CRLF endings are ignored
- a line without `=` is reported with a `NULL` value
- the handler returns `FALSE` to stop; the returned `CIni` says why/where

```c
#include "lib/inih/inih.hc"

Bool OnPair(CIni *ini, CStrs *section, CStrs *name, CStrs *value)
{
  I64 *port = ini->user;

  if (StrsEqualsS(section, "net") && StrsEqualsS(name, "port"))
    *port = Str2I64(StrsDup(value)); // or parse the slice in place
  return TRUE;
}

I64 port = 0;
CIni ini = IniParseS("[net]\nport = 80\n", &OnPair, &port);
if (!ini.ok)
  "ini error %d at line %d\n", ini.err, ini.line;
```

`IniParse(CStrs *text, IniHandler *handler, U8 *user=NULL)` parses a slice
and `IniParseS` a NUL-terminated string. Both return a `CIni` with `ok`,
`err` (`INI_OK`, `INI_ERROR_INVALID_ARGS`, `INI_ERROR_MISSING_BRACKET` for
`[` without `]`, `INI_ERROR_TRAILING_CHARS` for text after `]`,
`INI_ERROR_INVALID_DEF` for `=` with no name, `INI_ERROR_HANDLER` when the
handler returned `FALSE`) and `line`, the 1-based line where parsing stopped.
The handler gets a pointer to that same record, so `ini->user` and
`ini->line` are available while parsing.
