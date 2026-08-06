# Assembly blocks

aholyc accepts HolyC's token-oriented assembly block syntax:

```holyc
asm {
	/* target instructions and assembler directives */
};
```

The trailing semicolon after `}` is optional. The preprocessor runs before the
block is parsed, so `#define`, `#if`, and the `IS_*` target macros work inside
it.

## Capability and `-fno-asm`

`HAS_ASM` is predefined as `1` when the selected backend can emit assembly and
asm has not been disabled. Use it to keep a normal HolyC implementation next
to a native one:

```holyc
I64 AddOne(I64 value)
{
#ifdef HAS_ASM
	asm {
		/* target implementation */
	};
	return value;
#else
	return value + 1;
#endif
}
```

`-fno-asm` omits `HAS_ASM` and rejects every `asm {}` block that remains after
preprocessing, at either file or function scope. An asm block in a discarded
`#ifdef HAS_ASM` branch is not part of the compiled program and is allowed.
Defining `HAS_ASM` manually does not re-enable assembly under `-fno-asm`; the
parser still rejects the block.

The C and LLVM backends define `HAS_ASM`. The JS backend does not, so guarded
sources select their portable branch. An unguarded asm block on JS retains its
source-located unsupported-backend error.

aholyc is an assembly adapter, not an assembler. It rewrites the parts of the
TempleOS dialect that differ from native toolchains, then leaves instruction
validation and encoding to GCC or Clang. x86-64 blocks use Intel operand order;
ARM64, RISC-V, MIPS, and S390 blocks use the target assembler's normal syntax.

## File and function scope

A file-scope block becomes C basic assembly or LLVM `module asm`. It can define
a callable symbol and bind it to a HolyC declaration:

```holyc
asm {
_ANSWER::
	MOVQ RAX, 42
	RET
};

public _extern _ANSWER I64 Answer();
```

`_extern ASM_NAME` gives the HolyC function an exact assembler link name. The
assembler body is opaque to the optimizer, so this form always remains a real
call. In particular, `@inline` is rejected on an `_extern` assembler binding.

Inside a HolyC function, a block is emitted as volatile inline assembly. Put
function hints on the function definition, not on the block:

```holyc
/* @inline */
I64 AddOne(I64 input)
{
	I64 noreg value = input;
	asm {
		MOVQ RAX, &value[RBP]
		ADDQ RAX, 1
		MOVQ &value[RBP], RAX
	};
	return value;
}
```

The C backend emits `inline` plus `always_inline`; LLVM emits `alwaysinline`.
`@noinline` works in the same position. The other supported hints keep their
normal ownership: `@bits` belongs to integer objects, `@align` to class layout
or local storage, and `@cflags`, `@ldflags`, and `@pkgconfig` to the
translation unit.

## Local addresses

`&value[RBP]` is the original TempleOS x86 spelling for a stack local, as used
by `Demo/Asm/AsmAndC1.HC`. aholyc accepts it without relying on a physical stack
offset: it supplies `&value` as a named compiler operand and substitutes the
register chosen by the native compiler.

Function blocks also accept `&value` as an aholyc extension for visible locals
and parameters. It expands to a register containing the object's address. The
instruction still uses the target's memory-address syntax:

```asm
MOVQ RAX, [&value]    // x86-64
ldr  x0,  [&value]    // ARM64
ld   a0,  0(&value)   // RISC-V
ld   $2,  0(&value)   // MIPS
lg   %r2, 0(&value)   // S390
```

If the name is not a visible local or parameter, TempleOS's `&symbol` spelling
is retained as a direct assembler symbol. Taking a local address makes its
storage observable, and the block has a compiler memory barrier. Writes made
through the address are therefore visible to following HolyC statements.

Inline blocks conservatively declare memory, condition codes where applicable,
and the target ABI's caller-saved integer registers as clobbered. Assembly must
preserve the stack pointer, frame pointer, and other callee-saved registers.
Calls made inside a block must also obey native stack alignment and calling
conventions.

## Labels and location

| HolyC syntax | Meaning |
| --- | --- |
| `name::` | Define and export a global assembler label. |
| `name:` | Define a non-exported assembler label. |
| `@@name:` | Define a label local to this `asm` block. |
| `@@name` | Refer to that block-local label. |
| `$$` | The assembler's current location, emitted as `.`. |

Each block gets a unique prefix for `@@` labels, so identical local names in
different blocks do not collide.

## TempleOS directives

| Directive | aholyc behavior |
| --- | --- |
| `DU8`, `DU16`, `DU32`, `DU64` | Emit 1, 2, 4, or 8-byte values. The statement must end in `;`. |
| `count DUP(value)` | Repeat `value` within a `DU*` statement. |
| `ALIGN boundary, fill` | Emit native `.balign boundary, fill`; x86 `OC_NOP` becomes `0x90`. |
| `ORG expression` | Emit native `.org`; native object-format restrictions apply. |
| `USE16`, `USE32`, `USE64` | Emit x86 `.code16`, `.code32`, or `.code64`. |
| `IMPORT name, ...;` | Declare native assembler symbols with `.extern`. |
| `LIST`, `NOLIST` | Accepted as no-ops because aholyc does not produce an assembler listing. |
| `BINFILE "path";` | Emit native `.incbin`; the assembler resolves the path. |
| `I8`/`U8` through `I64`/`U64` | Translate x86 memory-size qualifiers to `byte ptr` through `qword ptr`. |

`I0`, `U0`, and `F64` occur in TempleOS's assembly keyword table, but the
original operand parser does not accept them as memory-size qualifiers. aholyc
likewise leaves such invalid uses for the target assembler to diagnose.

Strings in every `DU*` statement are emitted as raw bytes and do **not** gain a
terminating zero, matching TempleOS. For example:

```holyc
asm {
_DATA:
	DU8 "abc", 0;
	DU16 4 DUP(0x1234);
};
```

`DU*`, `IMPORT`, and `BINFILE` may span physical lines, but their terminating
semicolon is required.

## Native dot directives

Lines beginning with a dot pass through to the native assembler. Thus `.byte`,
`.ascii`, `.string`, `.short`, `.long`, `.quad`, and target-specific directives
can be used directly when that assembler supports them.

`.string` normally appends a zero byte, whereas a string used with `DU*` does
not. `.dword` is target-dependent; Apple ARM64 emits an 8-byte doubleword,
while an x86 assembler need not accept the spelling. Prefer `DU32` or `DU64`
when the intended width should be portable across assemblers.

## Backends and targets

The C backend uses GNU-style `__asm__`, so assembly requires GCC or Clang. The
LLVM backend uses `module asm` and side-effecting inline-asm calls. The JS
backend reports a source-located error.

LLVM IR and bitcode can contain assembly text, but that text is not portable
IR. It remains tied to the architecture, assembler dialect, ABI, and object
format selected when aholyc was built. Compile such IR or bitcode for the same
target.

Runnable syscall, data, and function-local examples are in
[`examples/asm`](../examples/asm/README.md).
