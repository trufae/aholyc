# Using aholyc

aholyc behaves like a normal C compiler:

```console
$ aholyc program.HC                 # build ./a.out with the default backend
$ aholyc program.HC -o program      # choose the output name
$ aholyc run program.HC             # build and run, leaving no binary behind
$ aholyc run program.HC one -x      # build, run, and pass program arguments
$ aholyc -b c program.HC            # pick a backend: llvm, c, js
$ aholyc -t amiga program.HC -o program-amiga # cross-compile for m68k AmigaOS
$ aholyc -S -b llvm program.HC      # emit program.ll only, don't build
$ aholyc -S -b js -o out.js program.HC
$ aholyc -c module.HC               # compile to module.o, like gcc -c
$ aholyc -shared api.HC -o libapi.so # build a native shared library
$ aholyc -sarchive api.HC -o libapi.a # build a native static library
$ aholyc main.HC module.o -o prog   # .o/.a inputs are linked in
$ aholyc run - < program.HC         # '-' reads source from stdin
$ echo '"hi\n";' | aholyc run -     # compile and run a one-liner
$ aholyc -S -b js -o - - < f.HC     # '-' is stdin; '-o -' emits to stdout
$ aholyc fmt -w src.HC              # format sources in place (doc/format.md)
```

## Amiga cross-compilation

`-t amiga` selects the C backend and cross-compiles for classic m68k
AmigaOS. The default CPU is the 68000, with software floating point. Output
is an Amiga Hunk executable that can be copied to an Amiga and launched
from its shell:

```console
$ aholyc -t amiga examples/hello.HC -o hello-amiga
$ aholyc -t amiga -c module.HC -o module.o
$ aholyc -t amiga main.HC module.o -o program-amiga
$ aholyc -t amiga -sarchive module.HC -o libmodule.a
$ aholyc -t amiga -S program.HC -o program.c
```

The driver searches `PATH`, then `/opt/amiga/bin`, for
`m68k-amigaos-gcc` and `m68k-amigaos-ar`. Set `AMIGA_CC` and `AMIGA_AR`
to override these tools. `CC` continues to select the host compiler for
`#exe` blocks, which execute during compilation on the host.
`CFLAGS` and `LDFLAGS` apply to target builds; for example,
`CFLAGS=-mcpu=68020` selects a later CPU. The target uses the cross
compiler's default C runtime (newlib in the tested GCC 6.5.0b installation).

HolyC defines `IS_AMIGA`, `IS_M68K`, and `IS_BIG_ENDIAN` for this target,
instead of the host's platform macros. Integer values, function value slots,
and stored HolyC pointers remain eight bytes; actual Amiga addresses are
32 bits. Process arguments are converted into eight-byte `argv` slots.
Packed class members use alignment-safe loads and stores, and exceptions
use the target's `setjmp`/`longjmp`.

Memory uses the Amiga's native big-endian byte order. In particular,
`q.u8[0]` names the most significant byte of an `I64`; it is not the
little-endian TempleOS layout. Packed character constants and exception
names retain their HolyC interpretation.

The runtime supports one HolyC task per process and does not use TLS.
The `L` bit operations use Exec `Forbid`/`Permit` to protect byte updates
against other tasks; they are not interrupt-handler synchronization.
For imported C functions, declare their exact widths (`I32` for C `int`,
`U32` for `size_t`, pointer types for addresses). Separately compiled HolyC
functions retain the HolyC ABI: use `I64` parameters and results in module
interfaces, including address values, or supply C wrappers.
`lib/ui/ui.hc` automatically selects its native Intuition/GadTools backend
on this target. Build `examples/ui/amiga.hc` for a compact Workbench demo;
see the [UI library](../lib/ui/README.md) for features and limitations.
Other bundled libraries that depend on Unix or Windows APIs need separate
Amiga ports.

`run`, `-shared`, and native `asm {}` are unsupported for this target.
`HAS_ASM` is absent. GCC 6.5 does not support the C backend's `_BitInt`
output for `@bits` hints; use `-fno-hints` with those sources.
`make test-amiga` checks UI model/layout behavior on the host, then
cross-compilation, generated Hunk formats, and UI structure layouts against
the NDK when the toolchain is installed. Native execution requires an Amiga
or emulator.

## Options

| option | meaning |
|--------|---------|
| `-o file` | output file (default `a.out`); with `-S`, `-o -` writes to stdout |
| `-b name` | backend: `llvm` (default), `c`, `js` |
| `-t name` | target: `native` (default), `amiga` (selects the C backend) |
| `-c` | compile to a relocatable object (`.o`), do not link |
| `-shared` | build a native shared library (C and LLVM backends) |
| `-sarchive` | build a native static archive (`.a`, or `.lib` on Windows) |
| `-S` | stop after emitting the backend source artifact |
| `-O0..-O3, -Os, -Oz` | optimization for the native toolchain (default `-Os`) |
| `-I dir` | add an `#include` search directory (also forwarded to the C toolchain) |
| `-L dir` | add a library search directory for the linker |
| `-l name` | link against a library (e.g. `-lz`) |
| `-D name[=value]` | predefine a macro; the last `-D` of a name wins |
| `-fno-hints` | ignore all source hints, treating their annotations as ordinary comments |
| `-fno-asm` | reject every asm block left after preprocessing and omit `HAS_ASM` |
| `-fno-pic` | disable position-independent native code and PIE executable linking |
| `-fno-exceptions` | omit exception handlers and catch blocks; surviving throws abort |
| `-fno-stack-protector` | disable native stack-protector instrumentation |
| `-fno-strict-fnptr` | accept function pointers whose signature differs from the declared function-pointer type, and implicit conversions between function and data pointers, in assignments, arguments and returns |
| `-k` | keep intermediate files (`.ll`, `.c`, runtime copies, `#exe` block libraries) |
| `-V` | print the toolchain commands being executed (including `#exe` builds) |
| `-h`, `-v` | help / version |

