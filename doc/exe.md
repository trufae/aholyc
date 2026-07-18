# `#exe{}` — compile-time execution

TempleOS lets any program run HolyC *inside the compiler* with
`#exe {...}`. aholyc supports the same directive. This document explains
how TempleOS uses it, the design aholyc chose, and what the differences
and limits are.

## What TempleOS does with it

Surveying every `#exe` in the TempleOS sources (third_party/TempleOS)
shows a handful of recurring patterns:

* **Bake compile-time values into the binary** — `Kernel/KStart16.HC`:
  `#exe {StreamPrint("SYS_COMPILE_TIME:: DU64 0x%X;",Now);}`
* **Conditional code from build configuration** — `Kernel/KStart16.HC`
  emits `INT 0x10` only when `!kernel_cfg->opts[CFG_TEXT_MODE]`;
  `Kernel/BlkDev/DskAddDev.HC` injects `probe=TRUE;` or `probe=FALSE;`.
* **Computed macros** — `Demo/DolDoc/DefineStr.HC`:
  `StreamPrint("#define COMPANY_AGE %0.1f\n", ...date math...)`.
* **Build scripting around includes** — `Kernel/Mem/MakeMem.HC` starts
  with `#exe {Cd(__DIR__);};`, includes a list of files, then
  `#exe {Cd("..");};`.
* **Compiler option toggles** — `#exe {Option(OPTf_NO_REG_VAR,ON);};`
  around interrupt handlers (`KExcept.HC`, `KTask.HC`).
* **Injecting more directives** — `DskAddDev.HC` StreamPrints whole
  `#exe {...}` blocks into the stream, which then run in turn.

The primitive underneath is `StreamPrint` (`Compiler/CMisc.HC`): it
appends formatted text to the current stream block, and the lexer
continues reading from that text when the block returns.

## The design aholyc chose

TempleOS can do this trivially: the compiler is a JIT living in the
same address space as everything else, so a `#exe` block is just one
more JIT job. aholyc is an AOT cross-compiler written in C, so the block
has to become native code some other way. The options were:

* an **interpreter** or **bytecode VM** — a second implementation of
  HolyC semantics to write and keep in sync, and slow;
* a **multi-stage build** (compile a helper binary, run it, restart
  the compile) — lots of process plumbing, no access to compiler
  internals;
* a **JIT** — big, platform-specific, exactly what aholyc avoids;
* a **shared library dlopened into the compiler** — the one aholyc took.

The block is compiled by the *same* lexer, parser and codegen as any
program, using the C backend, into a temporary shared library that is
`dlopen`ed into the running compiler and executed. One compiler, one
set of semantics, native speed, and — because the block runs in the
compiler's own address space — direct pointer access to compiler
internals with zero marshalling. Compiler pointers are plain addresses
in the same process, so they can be handed to HolyC code and even
inlined into generated text.

The C backend is the natural fit for the dl target: aholyc's HolyC class
layout uses the same natural-alignment rules as C structs, so a HolyC
`class` can mirror a compiler `struct` byte for byte, and the block
manipulates live compiler data through ordinary member access.

### Flow

```
lexer hits "#exe {"           (src/lex.c, preprocess)
  cut the {...} tokens out of the stream
  preprocess them            (same macro table: one compile stream)
  exe_run(block, &rest)      (src/exe.c)
    prepend runtime prelude + exe API   (runtime/exe.hc)
    parse                    (same parser, made re-entrant)
    emit C                   (same C backend, runtime embedded)
    cc -O0 -w -shared -fPIC  -> /tmp/aholyc-exe-<pid>-<n>.so
    dlopen(RTLD_NOW|RTLD_LOCAL); call __hc_start(0, empty_argv); dlclose
    collect StreamPrint text
  re-tokenize the text as "<exe>" and splice it in before rest
```

All of the dl glue lives in `src/exe.c` (~130 lines) and
`runtime/exe.hc` (~60 lines); the compiler proper is untouched apart
from the `#exe` branch in the preprocessor and an eight-line reset
that makes `parse()` re-entrant.

### The shim

