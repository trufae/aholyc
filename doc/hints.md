# aholyc source hints

`aholyc` may recognize annotations written inside comments.  They are
optional compiler hints: an official HolyC compiler ignores them as comments,
so adding a hint does not require a new keyword or type in the source
language.

Hints are an aholyc extension and are not part of TempleOS HolyC.  Unless a
hint is documented as changing semantics, an implementation may ignore it.
Hints are enabled by default; pass `-fno-hints` to make aholyc treat their
annotations as ordinary comments.

## `@bits`

`@bits` requests a narrower integer representation for a declaration:

```holyc
/* @bits=1 */ U8 ready;
/* @bits=4 */ U8 small_value;
/* @bits=53 */ U64 exact_number;
```

The requested width is an LLVM-level optimization hint.  LLVM represents
these values as integer types such as `i1`, `i4`, and `i53` when that is
profitable.  The width must be in the range 1 through 128 and must not exceed
the declared integer type's width.  Invalid widths and uses on non-integer
declarations are compile errors.

`@bits=1` is useful for boolean-like values.  It does not turn `U8` into a
new HolyC type, and it does not change the source-level declaration seen by
the official compiler.

The C backend uses the declared type's signedness to select
`signed _BitInt(N)` or `unsigned _BitInt(N)`.  It may use that as the storage
type for an unaliased local; objects whose normal storage or ABI must remain
visible are instead converted through `_BitInt(N)` at value boundaries.
Because ISO C requires a signed `_BitInt` width of at least two, signed
`@bits=1` uses ordinary storage plus an equivalent low-bit sign extension
to `0` or `-1`.  The JavaScript backend ignores `@bits`.

### Memory and address-taking

An LLVM `i1` value is one bit in SSA/register form, but an addressable object
does not necessarily occupy one bit in memory.  To preserve HolyC's pointer
and layout semantics, aholyc should normally keep hinted objects at their
ordinary storage size and use the narrower representation after loading:

```text
memory:  U8
loaded:  i1
compute: i1
stored:  i1 -> U8
```

An implementation must not silently bit-pack a global, class member, array
element, or object whose address is observable.  Bit-packing changes offsets,
aliasing, and pointer behavior.  A true packed representation requires an
explicit future design for containers and masked accesses.

For a local whose address is never taken, the backend may use the requested
LLVM width throughout the function.

### Values and conversions

The hint does not by itself define how values outside the requested range are
handled.  Until a stricter hint is specified, conversions should retain
HolyC's normal truncation behavior.  In particular, `@bits=1` should not be
assumed to mean that every nonzero value is automatically converted to one.

Code that requires a boolean invariant should explicitly produce `0` or `1`.

## Natural alignment

HolyC class fields are packed by default. Bare `@align` opts into the natural
C-style alignment defined by each field or variable's type. `@align=N` instead
selects an explicit byte boundary, where `N` must be a positive power of two.
No named values are accepted. Placing the hint before a `class` or `union`
applies that policy to every member and pads the final size to the selected
aggregate alignment:

```holyc
/* @align */ class CHeader {
	U8 tag;     // offset 0
	I64 value;  // offset 8
	U8 flags;   // offset 16; sizeof(CHeader) == 24
};
```

For example, `@align=4` on the same class places `value` at offset 4, `flags`
at offset 12, and pads the size to 16. It applies a uniform four-byte boundary
to each field rather than selecting each field's natural alignment.

Placing an alignment hint before one field aligns only that field. Once any
field uses the hint, the final class size is padded to the selected aggregate
alignment so arrays and nested instances remain correctly aligned:

```holyc
class CMixed {
	U8 tag;
	/* @align */ I64 value; // offset 8
	U8 flags;               // offset 16; sizeof(CMixed) == 24
};
```

Inside a function, the hint requests natural or explicit alignment for that
local in the stack frame:

```holyc
/* @align */ I64 value;
/* @align=16 */ U8 buffer[32];
```

An explicit `$$ = n` still moves the layout cursor. A subsequent aligned
field is placed at the first requested boundary at or after that cursor.
Without `@align`, class layout retains TempleOS-compatible packing. With
`-fno-hints`, all `@align` annotations are ignored as ordinary comments.
The JavaScript backend also ignores alignment hints and retains packed layout.

## Function inlining

`@inline` requests inlining of a function, while `@noinline` requests that a
function not be inlined:

```holyc
/* @inline */ I64 Small(I64 x) { return x + 1; }
/* @noinline */ I64 Boundary(I64 x) { return Small(x); }
```

The LLVM backend emits `alwaysinline` and `noinline`, respectively. The C
backend emits the plain `inline` keyword for `@inline` and the compiler
`noinline` attribute for `@noinline`. The JavaScript backend ignores both.

## Exception and effect hints

The compiler may infer whether a function can throw.  Optional annotations
can provide information that is unavailable across separately compiled
modules or through function pointers:

```holyc
/* @noexcept */ U0 Cleanup();
```

`@noexcept` is a promise, not a request to suppress exceptions.  If aholyc
can prove that the function may throw, it should diagnose the annotation.
Knowing that a call cannot throw allows a local `try` handler to be lowered
as direct branches instead of using the dynamic exception machinery.

Checked arithmetic, in contrast, cannot be inferred from ordinary HolyC
arithmetic because existing HolyC code relies on its normal integer
semantics.  It therefore needs an explicit future hint, for example:

```holyc
/* @checked */ I64 result;
```

The exact scope and overflow behavior of checked arithmetic are not yet part
of the language.  A future implementation should specify whether the hint
applies to a declaration, expression, or block, and whether signed overflow,
unsigned carry, or both raise an exception.

## Compatibility

Hints must remain inside comments and must not be required to parse ordinary
HolyC.  This preserves source compatibility with the official compiler, but
not necessarily identical behavior: an official compiler ignores semantic
hints such as checked arithmetic.  Programs that must behave identically on
both compilers should use hints only for representation and optimization,
not for required safety checks.
