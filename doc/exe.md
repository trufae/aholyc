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

The block uses the same lexer and parser as any program, but always executes
through the C backend, independent of the outer output backend. It becomes a
temporary shared library that is `dlopen`ed into the running compiler. One
compiler, one set of semantics and native speed; callbacks provide controlled
access to its compiler instance, with token pointers as plain addresses.

To reproduce TempleOS's ability to call an already-known generator, aholyc
keeps the complete top-level preprocessed constructs preceding each block.
The temporary program contains the normal prelude, the `#exe` API, that source
prefix, a private startup marker, and the block. Earlier classes, globals, and
function bodies are consequently in scope. An unfinished containing function
is not copied when `#exe` appears inside it. Startup statements from the prefix
are cut from the temporary entry point, so compiling a block does not
accidentally execute ordinary program code:

```c
U0 VecDefine(U8 *name, U8 *type)
{
  StreamPrint("class %s { %s *data; I64 count; };", name, type);
}

#exe {
  VecDefine("I64Vec", "I64");
  VecDefine("U8Vec", "U8");
};
```

The helper is ordinary HolyC and remains part of the final program as well.
Calling `StreamPrint` at runtime, when no `#exe` stream is active, reports an
error instead of injecting source.

The C backend is the natural fit for the dl target. HolyC classes are packed
by default, so the `Token` mirror in `runtime/exe.hc` uses explicit `$$`
offsets for the padding present in the compiler's C `struct Token`. The block
can then manipulate live token data through ordinary member access.

### Flow

```
lexer hits "#exe {"           (src/lexpp.c, preprocess)
  cut the {...} tokens out of the stream
  preprocess them            (same macro table: one compile stream)
  exe_run(block, &rest) (src/exe.c)
    prepend runtime prelude + exe API
    append preceding preprocessed user source
    append private marker + block
    parse                    (same parser, invocation-local state)
    discard startup statements before the marker
    emit C                   (same C backend, runtime embedded)
    append callback bridge; cc -shared -> /tmp/aholyc-exe-XXXXXX/block.so
    dlopen(RTLD_LOCAL); initialize callbacks; call __hc_start; dlclose
    collect StreamPrint text
  re-tokenize the text as "<exe>" and splice it in before rest
```

The dl glue lives in `src/exe.c` and `runtime/exe.hc`. Nested parsing and
emission use local contexts; the macro table, preceding source history, and
virtual working directory remain part of the containing `Aholyc` instance.

### The shim

`src/exe.c` appends a tiny bridge to every generated shared library. After
`dlopen`, the compiler initializes it with the current `Aholyc` and callbacks
for `__StreamPutS`, `ExeStream`, `ExeStreamSet`, `Cd` and `Now`. The externs in
`runtime/exe.hc` resolve inside that DSO, so the compiler exports no callback
symbols and needs no global router. `RTLD_LOCAL` plus a private embedded
runtime keeps simultaneous blocks isolated.

Compiler internals keep their names on the HolyC side: `class Token`
in `runtime/exe.hc` mirrors `struct Token` in `src/aholyc.h` — same
member names, same offsets — and `TK_*` match `TokenKind`. Blocks can
inspect these tokens only through the declared callback API.

## API available inside `#exe{}`

Everything from the normal runtime prelude (Print, MAlloc, StrCmp,
try/catch, ...) plus:

| name | meaning |
|------|---------|
| `U0 StreamPrint(U8 *fmt, ...)` | inject formatted source text after the block (TempleOS) |
| `Token *ExeStream()` | aholyc adapter: live token stream right after the block |
| `U0 ExeStreamSet(Token *t)` | aholyc adapter: advance the stream to consume tokens |
| `I64 Cd(U8 *path)` | change this compiler instance's cwd |
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
* Classes, globals, and functions declared earlier in the source are visible
  inside the block. aholyc recompiles those declarations into the temporary
  DSO; it does not replay earlier top-level statements.
* Injected text is **re-lexed in full**: it may contain declarations,
  macros, and further `#exe` blocks.
* Each `StreamPrint` starts on a **fresh line** in the injected text
  (TempleOS concatenates raw). This keeps injected directives valid,
  since aholyc directives must start a line.
* Errors inside a block are reported with the original file/line.
* A compile-time `Print` writes to the compiler's stdout — useful as a
  build-time trace, like TempleOS `Echo`.

## Compatibility with TempleOS

The reference for "standard" behavior here is the bundled official TempleOS
source, especially `Compiler/PrsStmt.HC:PrsStreamBlk`,
`Compiler/CMisc.HC:StreamPrint`, `Compiler/CMain.HC:StreamExePrint`, and
`Kernel/StrPrint.HC:StrPrintJoin`. The differences are:

| Area | TempleOS | aholyc |
|------|----------|--------|
| Earlier symbols | `PrsStreamBlk` switches to JIT mode and uses the task's `Fs->hash_table`, so already-JIT-loaded functions, types, globals, and system symbols are live. | Recompiles the preprocessed source before the block. Earlier source functions and types can be called, including generator helpers, but they are copies in the temporary DSO. |
| Values and addresses | Uses the task's live global storage and symbol addresses. Mutations can survive and addresses keep their identity. | Earlier globals are newly allocated and zero-initialized in each DSO. Earlier top-level initializers and statements are deliberately not replayed. Mutations and addresses do not survive `dlclose`, and each block starts with another copy. |
| Stream insertion | Consecutive `StreamPrint` calls concatenate raw bytes in one `CStreamBlk`. Token fragments may intentionally join. | Adds a newline after every call. This prevents accidental token joining and makes injected directives start on a line, but code depending on raw concatenation differs. |
| Directive position | The TempleOS lexer handles `#exe` when it encounters `#`; it is not restricted by aholyc's beginning-of-line check. | `#exe` must be the first token on its source line. It may appear inside a function, but the injected text must be legal at that function-body location. |
| Format language | Uses the full TempleOS `StrPrintJoin`, including formats such as `%C`, `%T`, `%z`, function-format callbacks, and TempleOS field/justification flags. | Implements the common hosted subset: `d i u x X o p P c s f e g`, flags, width, and precision. Unsupported TempleOS conversions are emitted literally, so generators using them must be adapted. |
| Compiler controls | `Option`, `PassTrace`, `Echo`, and related calls alter the active compiler. | `Option`, `PassTrace`, and `Echo` are accepted no-ops. |
| Compiler reflection | Code can use TempleOS's in-process compiler and task structures directly. | Exposes only the `Token` mirror plus `ExeStream`/`ExeStreamSet` callbacks. Those two functions are aholyc adapters, not TempleOS APIs. |
| Time and directory | `Now` is a TempleOS `CDate`; `Cd` changes the task's drive/directory state. | `Now()` is Unix seconds. `Cd` changes a compiler-instance virtual CWD without changing the host process CWD. |
| Runtime compilation | `ExePutS`, `ExePrint`, `ExeFile`, `RunFile`, and `StreamExePrint` use the resident JIT. | These runtime APIs are not implemented. `StreamPrint` is available for compile-time generation only. |
| Execution environment | Runs through TempleOS's resident x86-64 JIT and shares the compiler task. | Builds a host C shared library, loads it with `dlopen`, and uses a private embedded runtime. The build machine needs a C compiler even when the outer target is LLVM, C, or JS. |
| Block-local definitions | Definitions execute in TempleOS's compiler/JIT symbol environment. | Functions and classes defined inside a block exist only in that block's DSO. Use `StreamPrint` to add definitions to the output program. |
| Nested blocks | An inner block can use definitions the outer block has already JIT-compiled. | Macros and injected text nest, but an inner block cannot call a helper declared earlier inside its enclosing block; put reusable helpers before the outermost block. |

These distinctions matter most for stateful metaprograms. Pure generators
whose earlier helper functions compute text from their arguments are portable:

```c
#include "vec.HC"

#exe {
  VecDefine("PointVec", "CPoint");
  VecDefine("NumberVec", "I64");
};
```

Generators that read a previously initialized global, retain a pointer between
blocks, join tokens across multiple `StreamPrint` calls, or use a TempleOS-only
format conversion are not equivalent yet.

## Remaining limitations

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
* **No live state across blocks.** Each block is its own shared library.
  Source declarations are visible, but global values are fresh and earlier
  startup code is not executed. Persist through injected code, macros, files,
  or `Cd` (the virtual cwd persists for that compiler invocation).
* Functions and classes defined inside a block exist only during the
  block. To add them to the program, `StreamPrint` their source.
* Recompiling the full preceding source for every block makes many-block
  metaprograms progressively more expensive than TempleOS's shared JIT.
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

* **Link the compiler into every produced binary** — `libaholyc.a` makes this
  possible for host applications, but it would make every hello world carry a
  compiler. It violates the small-binary rule for programs that never eval.
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

* **Cost when unused: zero.** The whole feature is one more dead-strippable
  runtime section. Its `-ldl` link flag would be added only when referenced;
  a generated callback bridge can connect a chunk without exporting the host.
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
  the host's, and its globals die with `dlclose`. Explicit callbacks are the
  channel for sharing data. TempleOS shares the task's whole symbol table;
  that looseness is not reproducible across a static AOT boundary.
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

`aholyc -V` prints the `cc -shared` command used for each block; `-k`
keeps its `/tmp/aholyc-exe-XXXXXX/` directory for inspection.

See `examples/exe.HC` (code generation, computed macros, config patterns),
`examples/exe_symbols.HC` (earlier helpers and in-function placement),
`examples/vec.HC` (an include-once typed generator), and
`examples/exetokens.HC` (stream reflection, in-place token patching, a
compile-time mini-DSL).
