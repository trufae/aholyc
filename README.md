# aholyc — another Holy-C compiler

`aholyc` (invoked as `aholyc`) compiles [HolyC](https://templeos.org) — the language Terry A. Davis
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

## Layout

* `src/` — the compiler (lexer, parser, backends, driver)
* `runtime/` — the HolyC runtime (C and JS) and the prelude, embedded into
  the aholyc binary at build time
* `doc/` — [language](doc/language.md), [usage](doc/usage.md),
  [backends](doc/backends.md), [memory](doc/memory.md),
  [hints](doc/hints.md), [internals](doc/internals.md)
* `examples/` — small HolyC programs, used by `make test`
* `third_party/` — reference material (TempleOS sources, holyc-lang)

## Why

TempleOS's compiler JIT-compiled HolyC into a single flat address space.
aholyc keeps the language and the spirit — simplicity, directness, no
dependency sprawl — but targets the world outside the temple: normal
operating systems, normal executables, several code generators.

God's temple ships with an amber screen; aholyc ships with a Makefile.