Native compilation uses position-independent code by default, including with
`-c`. Pass `-fno-pic` to select the native static relocation model instead;
when linking an executable, it also disables PIE output.

Exceptions are enabled by default and define `HAS_EXCEPTIONS=1` for source
selection. With `-fno-exceptions`, that macro is absent, `try` bodies run
without handlers, and their `catch` blocks are omitted. A surviving
`throw(code)` prints `AHOLYC_EXCEPTION=0x` followed by all 16 hex digits and
terminates as a controlled abort. On Unix the resulting shell status is 134,
distinct from a segmentation fault's 139. Use `#ifdef HAS_EXCEPTIONS` to
provide a non-throwing fallback; all objects in one native link should be
compiled with the same exception setting.

Multiple `.HC` input files are concatenated and compiled as one
translation unit, in order.

The host platform macros (`IS_DARWIN`, `IS_LINUX`, `IS_NETBSD`, `IS_OPENBSD`,
`IS_FREEBSD`, `IS_WINDOWS`, and `IS_UNIX`) and architecture macros
(`IS_X86_64`, `IS_ARM_64`, `IS_ARM_32`, `IS_POWERPC`, `IS_RISCV`, `IS_MIPS`,
or `IS_S390`) are predefined, so sources can `#ifdef` on them to pick platform
defaults. Darwin also defines `IS_MACOS`, `IS_IOS` (including iPadOS),
`IS_TVOS`, `IS_WATCHOS`, `IS_VISIONOS`, or `IS_MACCATALYST` for the concrete
Apple platform when it can be identified. `HAS_ASM` is predefined when the
selected backend supports assembly and `-fno-asm` is not active; use it to
select a portable alternative to an `asm {}` block. `HAS_EXCEPTIONS` is
predefined unless `-fno-exceptions` is active.

## Program arguments

