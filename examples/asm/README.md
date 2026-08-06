# Native assembly examples

These examples issue `write(2)` directly on Linux x86-64, ARM64, RISC-V 64,
and MIPS64 N64, plus ARM64 Darwin. Build the file matching the host:

```sh
./aholyc run -b c examples/asm/x86_64_linux.HC
./aholyc run -b llvm examples/asm/inline_x86_64.HC
./aholyc run -b llvm examples/asm/arm64_linux.HC
./aholyc run -b llvm examples/asm/arm64_darwin.HC
./aholyc run -b c examples/asm/data_directives.HC
```

The Linux syscall files use a top-level `asm {}` block to define `_RAW_WRITE`,
then bind that exact assembler symbol to a HolyC declaration with
`_extern _RAW_WRITE`. The ARM64 Darwin example instead puts the syscall in an
`@inline` HolyC function and uses `&local` address operands to move its
arguments into the Darwin syscall registers. The C and LLVM backends pass the
instruction stream to their native assembler. Consequently, LLVM IR and
bitcode containing assembly are tied to the architecture and object format
they were generated for.

The x86-64 example intentionally uses HolyC's Intel-order, size-suffixed
mnemonics. The other examples use the normal spelling accepted by the target
assembler.

`inline_x86_64.HC` follows TempleOS's `Demo/Asm/AsmAndC1.HC` convention for
accessing a function local as `&name[RBP]`. aholyc turns that spelling into a
real compiler-managed address operand, so it does not depend on a guessed
stack-frame displacement.

`data_directives.HC` shows the portable TempleOS `DU*`/`DUP` spelling and
native assembler directives. `.byte` and `.string` are passed through. The
`.dword` example is ARM64-only because dot-directive names and widths belong
to the selected assembler, not to HolyC; Apple's ARM64 assembler emits it as
an eight-byte doubleword.
