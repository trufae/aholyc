# Sub-int access

Every integer lvalue in HolyC doubles as a little-endian array of
smaller integers. `q.u8[5]` reads byte 5 of `q`, `q.u8[0] = 0xFF`
stores one byte into it, and views chain: `q.i32[1].u8[2]`. This is
faithful to TempleOS, where the builtin int types are declared as
unions over their own bytes (`Demo/SubIntAccess.HC`, `Doc/HolyC.DD`):

```holyc
public I64i union I64   // "I64i" is intrinsic.  We are defining "I64".
{
  I8i i8[8];
  U8i u8[8];
  I16 i16[4];
  U16 u16[4];
  I32 i32[2];
  U32 u32[2];
};
```

ahc builds the same views into the compiler instead of declaring
unions: any `TY_INT` lvalue accepts `.i8 .u8 .i16 .u16 .i32 .u32`, each
a view **strictly smaller** than the int it is applied to. The view
covers exactly the int's bytes, so the index ranges over
`sizeof(base) / sizeof(view)` elements:

| base        | `u8`/`i8` | `u16`/`i16` | `u32`/`i32` |
| ----------- | --------- | ----------- | ----------- |
| `I64`/`U64` | `[8]`     | `[4]`       | `[2]`       |
| `I32`/`U32` | `[4]`     | `[2]`       | —           |
| `I16`/`U16` | `[2]`     | —           | —           |

## Semantics

Byte order is little-endian, matching x86-64 and every ahc backend
(the JS backend's linear memory is an explicitly little-endian
`DataView`):

```holyc
I64 q = 0x123456789ABC;
q.u8[0];    // 0xBC   least significant byte
q.u8[5];    // 0x12
q.u16[1];   // 0x5678 bytes 2..3
q.i32[1];   // 0x1234 high dword
```

A view element is an ordinary lvalue of the view's type. Reads widen
like any load — signed views sign-extend, unsigned views zero-extend —
and writes truncate to the view's width:

```holyc
U16 w = 0xABCD;
w.i8[1];         // -85   (0xAB sign-extended)
w.u8[1];         // 0xAB  (zero-extended)
w.u8[0] = 0x101; // stores 0x01: w == 0xAB01
w.u8[0]++;       // ++/--/OP= work and wrap at the view width
```

## Chained views

A view element of 2 or more bytes is itself an integer lvalue, so views
nest to any depth. Each link narrows the window: `q.i32[1]` is bytes
4..7 of `q`, `.u8[2]` picks byte 2 *of that window* — byte 6 of `q`:

```holyc
I64 q = 0x123456789ABC;
q.i32[1].u8[0];        // 0x34  byte 4 of q
q.i32[0].u8[2];        // 0x78  byte 2 of q
q.i32[0].u16[1].u8[0]; // 0x78  same byte, three links deep
q.i32[0].u8[3] = 0x11; // writes byte 3 of q
```

The offsets fold into a single access: `q.i32[1].u8[2]` compiles to one
byte load at `&q + 1*4 + 2`, not three.

## What counts as a base

The base must be *addressable* — a variable, a dereferenced pointer, or
a class member; TempleOS raises "Must be address, not value" for the
same reason. Globals, locals, `I64`/`U64` parameters, class members and
pointer targets all work:

```holyc
class Pair { I64 a; I64 b; };
Pair pr;
I64 *p = &pr.b;
pr.b.u8[1] = 0x99;  // member base
p->u8[0]   = 0x42;  // pointer base, same byte 0 of pr.b

(q + 1).u8[0];      // error: sub-int access needs an addressable value
```

A view with no index decays to a pointer to the base's first byte, like
any array:

```holyc
U8 *bytes = q.u8;   // == &q, typed U8*
MemCpy(buf, q.u8, 8);
```

## Restrictions

* Views exist only on integers, and only strictly smaller ones:
  `q.u64[0]` on an `I64` and `w.i32[0]` on a `U16` are errors, as in
  TempleOS (whose unions declare no same-size members). `F64` has no
  views — TempleOS registers `F64` as a bare intrinsic, not a union;
  cast its address instead: `(&f)(U8*)[7]`.
* Parameters narrower than 64 bits are rejected as bases (`sub-int
  access on a narrow parameter`). Narrow params live sign-extended in
  full 64-bit slots on every backend; a byte store into the slot would
  desynchronize the extension. Copy the param to a local first.
* Indexing is unchecked, exactly like every other HolyC array: `q.u8[9]`
  is an out-of-bounds access the compiler will not stop.
* On the JS backend an `I64` only holds 53 bits exactly
  (`doc/backends.md`), so views over values wider than that see the
  rounded bit pattern.

## Why it forces memory

TempleOS notes that sub-int access "causes the compiler to not use a
reg for the variable" (`Doc/Tips.DD`). The same is true here for the
same reason: the lowering takes the base's address (`*(U8(*)[8])&q`),
so the C and LLVM backends keep such variables addressable in memory —
the optimizer is free to promote them back when the accesses are
transparent to it.