A built program receives only its user-supplied arguments: the executable
name is excluded, so the first argument is `argv[0]` and a run with no
arguments has `argc == 0`. The synthetic top-level entry exposes these as
`I64 argc` and `I64 *argv`; `argv[argc]` is `NULL`. See
[language.md](language.md#no-main) for how to forward them explicitly to a
user-defined `Main` function.

With `run`, the first positional argument is the program source. Every token
after it is passed verbatim to the built program, including tokens beginning
with `-`, empty arguments, and names ending in `.HC`. Put compiler options
before the program source:

```console
$ aholyc args.HC -o args
$ ./args alpha "two words" -x
$ aholyc run args.HC alpha "two words" -x
$ aholyc run -b c - alpha < args.HC
```

Without `run`, run the output executable directly to supply arguments. The
`run` arguments are command-line strings; they are unrelated to TempleOS
`RunFile`/`LastFun`, which forward typed HolyC call arguments.

## Reading from stdin

`-` as an input file reads HolyC source from stdin. For example,
`aholyc run - < prog.HC` and `echo '"hi\n";' | aholyc run -` compile from stdin;
invoking `aholyc` without an input file prints usage and exits with status 1.
Default artifact names for stdin input use the stem `stdin` (`-S` →
`stdin.ll`, `-c` → `stdin.o`), `-o -` with `-S` writes the artifact to
stdout (and is
rejected without `-S`), and `#include` directives resolve relative to the
current directory.

## Separate compilation (-c)

`-c` produces a relocatable object, so aholyc can be dropped into Makefiles
that expect a C compiler:

```console
$ aholyc -c mod_a.HC                # -> mod_a.o
$ aholyc -c mod_b.HC                # -> mod_b.o
$ aholyc mod_a.o mod_b.o -o prog    # aholyc links objects + the HolyC runtime
```

The rules, HolyC-style:

* `public` marks a function or global as **exported** (unmangled symbol,
  external linkage). Everything else in an object is local:

  ```holyc
  // mod_a.HC
  public I64 counter = 5;
  public I64 Twice(I64 x) { return 2 * x; }
  ```

* The consumer declares what it imports with `extern`, using the same
  types:

  ```holyc
  // mod_b.HC
  extern I64 counter;
  extern I64 Twice(I64 x);
  "twice(%d)=%d\n", counter, Twice(counter);
  ```

* Each object has a constructor that registers its top-level code (including
  global initializers) with the runtime. At program entry, the runtime invokes
  registered startups in **link order** with the process arguments — so list
  objects whose startup code others depend on first. When source is linked
  alongside those objects, its top-level entry runs afterward.
* Link with aholyc (it adds the runtime); `gcc a.o b.o` alone will miss the
  HolyC runtime symbols. `.a` archives are accepted too.
* `-c` works with the `llvm` and `c` backends; the `js` backend has no
  object format.
* With several `.HC` files and `-c`, aholyc builds **one** object from the
  group (HolyC sources are always one translation unit); the default
  output name comes from the first file.

## Shared libraries (-shared)

`-shared` accepts HolyC sources, existing `.o`/`.a` inputs, or both, and links
a native shared library with the HolyC runtime. `public` functions and globals
are exported with their HolyC names. Module constructors run top-level code
and global initializers when the library is loaded; because there is no process
entry point, shared-library startup receives `argc == 0`.

Runtime support inside a shared library has hidden visibility and is emitted in
individually discardable sections. The native linker therefore keeps only the
helpers actually referenced by that library, without exporting or interposing
runtime symbols from another HolyC library. A module with no top-level code or
global initializers emits no startup constructor at all.

Build shared libraries with either native backend and load or link them as you
would a C library:

```console
$ aholyc -shared -b llvm api.HC -o libapi.so
$ aholyc -c api.HC -o api.o
$ aholyc -shared api.o -o libapi.so
```

On macOS, conventionally use a `.dylib` output name. `-shared` cannot be
combined with `run` or `-c`, and the JavaScript backend does not support it.

## Static archives (-sarchive)

`-sarchive` compiles HolyC source to a relocatable object and packs it with
any supplied `.o` inputs into a static archive. It is supported by the C and
LLVM backends; the JavaScript backend has no object format. The default output
name is `a.a` (`a.lib` on Windows).

```console
$ aholyc -sarchive api.HC -o libapi.a
$ aholyc main.HC libapi.a -o prog
```

Like `-c`, archives rely on the final aholyc link to add the HolyC runtime.
They cannot contain another `.a`/`.lib` archive, and `-sarchive` cannot be
combined with `run`, `-c`, or `-shared`.

## What happens under the hood

1. The embedded prelude (`runtime/prelude.hc`) is compiled first: it
   defines `TRUE`/`NULL`/`Bool`... and declares the runtime API.
2. Your file(s) are lexed, preprocessed, and parsed into one AST.
   Top-level statements become the startup function.
3. The selected backend emits a source artifact next to the output
   (`out.aholyc.ll`, `out.aholyc.c`, or `out.aholyc.js`; removed unless `-k`).
4. The backend builds the native output:
   * **llvm** — `clang prog.ll runtime.c -Os -o prog` (or `llc` + `cc`
     when clang is absent). aholyc never links LLVM libraries; it only
     drives the external tools.
   * **c** — the artifact already contains the runtime; `cc -Os` builds it.
   * **js** — the artifact is a complete node script; it is installed to
     the output path with a `#!/usr/bin/env node` shebang and `chmod +x`.
If no backend is given, aholyc uses `llvm` when clang or llc is installed,
falling back to `c` otherwise.

## Calling C libraries

Declare foreign functions and globals with `extern` and link with
`-L`/`-l` (native backends only):

```holyc
// zdemo.HC
extern U64 crc32(U64 crc, U8 *buf, U32 len);
"%X\n", crc32(0, "hello", 5);
```

```console
$ aholyc zdemo.HC -lz -o zdemo
```

aholyc emits matching declarations for every `extern` symbol your source
declares that the runtime doesn't provide. All HolyC integers are 64-bit,
so prefer C functions with pointer/`long long`/`double`-shaped
signatures and mask narrower return values yourself (e.g. `x(I32)`).
C-variadic functions work too: a bodiless `extern` declared with `...`
uses the real C varargs ABI, so
`extern I64 printf(U8 *fmt, ...); printf("%s %lld %f\n", s, n, f);`
calls libc directly (use C format sizes: `%lld` for I64, `%f`/`%g` read
a double). Only variadic functions with HolyC bodies use the
`argc`/`argv` convention.

## Dead code elimination

The runtime is embedded as `static` in whole-program C builds and the
build always uses `-ffunction-sections -fdata-sections` with linker
section GC, so runtime functions your program never calls do not reach
the final binary.

## Exit status and errors

Compile errors print `file:line: error: message` and exit 1. With `run`,
aholyc exits with the program's exit code. A top-level `return n;` sets that
code (falling off the end returns zero); `Exit(n)` terminates immediately with
the same hosted process-status semantics.

## Environment

* `CC` — the C compiler used by the `c` backend and the `llc` fallback
  (default: `cc`).
* `CFLAGS`, `LDFLAGS` — extra space-separated words for the C-toolchain
  command line, make-style: `CFLAGS` on every compile, `LDFLAGS` only on
  executable links. The way to pass flags that have no aholyc option,
  e.g. `LDFLAGS='-framework AppKit' aholyc app.HC`. `#exe{}` builds are
  internal to the compiler and unaffected. Sources can carry the same
  words themselves with the `@cflags`/`@ldflags` comment hints
  ([hints.md](hints.md)).