`aholyc` is linked with `-rdynamic`, so every symbol of the compiler
binary is visible to dlopened blocks. `src/exe.c` exports the small
API the blocks' extern declarations resolve against (`__StreamPutS`,
`ExeStream`, `ExeStreamSet`, `Cd`, `Now`); everything else in the exe
API is plain HolyC in `runtime/exe.hc`, compiled with the block. The
embedded runtime inside the `.so` is `static`, so blocks never collide
with the compiler or with each other.

Compiler internals keep their names on the HolyC side: `class Token`
in `runtime/exe.hc` mirrors `struct Token` in `src/aholyc.h` — same
member names, same offsets — and `TK_*` match `TokenKind`. Since
`-rdynamic` exports everything, an adventurous block can declare an
extern for *any* compiler function and call it.

## API available inside `#exe{}`

Everything from the normal runtime prelude (Print, MAlloc, StrCmp,
try/catch, ...) plus:

| name | meaning |
|------|---------|
| `U0 StreamPrint(U8 *fmt, ...)` | inject formatted source text after the block (TempleOS) |
| `Token *ExeStream()` | the compiler's live token stream right after the block |
| `U0 ExeStreamSet(Token *t)` | advance the stream: consume tokens the block read |
| `I64 Cd(U8 *path)` | chdir of the compiler process (TempleOS) |
| `I64 Now()` | compile-time clock, unix seconds (TempleOS: CDate) |
| `__FILE__`, `__DIR__` | macros: file containing the block, its directory |
| `class Token`, `TK_*` | mirror of the compiler's token structures |
| `Option`, `PassTrace`, `Echo` | accepted for TempleOS compatibility, no-ops |
| `U8 *StrPrintJoin(U8 *dst, U8 *fmt, I64 argc, I64 *argv)` | varargs-forwarding formatter (also in the normal prelude) |

Semantics worth knowing:

* The block shares the **macro table** with the outer program — macros
  defined before the block work inside it, and `#define`s made inside
  the block (or injected by it) are visible after it. One compile
  stream, like TempleOS.
* Injected text is **re-lexed in full**: it may contain declarations,
  macros, and further `#exe` blocks.
* Each `StreamPrint` starts on a **fresh line** in the injected text
  (TempleOS concatenates raw). This keeps injected directives valid,
  since aholyc directives must start a line.
* Errors inside a block are reported with the original file/line.
* A compile-time `Print` writes to the compiler's stdout — useful as a
  build-time trace, like TempleOS `Echo`.

## Limitations

* **Compile time only.** aholyc produces self-contained native binaries
  with no compiler inside, so the runtime half of the TempleOS API
  (`ExePutS`, `ExePrint`, `ExeFile`, `StreamExePrint`, `RunFile`) does
  not exist. This is by design: the payoff is blazing-fast AOT output.
  See "The runtime half on POSIX" below for how it could be added
  without giving that up.
* **Token-level reflection, not AST.** aholyc preprocesses the entire
  stream before parsing, so when a block runs, the outer program has
  no AST yet. TempleOS interleaves lex/parse/JIT per statement; aholyc
  deliberately does not. Blocks inspect and rewrite *tokens*.
* `#exe` is a directive: it must be the first token on its line.
  Mid-expression `#exe` (TempleOS `StreamExePrint`) is not supported.
* **No state across blocks.** Each block is its own shared library
  with its own globals; TempleOS blocks share the task's symbol table.
  Persist through injected code, macros, files, or `Cd` (the process
  cwd does persist).
* Functions and classes defined inside a block exist only during the
  block. To add them to the program, `StreamPrint` their source.
* `Option`/`PassTrace`/`Echo` do nothing — aholyc's codegen has no
  equivalent knobs.
* `Now()` returns unix seconds, not the TempleOS `CDate` 32.32 fixed
  point.
* The build machine needs a C compiler and `dlopen` at compile time.
  When cross-compiling, blocks still run on the build machine.

## The runtime half on POSIX

An evaluation of what it would take to offer the TempleOS *runtime*
compiler API from aholyc-built binaries on a normal POSIX system.

What TempleOS provides (`Compiler/CMain.HC`):

