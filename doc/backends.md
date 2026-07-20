# aholyc backends

A backend turns the parsed program into a *source artifact* (never object
code) and knows how to build an executable from it using external tools
only. That keeps aholyc dependency-free: the LLVM toolchain, the system C
compiler, or node are used at *your* build time, never linked into aholyc.

## llvm (default)

Emits textual LLVM-IR (`.ll`). Every local is an `alloca`, every scalar
is `i64` or `double`, addresses are `i64` and become pointers at each
load/store — LLVM's mem2reg and the usual pipeline turn this into proper
registerized code, so aholyc stays simple and the optimizer does the heavy
lifting (this is the TempleOS way: let one big hammer do the work).

Build: `clang -Os prog.ll runtime.c -o prog`, or if clang is missing,
`llc prog.ll -o prog.s` + `cc prog.s runtime.c`. Exceptions use
`@_setjmp` declared `returns_twice` plus a small frame stack in the
runtime.

## c

Emits one self-contained C translation unit: the C99 runtime source is
prepended, then the program as "portable assembly" C — all values are
`hc_i64`/`hc_f64`, all memory accesses are explicit width-typed derefs.
The output of `-S -b c` compiles anywhere with
`cc -Os -fno-strict-aliasing -w out.c -lm`.

The `@bits` source hint uses C23 `_BitInt(N)` declarations or conversions.
Compiling hinted output therefore requires a compiler with `_BitInt` support;
`-fno-hints` retains the ordinary portable integer types.  See
[hints.md](hints.md).

This backend is the reference implementation and works on any machine
with a C compiler — no LLVM needed. It is also how `#exe{}` blocks run,
whatever backend the outer program uses: each block is emitted as C,
built into a shared library and dlopened into the compiler process
(see `doc/exe.md`).

In whole-program mode the runtime is injected with `#define HC_API
static`, so the C compiler discards every runtime function the program
never uses; combined with `--gc-sections` (both native backends) a
hello world carries ~3 KB of code instead of the full runtime.

## js

Emits a complete node script. Memory is one `ArrayBuffer`; pointers are
byte addresses; a `DataView` does typed loads/stores, so pointer tricks,
classes and `MAlloc` behave exactly like the native backends.

JavaScript has no `goto` (and aholyc lowers `switch` into gotos), so each
function is compiled into a program-counter state machine:

```js
for (;;) switch (pc) {
  case 0: ...; pc = 3; continue;
  ...
}
```

HolyC exceptions map onto JS exceptions with a per-invocation try stack.
Caveat: `I64` is a JS number — exact to 53 bits only. The address-space
layout is documented in [memory.md](memory.md).

The JS runtime gets the same dead-code treatment as the C runtime:
`runtime/rt.js` is split into chunks by `//@ name dep...` markers, the
backend records every runtime helper the program actually references
while emitting, and only the transitive closure of used chunks is
shipped — a hello world carries ~17 runtime functions instead of ~90.
When adding a runtime function, give it a marker line listing the other
runtime functions it calls; shared module state (like the PRNG seed)
lives in its own chunk that its users depend on.

## Adding a backend

Backends are a vtable in `src/aholyc.h`:

```c
typedef struct Backend {
    const char *name;   /* -b <name> */
    const char *ext;    /* artifact extension */
    const char *descr;
    void (*emit)(Aholyc *cc, Program *prog, FILE *out,
                 bool object_mode, bool ctor_mode);
    int (*build)(Aholyc *cc, const char *artifact,
                 const char *outpath, const char *opt);
    int (*build_obj)(Aholyc *cc, const char *artifact,
                     const char *outpath, const char *opt); /* optional */
} Backend;
```

The driver passes `object_mode` explicitly for `-c` and source groups mixed
with `.o` inputs. In that mode the runtime is declared instead of embedded and
`public` symbols keep external linkage. `ctor_mode` distinguishes a true `-c`
module, whose constructor registers its startup function, from a source group
linked with objects, whose startup remains `__hc_start(argc,argv)`. Other
driver options and diagnostics come through the `Aholyc` instance.

1. Create `src/back_foo.c`, define `const Backend backend_foo`.
2. Add it to the `backends[]` array in `src/main.c` and to `LIBSRC` in the
   Makefile.

The AST a backend receives is deliberately small. The parser has already
lowered all the HolyC sugar (default args, implicit prints, `switch`,
compound assignment, `++`/`--`, chained comparisons), so `emit` only has
to handle: literals, variables, loads/stores, the arithmetic/logic
operators, calls (direct, variadic with `argc`/`argv` packing, indirect),
`if`, `while`/`do`/`for`, `goto`/labels, `return`, and `try`. Statement
`goto` is the only unstructured control flow a backend must support —
see the C backend for the simplest possible implementation, the JS
backend for how to cope without native goto.

Backend checklist, in the order the test suite will hit it:

* widths: loads sign/zero-extend by declared type; stores truncate
* pointer arithmetic scales by element size
* `argc`/`argv`: extras are 8-byte slots, F64 bit-copied
* exceptions: catch runs during the handler search; rethrow when
  `Fs->catch_except` stays 0
* `Print` and friends live in the runtime — emit calls, not formatting
