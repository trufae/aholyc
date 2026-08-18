# RFC: HolyC Test Suite for aholyc

**Status:** Draft  
**Date:** 2026-08-17  
**Author:** pancake

## Motivation

aholyc currently tests through a shell harness (`tests/run.sh`) that compiles
examples, runs them, and diffs stdout against expected output. This works but
has limitations:

- Tests are written in shell, not HolyC -- library authors cannot ship tests
  with their code without adopting the aholyc build system.
- No structured pass/fail per-assertion; a single wrong character on stdout
  means the entire test is a failure with no granularity.
- No in-language assertion vocabulary; testing logic lives in external scripts.
- Third-party HolyC code has no portable way to self-test across compilers.

A HolyC-native test suite would let any program self-test with `aholyc run test.HC`,
making tests portable across aholyc, holyc-lang, and (where feasible) TempleOS.

## Survey of Existing Approaches

### TempleOS OSTestSuite

`TempleOS/Misc/OSTestSuite.HC` launches each demo in a child `CTask`, sends
keyboard/mouse events via `PostMsgWait`, sleeps, and kills the task. There are
no assertions or pass/fail results -- the suite is purely visual/integration.
It exercises the full GUI stack, filesystem, and hardware. Completely unsuitable
for CI or headless use. **Not compatible, not worth emulating.**

### holyc-lang test suite

`third_party/holyc-lang/src/tests/` contains ~70 numbered `.HC` files, each a
standalone program with a `Main()` entry point. The pattern:

```holyc
#include "testhelper.HC"

I32 Main() {
  I64 correct = 0, tests = N;
  // ... per-check logic ...
  PrintResult(correct, tests);
  return 0;
}
```

`testhelper.HC` provides:

```holyc
public U0 PrintResult(I64 correct, I64 total) {
  if (correct != total)
    "\033[0;31mFAILED: %d/%d\033[0;0m\n", correct, total;
  else
    "\033[0;32mPASSED: %d/%d\033[0;0m\n", correct, total;
}
```

`run.HC` auto-discovers `.HC` files, compiles each with the local `hcc`, runs
the resulting binary, and reports. `run_jit.HC` does the same with `-jit`.
Tests are sorted numerically so `01_pointer_simple` runs before `64_sret_x8`.

**This is the most relevant model.** We should be compatible where it costs
nothing, and diverge only where we can do better.

### aholyc shell harness

`tests/run.sh` is a 1300-line POSIX shell script. Each example in `examples/`
is compiled on every available backend (c, llvm, js), run, and its stdout
compared with `tests/expected/<name>.out`. Additional sections test compiler
flags (`-fno-asm`, `-fno-pic`, `-shared`, `-sarchive`, `-fno-exceptions`),
error diagnostics, source hints, separate compilation, C library linking,
variadic FFI, formatting, and more.

This is the authoritative regression suite for the compiler itself. The HolyC
test suite proposed below complements it -- not replaces it.

## Design

### Guiding Principles

1. **HolyC-native.** Tests are `.HC` files that compile with `aholyc run`.
2. **Self-contained.** Each test is a standalone program; no external runner
   required (though a runner is provided).
3. **Compatible with holyc-lang.** Adopt their `testhelper.HC` API verbatim.
   Anyone who switches compilers can reuse tests.
4. **Backward-compatible with aholyc.** The existing `tests/run.sh` harness
   continues to test examples and compiler flags. The new suite adds
   HolyC-language-level conformance tests.
5. **CI-friendly.** Exit status 0 = all pass, 1 = failure. Machine-readable.

### API (testhelper.HC)

Port holyc-lang's `testhelper.HC` directly, adding a few extras:

```holyc
// --- Core (compatible with holyc-lang) ---

public U0 PrintResult(I64 correct, I64 total) {
  if (correct != total)
    "\033[0;31mFAILED: %d/%d\033[0;0m\n", correct, total;
  else
    "\033[0;32mPASSED: %d/%d\033[0;0m\n", correct, total;
}

// --- Extensions (aholyc-specific, guarded) ---

// Global pass/fail counter for the entire program.
// Test functions increment these; Main() checks at the end.
public I64 g_test_pass = 0;
public I64 g_test_fail = 0;

public U0 AssertTrue(I64 cond, U8 *msg) {
  if (cond) {
    g_test_pass++;
  } else {
    g_test_fail++;
    "  \033[0;31mASSERT FAILED: %s\033[0;0m\n", msg;
  }
}

public U0 AssertEqI64(I64 got, I64 expected, U8 *msg) {
  if (got == expected) {
    g_test_pass++;
  } else {
    g_test_fail++;
    "  \033[0;31mASSERT FAILED: %s (got %d, expected %d)\033[0;0m\n",
      msg, got, expected;
  }
}

public U0 AssertEqF64(F64 got, F64 expected, F64 eps, U8 *msg) {
  if (got > expected - eps && got < expected + eps) {
    g_test_pass++;
  } else {
    g_test_fail++;
    "  \033[0;31mASSERT FAILED: %s (got %f, expected %f)\033[0;0m\n",
      msg, got, expected;
  }
}

public U0 AssertStrEq(U8 *got, U8 *expected, U8 *msg) {
  if (!StrCmp(got, expected)) {
    g_test_pass++;
  } else {
    g_test_fail++;
    "  \033[0;31mASSERT FAILED: %s (got \"%s\", expected \"%s\")\033[0;0m\n",
      msg, got, expected;
  }
}

// Final summary. Call from Main() after all tests.
public I64 TestSummary() {
  I64 total = g_test_pass + g_test_fail;
  PrintResult(g_test_pass, total);
  if (g_test_fail) Exit(1);
  return 0;
}
```

The `Assert*` helpers are **not** part of holyc-lang's API. They live in
aholyc's copy of `testhelper.HC` and are guarded with `#ifdef AHOLYC` if
cross-compiler portability is needed.

### Directory Layout

```
tests/
  run.sh              # existing shell harness (unchanged)
  expected/           # existing expected-output files (unchanged)
  hctest/             # NEW: HolyC-native test suite
    testhelper.HC     # assertion library
    run.HC            # test runner (auto-discovers and runs all tests)
    01_types.HC       # type sizes, alignment, sizeof
    02_operators.HC   # arithmetic, bitwise, comparison
    03_strings.HC     # string ops, literals, concatenation
    04_control.HC     # if/else, while, for, switch, goto
    05_functions.HC   # call, return, parameters, default args
    06_pointers.HC    # pointer arithmetic, deref, arrays
    07_classes.HC     # struct layout, methods, inheritance
    08_memory.HC      # MAlloc, Free, heap, stack
    09_preprocessor.HC # #define, #include, #if, #ifdef
    10_exceptions.HC  # try/catch/throw
    11_varargs.HC     # variadic functions, ... args
    12_macros.HC      # macro expansion, token pasting
    13_globals.HC     # global init, static, extern
    14_asm.HC         # inline assembly (portable subset)
    15_misc.HC        # sizeof, typeof, enums, labels, auto
```

File naming follows holyc-lang convention: two-digit prefix + descriptive name.
Tests are numbered so a simple `ls` gives execution order.

### Test Runner (run.HC)

A minimal runner modeled after holyc-lang's `run.HC`:

```holyc
#include "testhelper.HC"

U0 RunTest(U8 *filename) {
  U8 buf[512];
  I64 len = snprintf(buf, sizeof(buf), "%s", filename);
  buf[len] = '\0';
  // aholyc compile + execute
  auto res = System(buf);
}

I32 Main(I32 argc, U8 **argv) {
  if (argc > 1) {
    RunTest(argv[1]);
    Exit(0);
  }

  // Run all tests in directory
  // ... (auto-discover .HC files, exclude run.HC/testhelper.HC) ...
  return 0;
}
```

However, the **recommended** workflow is simpler:

```sh
make test-hctest   # compiles and runs each test individually
```

This is a Makefile target that loops over `tests/hctest/[0-9]*.HC` files,
compiles each with `aholyc run`, and checks the exit status. This matches
how holyc-lang's `run.HC` works but stays in shell for compatibility with
the existing `make test` infrastructure.

### Makefile Integration

Add to the Makefile:

```makefile
test-hctest:
	@fail=0; for f in tests/hctest/[0-9]*.HC; do \
		n=$$(basename "$$f" .HC); \
		if ./aholyc run "$$f" >/dev/null 2>&1; then \
			echo "ok   hctest/$$n"; \
		else \
			echo "FAIL hctest/$$n"; \
			fail=1; \
		fi; \
	done; exit $$fail
```

