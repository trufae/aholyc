# Using mhc

mhc behaves like a normal C compiler:

```console
$ mhc program.HC                 # build ./a.out with the default backend
$ mhc program.HC -o program      # choose the output name
$ mhc -r program.HC              # build and run
$ mhc -b c program.HC            # pick a backend: llvm, c, js
$ mhc -S -b llvm program.HC      # emit program.ll only, don't build
$ mhc -S -b js -o out.js program.HC
$ mhc -c module.HC               # compile to module.o, like gcc -c
$ mhc main.HC module.o -o prog   # .o/.a inputs are linked in
```

## Options

| option | meaning |
|--------|---------|
| `-o file` | output executable (default `a.out`) |
| `-b name` | backend: `llvm` (default), `c`, `js` |
| `-c` | compile to a relocatable object (`.o`), do not link |
| `-S` | stop after emitting the backend source artifact |
| `-O0..-O3, -Os, -Oz` | optimization for the native toolchain (default `-Os`) |
| `-I dir` | add an `#include` search directory (also forwarded to the C toolchain) |
| `-L dir` | add a library search directory for the linker |
| `-l name` | link against a library (e.g. `-lz`) |
| `-D name[=value]` | predefine a macro |
| `-r`, `--run` | run the program after a successful build |
| `-k` | keep intermediate files (`.ll`, `.c`, runtime copies) |
| `-v` | print the toolchain commands being executed |
| `-h`, `--version` | help / version |

Multiple `.HC` input files are concatenated and compiled as one
translation unit, in order.

## Separate compilation (-c)

`-c` produces a relocatable object, so mhc can be dropped into Makefiles
that expect a C compiler:

```console
$ mhc -c mod_a.HC                # -> mod_a.o
$ mhc -c mod_b.HC                # -> mod_b.o
$ mhc mod_a.o mod_b.o -o prog    # mhc links objects + the HolyC runtime
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

* Top-level code (including global initializers) of an object runs as a
  constructor at program start, before `main`, in **link order** — so
  list objects whose startup code others depend on first.
* Link with mhc (it adds the runtime); `gcc a.o b.o` alone will miss the
  HolyC runtime symbols. `.a` archives are accepted too.
* `-c` works with the `llvm` and `c` backends; the `js` backend has no
  object format.
* With several `.HC` files and `-c`, mhc builds **one** object from the
  group (HolyC sources are always one translation unit); the default
  output name comes from the first file.

## What happens under the hood

1. The embedded prelude (`runtime/prelude.hc`) is compiled first: it
   defines `TRUE`/`NULL`/`Bool`... and declares the runtime API.
2. Your file(s) are lexed, preprocessed, and parsed into one AST.
   Top-level statements become the startup function.
3. The selected backend emits a source artifact next to the output
   (`out.mhc.ll`, `out.mhc.c`, or `out.mhc.js`; removed unless `-k`).
4. The backend builds the executable:
   * **llvm** — `clang prog.ll runtime.c -Os -o prog` (or `llc` + `cc`
     when clang is absent). mhc never links LLVM libraries; it only
     drives the external tools.
   * **c** — the artifact already contains the runtime; `cc -Os` builds it.
   * **js** — the artifact is a complete node script; it is installed to
     the output path with a `#!/usr/bin/env node` shebang and `chmod +x`.
5. The binary is stripped for size.

If no backend is given, mhc uses `llvm` when clang or llc is installed,
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
$ mhc zdemo.HC -lz -o zdemo
```

mhc emits matching declarations for every `extern` symbol your source
declares that the runtime doesn't provide. All HolyC integers are 64-bit,
so prefer C functions with pointer/`long long`/`double`-shaped
signatures; mask narrower return values yourself (e.g. `x(I32)`), and
avoid C-variadic functions like `printf` (HolyC varargs use the
`argc`/`argv` convention instead).

## Dead code elimination

The runtime is embedded as `static` in whole-program C builds and the
build always uses `-ffunction-sections -fdata-sections` with linker
section GC, so runtime functions your program never calls do not reach
the final binary.

## Exit status and errors

Compile errors print `file:line: error: message` and exit 1. With `-r`,
mhc exits with the program's exit code.

## Environment

* `CC` — the C compiler used by the `c` backend and the `llc` fallback
  (default: `cc`).
