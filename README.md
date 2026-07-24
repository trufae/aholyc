# aholyc — another Holy-C compiler

`aholyc` compiles [HolyC](https://templeos.org) — the language Terry A. Davis
created for TempleOS — into real native executables, using the LLVM
toolchain for code generation without ever linking against LLVM libraries:
aholyc emits textual LLVM-IR and lets `clang`/`llc` do the rest.

```holyc
U0 Hello(U8 *who="World")
{
  "Hello %s!\n", who;
}
Hello;
```

```console
$ aholyc hello.HC -o hello
$ ./hello
Hello World!
```

## Highlights

* Written in portable C99. **Zero external dependencies** — building aholyc
  needs only `cc` and `make`.
* **Embeddable and parallel-safe.** `libaholyc.a` exposes four calls around
  an opaque compiler instance; independent instances share no mutable state.
* **Pluggable backends** selected with `-b`:
  * `llvm` — LLVM-IR text, compiled to native by clang/llc (default)
  * `c` — portable C99, compiled by the system C compiler
  * `js` — JavaScript for node, using a linear-memory model
* Faithful HolyC: no `main()`, implicit `Print` statements, default args in
  any position, paren-less calls, `case` ranges and sub_switch, `try/catch/
  throw`, variadic `argc/argv`, the `` ` `` power operator, chained
  comparisons, postfix casts, classes with single inheritance.
* Small output from `-Os` and dead-code elimination, without discarding
  symbols that are useful for debugging.

## Building

```console
$ make
$ make test        # runs examples on every available backend
$ sudo make install
```

Backends can be left out of the compiler binary when they are not needed:

```console
$ make AHOLYC_BACKEND_C=0 AHOLYC_BACKEND_JS=0  # LLVM-only build
```

`AHOLYC_BACKEND_LLVM`, `AHOLYC_BACKEND_C`, and `AHOLYC_BACKEND_JS` default
to `1`. `#exe{}` works with every output backend, but needs the C backend
to execute its compile-time block.

## Library

`make` also builds `libaholyc.a` and `install` installs `<aholyc.h>`. Create
an instance with `aholyc_init()` (which returns `NULL` on allocation failure),
pass the same argument vector accepted by the CLI to `aholyc_parseargv()`,
inspect errors with `aholyc_error()`, then release it with `aholyc_fini()`.
Calls start clean;
instance-local state lets separate compilers run concurrently. Link with
`libaholyc.a -ldl`.

## Layout

* `src/` — the compiler (lexer, parser, backends, driver)
* `runtime/` — the HolyC runtime (C and JS) and the prelude, embedded into
  the aholyc binary at build time
* `doc/` — [language](doc/language.md), [usage](doc/usage.md),
  [backends](doc/backends.md), [memory](doc/memory.md),
  [hints](doc/hints.md), [preprocessor](doc/pp.md),
  [internals](doc/internals.md)
* `examples/` — small HolyC programs, used by `make test`
* `third_party/` — reference material (TempleOS sources, holyc-lang)

## Why

TempleOS's compiler JIT-compiled HolyC into a single flat address space.
aholyc keeps the language and the spirit — simplicity, directness, no
dependency sprawl — but targets the world outside the temple: normal
operating systems, normal executables, several code generators.

God's temple ships with an amber screen; aholyc ships with a Makefile.
