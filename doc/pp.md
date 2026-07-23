# The aholyc preprocessor

The preprocessor is token-level: `tokenize()` (in `src/lex.c`) turns source
into a token list, then `lex_preprocess()` (in `src/lexpp.c`) resolves
directives and expands object-macros over that list before parsing. There
is no separate text pass. This mirrors TempleOS HolyC, whose parser
front-end has the preprocessor built in (`third_party/TempleOS/Doc/
PreProcessor.DD`).

This document tracks what is implemented, what is partial, and what is
still missing versus standard HolyC — and doubles as the roadmap for
finishing the preprocessor.

## Directives

| directive | status | standard behavior |
|-----------|--------|-------------------|
| `#include "file"` | ✅ done | include a file; no `<>` form (nor in TempleOS). Also accepts `#include MACRO` where a string body names the file. |
| `#define NAME tokens` | ✅ done | object-like macro. **No function-like macros** — intentional, TempleOS omits them too ("I'm not a fan" — T. Davis). |
| `#undef NAME` | ✅ done | remove a macro. |
| `#if <expr>` | ✅ done | keep the branch if a constant integer expression is non-zero (see below). |
| `#ifdef` / `#ifndef` | ✅ done | keep the branch if a name is / is not defined. |
| `#else` / `#endif` | ✅ done | else arm / close a conditional. Nesting works (`skip_cond` counts any `#if*`). |
| `#assert <expr>` | ✅ done | print a **warning** (not error) during compilation if a constant expression is false; compilation continues. Same expression grammar as `#if`. |
| `#exe {…}` | ✅ done | run HolyC in the compiler at compile time; its `StreamPrint` output is spliced into the source. See [exe.md](exe.md). |
| `#help_index` / `#help_file` | ◐ ignored | TempleOS help-system metadata; parsed and skipped (harmless as comments). |
| `#ifaot` | ❌ missing | include code only in AOT-compiler mode. |
| `#ifjit` | ❌ missing | include code only in JIT-compiler mode. |
| `#pragma …` | ❌ missing | TempleOS-specific pragmas (2 uses); niche. |
| `#elif` | — n/a | **not** standard HolyC (zero uses in TempleOS); aholyc omitting it is faithful, not a gap. |

## `#if` and `#assert` constant expressions

Both collect the rest of the directive line, macro-expand it (`pp_eval_line`),
and evaluate it with a recursive-descent integer evaluator (`pp_or` …
`pp_prim` in `src/lexpp.c`). `#if` keeps/drops its branch; `#assert` warns
(via `warn_tok`, non-fatal) when the value is zero. Semantics:

- **Operators**, in HolyC precedence (tightest first — note shifts bind
  tighter than `*`, unlike C): `<< >>`, then `* / %`, then `&`, `^`, `|`,
  then `+ -`, then `< > <= >=`, then `== !=`, then `&&`, `^^`, `||`, plus
  unary `! ~ - +` and parentheses. So `1<<2*3` is `(1<<2)*3 == 12`, exactly
  as it evaluates at runtime.
- **`defined(NAME)`** and **`defined NAME`** → 1 if the macro is defined,
  else 0. The operand is never macro-expanded.
- Object-like macros in the expression are expanded first; an identifier
  with **no** macro evaluates to `0` (C-style).
- Division/modulo by zero, an empty expression, and trailing tokens are
  compile errors.

Deviation: comparisons are left-associative (`a<b<c` is `(a<b)<c`), i.e.
**not chained**, unlike ordinary HolyC expressions where `5<i<20` chains.
Chaining inside `#if` is a possible future refinement; it is rare in
conditionals.

## Macros

- `#define NAME body` binds an object-like macro; redefinition replaces the
  live entry (so a later `#undef` fully removes it).
- Expansion re-scans, with a self-reference guard (`no_expand`) so
  `#define A A` doesn't loop.
- Hints attached to a macro invocation are inherited by the expansion
  (`inherit_hint`), so `/* @align */ SOMECLASS` works.
- **No function-like macros** and **no `#`/`##`** operators — faithful to
  TempleOS.

## Predefined macros

Set in `lex_reset()` (`src/lex.c`) to expose **HolyC** platform names
(TempleOS style) rather than the host C compiler's macros:

- Architecture (one of): `IS_X86_64`, `IS_ARM_64`, `IS_ARM_32`,
  `IS_POWERPC`, `IS_RISCV`, `IS_MIPS`.
- OS (one of): `IS_MACOS`, `IS_LINUX`, `IS_NETBSD`, `IS_OPENBSD`,
  `IS_FREEBSD`, `IS_WINDOWS`; plus `IS_UNIX` on any Unix.

Inside `#exe {…}` blocks, `__FILE__` and `__DIR__` are defined to the
current file/dir (TempleOS style).

Missing predefined names that standard HolyC has: `__LINE__`,
`__CMD_LINE__` (and `__FILE__`/`__DIR__` outside `#exe`).

## Command-line `-D`

`-Dname` defines `name=1`; `-Dname=value` defines it to `value`. The last
`-D` of a given name wins. To dispatch on a choice, define distinct macros
(`-DUI_GTK4`) and branch with plain `#ifdef` — there is no automatic
`name_value` combo define.

## Deviations from standard HolyC (summary)

- Missing directives: `#ifaot`, `#ifjit`, `#pragma`.
- `#if` comparisons don't chain (runtime expressions do).
- No `__LINE__` / `__CMD_LINE__`; `__FILE__`/`__DIR__` only in `#exe`.
- Intentional (faithful) omissions: no function-like macros, no `#elif`,
  no `#`/`##`.

## Roadmap

Priority order to finish the preprocessor. The `#if`/`#assert` evaluator
(`pp_eval_line` → `pp_or`) already exists, so the remaining directives are
small and share it.

1. ~~**`#assert <expr>`**~~ — **done**: `pp_eval_line` + `warn_tok` (non-fatal
   diagnostic with source location); compilation continues.
2. **`#ifaot` / `#ifjit`** — aholyc has exactly one mode (AOT), so these
   reduce to an always-live / always-dead conditional; wire them into
   `lex_preprocess` next to `#ifdef` using the existing `skip_cond`.
3. **`#pragma`** — either ignore-to-end-of-line (like `#help_*`) with an
   optional warning, or implement the handful TempleOS actually uses.
4. **`__LINE__` / `__CMD_LINE__`** and `__FILE__`/`__DIR__` outside `#exe`
   — predefine/refresh these during preprocessing.
5. *(optional)* chained comparisons in `#if`, to match runtime expression
   semantics.

Non-goals (keep faithful to TempleOS): function-like macros, `#elif`,
token-paste/stringize operators.
