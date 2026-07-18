// #exe{} runs HolyC inside the compiler at compile time, just like
// TempleOS: StreamPrint injects source text into the compile stream
// right after the block. See doc/exe.md for the design.

#define N 6
#exe {
  I64 i;
  StreamPrint("I64 SQUARES[N] = {");
  for (i = 0; i < N; i++) {
    if (i) StreamPrint(",");
    StreamPrint("%d", i * i);
  }
  StreamPrint("};");
};

// injected text is re-lexed: it may define macros, functions,
// even further #exe blocks
#exe { StreamPrint("#define GREETING \"made at compile time\""); };

// the TempleOS kernel-config pattern: choose code paths at compile time
#define CFG_TEXT_MODE FALSE
#exe {
  if (CFG_TEXT_MODE)
    StreamPrint("U0 Banner() { \"text mode\\n\"; }");
  else
    StreamPrint("U0 Banner() { \"vga mode\\n\"; }");
};

I64 i;
for (i = 0; i < N; i++)
  "%d ", SQUARES[i];
"\n";
"%s\n", GREETING;
Banner;
