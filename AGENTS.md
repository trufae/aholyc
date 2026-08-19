# AGENTS.md

aholyc — a HolyC compiler written in portable C99. Zero external dependencies: build needs only `cc` and `make`.

## Project

- Compiler: `src/` (lexer, parser, backends, driver). Entry point `src/main.c`.
- Backends (`-b`): `llvm` (default, emits textual LLVM-IR for clang/llc), `c` (C99), `js` (node).
- `runtime/` — HolyC runtime (C/JS) + prelude, embedded into the binary at build time via `tools/file2c` → `src/embed.c`.
- `lib/` — HolyC standard library (htk UI, json, http, net, thread, …).
- `examples/`, `tests/` — HolyC programs exercised by `make test`.
- `doc/` — language, usage, backends, memory, hints, pp, internals, format.
- `third_party/` — reference material only; do not edit.

## Commands

- `make` — build `aholyc` + `libaholyc.a`
- `make test` — run examples on every available backend (CI: `make test CC=clang`)
- `make fmt` — normalize all HolyC sources (`aholyc fmt -w examples/*.HC tests/*.HC runtime/*.hc`)
- `make clean` / `make install` / `make uninstall`
- Omit a backend: `make AHOLYC_BACKEND_C=0 AHOLYC_BACKEND_JS=0`
- Compile/run HolyC: `./aholyc prog.HC -o prog`, `./aholyc run prog.HC [args]`
- Format check: `./aholyc fmt -q file.HC` (exit 1 if unformatted)

## Conventions

- Compiler sources are C99 (`-std=gnu99 -Os -Wall -Wextra`); no new external deps.
- Format all HolyC with `aholyc fmt` (2-space indent, function/class `{` on own line); keep it idempotent — `tests/run.sh` verifies.
- New compiler options are CLI flags (see `doc/usage.md`); formatter options are env vars (`AHOLYC_FMT_*`).
- `src/embed.c` and `src/config.h` are generated — don't hand-edit.
- Backends are selected at build time via `AHOLYC_BACKEND_*` defines; keep emitter code independent.
- `libaholyc.a` API (`include/aholyc.h`) is parallel-safe: instances share no mutable state.
- Tests: add `tests/*.HC` + `tests/expected/*.out`; `tests/run.sh` drives per-backend runs.