| name | semantics |
|------|-----------|
| `I64 ExePutS(buf)` | JIT compile + run HolyC text, return the last expression's value |
| `I64 ExePrint(fmt,...)` | `ExePutS(MStrPrint(fmt,...))` |
| `I64 ExeFile(name)` | `ExePutS("#include \"name\";")` |
| `I64 RunFile(name,flags,...)` | `ExeFile(name)`, then call the file's last-defined function with the extra args (`LastFun`) |
| `I64 StreamExePrint(fmt,...)` | inside an AOT `#exe{}` block only: run text against the outer stream |

`StreamPrint` needs no evaluation: it is compile-time by definition
(it appends to the token stream being compiled) and aholyc already has
it inside `#exe{}`. Same for `StreamExePrint`: it only means something
while a compile is in progress, and within a block plain `StreamPrint`
covers the use.

For the other four the options mirror the `#exe` design decision:

* **Link the compiler into every binary** (a `libaholyc`) — makes every
  hello world carry a compiler. Violates the small-binary rule for
  programs that never eval anything; rejected.
* **A runtime interpreter** — a second implementation of HolyC
  semantics to keep in sync; rejected for `#exe`, same verdict here.
* **Reuse the `#exe` mechanism at runtime** — the program shells out
  to the `aholyc` on `PATH` exactly like the compiler itself does for
  `#exe` blocks: emit C, `cc -O0 -w -shared -fPIC`, `dlopen` into the
  running process, call `__hc_start(0, empty_argv)`, `dlclose`. One compiler, one set
  of semantics, and the machinery already exists in `src/exe.c` — the
  runtime version is the same ~100 lines with `exe_run`'s
  StreamPrint plumbing replaced by a result slot.

The third option fits aholyc:

* **Cost when unused: zero.** The whole feature is one more section
  of `runtime/rt.c` (`fork`/`exec` + `dlopen` + the result protocol),
  `HC_API static` like everything else, so a program that never calls
  `ExePrint` produces a byte-identical binary. The extra link flags
  (`-ldl`, and `-rdynamic` so chunks can call the host's `public`
  symbols) would be added by the driver only when the program
  references the API, keeping the exported-symbol table lean too.
* **Return value.** TempleOS returns the last expression's value. The
  chunk build would compile in a "chunk mode" where the synthesized
  startup function stores the value of its last top-level expression
  statement into an exported `I64 __hc_result`, read after
  `__hc_start` returns.
* **`RunFile` args.** Chunk mode also exports the address of the last
  *defined* function as `__hc_lastfun`; `RunFile` calls it through a
  function pointer with the forwarded varargs — `LastFun` semantics
  without a symbol table.
* **Shared state.** Like `#exe` blocks, a chunk carries its own static
  runtime: its `Fs`, exception stack and allocator are separate from
  the host's, and its globals die with `dlclose`. It can call the
  host's `public` functions (via `-rdynamic`), which is also the
  channel for sharing data. TempleOS shares the task's whole symbol
  table; that looseness is not reproducible across a static AOT
  boundary and would stay a documented difference.
* **Errors.** A failed compile makes `ExePutS` throw `'Compiler'`,
  matching the TempleOS try/catch contract.
* **Requirements.** The *target* machine needs `aholyc`, a C compiler
  and `dlopen` at runtime — the moral equivalent of TempleOS shipping
  its compiler in the OS image. A cross-compiled appliance without a
  toolchain cannot eval; that is inherent to AOT, not to this design.
* **JS backend.** node could `eval` aholyc-generated JS, but the chunk
  and host would have to negotiate one linear memory and function
  table; doable, bigger than the POSIX story, and left out of scope.

Verdict: `ExePutS`/`ExePrint`/`ExeFile`/`RunFile` are implementable
today as a thin opt-in runtime section plus a small chunk-mode tweak
to the driver (exporting `__hc_result`/`__hc_lastfun`), with zero cost
to programs that do not use them. What cannot be reproduced is
TempleOS's shared symbol table — chunks are separate libraries, not
patches to the running image.

## Debugging

`aholyc -v` prints the `cc -shared` command used for each block; `-k`
keeps the intermediates (`/tmp/aholyc-exe-<pid>-<n>.c` and `.so`) for
inspection.

See `examples/exe.HC` (code generation, computed macros, config
patterns) and `examples/exetokens.HC` (stream reflection, in-place
token patching, a compile-time mini-DSL).