The existing `test` target calls `test-hctest` as part of its suite.

### Test Structure Pattern

Each test file follows this pattern (compatible with holyc-lang):

```holyc
#include "testhelper.HC"

// Individual checks return Bool or use Assert helpers

I64 TestArithmetic() {
  I64 correct = 0, tests = 4;
  if (2 + 3 == 5) correct++;
  if (10 * 5 == 50) correct++;
  if (100 / 4 == 25) correct++;
  if (7 % 3 == 1) correct++;
  PrintResult(correct, tests);
  return correct == tests;
}

I32 Main() {
  "Test - Arithmetic:\n";
  I64 ok = 0, total = 3;
  if (TestArithmetic()) ok++;
  if (TestBitwise())   ok++;
  if (TestComparison()) ok++;
  PrintResult(ok, total);
  "====\n";
  return ok != total;
}
```

Return value: `0` = all pass, non-zero = failure. This matches holyc-lang
convention and gives the shell harness a clean exit status.

### What to Test

Priority areas (each becomes a numbered test file):

| File | Coverage |
|------|----------|
| `01_types.HC` | sizeof all primitives, pointer size, struct alignment, padding |
| `02_operators.HC` | all arithmetic, bitwise, shift, comparison, boolean, precedence |
| `03_strings.HC` | literal concat, escape sequences, sizeof strings, string ops |
| `04_control.HC` | if/else, while, do/while, for, switch/case/default, goto, break/continue |
| `05_functions.HC` | call/return, default params, function pointers, recursion |
| `06_pointers.HC` | addr-of, deref, pointer arithmetic, array decay, null |
| `07_classes.HC` | struct layout, sizeof classes, member access, nested structs |
| `08_memory.HC` | MAlloc, Free, stack vs heap, MemSet/MemCpy |
| `09_preprocessor.HC` | #define, #if/#ifdef/#else/#endif, #include, token pasting |
| `10_exceptions.HC` | try/catch/throw, exception propagation, nested try |
| `11_varargs.HC` | variadic params, printf-style formatting |
| `12_macros.HC` | macro expansion order, stringification, multi-statement |
| `13_globals.HC` | global init order, static locals, extern declarations |
| `14_asm.HC` | inline asm basic ops (platform-dependent tests guarded) |
| `15_misc.HC` | sizeof, typeof, enum, labels, auto, cast, Bool logic |

### Compatibility Notes

**Things we adopt from holyc-lang (zero cost):**

- `PrintResult()` API and signature
- `testhelper.HC` filename and include convention
- Numbered file naming scheme
- `Main()` returns 0 on success
- ANSI color output for pass/fail

**Things we do differently:**

- Add `Assert*` helpers beyond holyc-lang's `PrintResult` (optional, additive)
- Integrate with `make test` and shell harness (holyc-lang uses its own
  `run.HC` compiled by the local hcc)
- Each test exits non-zero on failure (holyc-lang tests always return 0
  even on failure, relying on stdout parsing by the runner)

**Things we do not adopt:**

- TempleOS GUI-based test orchestration (OSTestSuite) -- incompatible with
  headless/CI use
- holyc-lang's `run_shared.HC` test discovery -- overly complex for a
  small test set; a Makefile glob is simpler and more transparent

## Migration Plan

1. Add `tests/hctest/testhelper.HC` with the API above.
2. Port 3-5 holyc-lang test files directly (e.g. `38_sizeof.HC`, `14_maths.HC`,
   `19_switch.HC`) as proof of compatibility. Adjust only the include path.
3. Add `make test-hctest` target.
4. Port remaining holyc-lang tests and add aholyc-specific tests incrementally.
5. Integrate into CI (GitHub Actions workflow runs `make test` which includes
   both the shell harness and the HolyC suite).

## Open Questions

- Should `Assert*` macros use `#ifdef AHOLYC` guards so the same test files
  compile cleanly on holyc-lang (which lacks them)?
- Should the runner support `--filter=` for selecting tests by name pattern?
- How to handle platform-dependent tests (e.g. inline asm, syscall numbers)?
  Guard with `#ifdef` or skip in the runner?
- Do we have a way to differentiate debug and release builds like Swift#DEBUG?
