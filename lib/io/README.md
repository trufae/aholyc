# File I/O

`lib/io/file.hc` offers whole-file helpers on top of the C runtime's stdio,
so the same code runs on Linux, macOS and Windows:

```holyc
#include "lib/io/file.hc"

I64 size;
U8 *data = FileRead("input.bin", &size);   // heap buffer, NUL-terminated
if (data && FileWrite("copy.bin", data, size))
  "copied %d bytes\n", size;
Free(data);
if (FileExists("copy.bin"))
  "ok\n";
```

`FileWrite(path, text)` without a size writes a C string. Higher-level
libraries such as `lib/llm` deliberately take bytes rather than paths; combine
them with these helpers.
