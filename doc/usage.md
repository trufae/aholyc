# Using aholyc

aholyc behaves like a normal C compiler:

```console
$ aholyc program.HC                 # build ./a.out with the default backend
$ aholyc program.HC -o program      # choose the output name
$ aholyc run program.HC             # build and run, leaving no binary behind
$ aholyc run program.HC one -x      # build, run, and pass program arguments
$ aholyc -b c program.HC            # pick a backend: llvm, c, js
$ aholyc -S -b llvm program.HC      # emit program.ll only, don't build
$ aholyc -S -b js -o out.js program.HC
$ aholyc -c module.HC               # compile to module.o, like gcc -c
$ aholyc main.HC module.o -o prog   # .o/.a inputs are linked in
$ aholyc run - < program.HC         # '-' reads source from stdin
$ echo '"hi\n";' | aholyc run -     # compile and run a one-liner
$ aholyc -S -b js -o - - < f.HC     # '-' is stdin; '-o -' emits to stdout
$ aholyc fmt -w src.HC              # format sources in place (doc/format.md)
```

## Options

| option | meaning |
|--------|---------|
| `-o file` | output executable (default `a.out`); with `-S`, `-o -` writes to stdout |
| `-b name` | backend: `llvm` (default), `c`, `js` |
| `-c` | compile to a relocatable object (`.o`), do not link |
| `-S` | stop after emitting the backend source artifact |
| `-O0..-O3, -Os, -Oz` | optimization for the native toolchain (default `-Os`) |
| `-I dir` | add an `#include` search directory (also forwarded to the C toolchain) |
| `-L dir` | add a library search directory for the linker |
| `-l name` | link against a library (e.g. `-lz`) |
| `-D name[=value]` | predefine a macro; when the value is an identifier, `-Dname=word` also defines case-sensitive `name_word` so `#ifdef` can dispatch on the value ; the last `-D` of a name wins |
| `-fno-hints` | ignore all source hints, treating their annotations as ordinary comments |
| `-k` | keep intermediate files (`.ll`, `.c`, runtime copies, `#exe` block libraries) |
| `-V` | print the toolchain commands being executed (including `#exe` builds) |
| `-h`, `-v` | help / version |

Multiple `.HC` input files are concatenated and compiled as one
translation unit, in order.

The host platform macros (`IS_MACOS`, `IS_LINUX`, `IS_NETBSD`, `IS_OPENBSD`,
`IS_FREEBSD`, `IS_WINDOWS`, and `IS_UNIX`) and architecture macros
(`IS_X86_64`, `IS_ARM_64`, `IS_ARM_32`, `IS_POWERPC`, `IS_RISCV`, or
`IS_MIPS`) are predefined, so sources can `#ifdef` on them to pick platform
defaults.

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

## What happens under the hood

1. The embedded prelude (`runtime/prelude.hc`) is compiled first: it
   defines `TRUE`/`NULL`/`Bool`... and declares the runtime API.
2. Your file(s) are lexed, preprocessed, and parsed into one AST.
   Top-level statements become the startup function.
3. The selected backend emits a source artifact next to the output
   (`out.aholyc.ll`, `out.aholyc.c`, or `out.aholyc.js`; removed unless `-k`).
4. The backend builds the executable:
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
