# The HolyC language, as implemented by mhc

This documents the language mhc accepts. It follows TempleOS HolyC
(see `third_party/TempleOS/Doc/HolyC.DD`) with the deviations listed at
the end.

## Types

| type  | meaning                    |
|-------|----------------------------|
| `U0`  | void, and **zero size**    |
| `I8`/`U8`   | signed/unsigned byte |
| `I16`/`U16` | 16-bit               |
| `I32`/`U32` | 32-bit               |
| `I64`/`U64` | 64-bit               |
| `F64` | 8-byte float (there is no F32) |
| `Bool`| alias for `U8` (prelude)   |

All values widen to 64 bits when loaded; all arithmetic happens on 64-bit
values (or F64). Storing truncates to the declared width. Assignment
evaluates to the *pre-truncation* value, exactly like TempleOS:

```holyc
I16 i1;
I32 j1;
j1 = i1 = 0x12345678;   // i1 is 0x5678 but j1 is 0x12345678
```

Pointers (`U8 *p`) are 8 bytes. Pointer arithmetic is scaled by the element
size, and fixed-size arrays (`I64 a[10]`) decay to pointers in expressions.

## No main()

Code outside functions executes at startup, in order:

```holyc
"first\n";
U0 F() { "third\n"; }
"second\n";
F;
```

Global variable initializers are part of that startup code and run in
declaration order.

## Functions

```holyc
U0 Test(I64 i=4, I64 j, I64 k=5)
{
  "%X %X %X\n", i, j, k;
}
Test(,3);    // 4 3 5 — holes and missing args take defaults
Test;        // error: j has no default
```

* Default arguments may appear in **any** position; empty argument slots
  (`f(,3)`) select the default.
* A call with no needed parentheses can drop them: `Dir;` calls `Dir()`.
  Any use of a function name without `(` calls it — except after `&`,
  which yields the function's address for callbacks.
* Variadic functions declare `...` and read the extra args through the
  implicit `I64 argc` and `I64 argv[]`:

```holyc
I64 AddNums(...)
{
  I64 i, res = 0;
  for (i = 0; i < argc; i++)
    res += argv[i];
  return res;
}
```

* `public` exports a function or global as an unmangled symbol so other
  objects can `extern` it — see "Separate compilation" in
  [usage.md](usage.md). In whole-program builds it is a no-op.
* `interrupt`, `haserrcode`, `argpop`, `noargpop`, `reg`, `noreg` are
  accepted and ignored (they only mean something inside TempleOS).

## Implicit print statements

A string literal statement prints itself. Arguments follow after commas.
A char literal statement goes to `PutChars()`. An empty string means the
format string is a variable; an empty char literal means the value is an
expression:

```holyc
"Hello World!\n";
"%s age %d\n", name, age;
"" fmt, name, age;    // Print(fmt, name, age)
'*';                  // PutChars('*')
'' drv;               // PutChars(drv)
```

## Operators

Precedence, tightest first (this is TempleOS's order — note shifts bind
tighter than multiplication):

```
`  <<  >>
*  /  %
&
^
|
+  -
<  >  <=  >=      (chainable)
==  !=
&&
^^                (logical xor)
||
=  +=  -=  *=  /=  %=  &=  |=  ^=  <<=  >>=
```

* `` a`b `` raises `a` to the power `b` and always yields `F64`.
* Comparisons chain: `5 < i < j + 1 < 20` means
  `5<i && i<j+1 && j+1<20`, with each middle term evaluated once.
* There is **no** `?:` operator.
* Type casting is **postfix**: `ptr(CDog *)`, `x(I64)`. `ToI64()`,
  `ToF64()` and `ToBool()` also exist and are clearer for numeric
  conversion.
* A char constant can hold up to 8 characters packed little-endian:
  `'ABC'` is `0x434241`, and `PutChars('OK!\n')` prints all of them.

## Statements

`if/else`, `while`, `do...while`, `for`, `goto`, `break`, `return` are as
in C. There is **no `continue`** — use `goto`, as Terry intended. Labels
are `name:`.

### switch

`switch` supports auto-incrementing caseless cases, ranges, and
sub_switch porches:

```holyc
switch (i) {
  case: "Zero\n"; break;       // starts at 0
  case: "One\n"; break;        // previous + 1
  case 5...8: "5-8\n"; break;  // ranges
  default: "Other\n"; break;
  start:                       // sub_switch: the porch runs before
    "[";                       // every grouped case...
    case 10: "Ten"; break;     // break inside the group jumps to end:
  end:
    "]";                       // ...and the end porch runs after
    break;
}
```

`switch [i]` (unbounded, no range check) is accepted and compiles like
`switch (i)`.

## Classes

`class` declares a record; a single parent gives inheritance. There is no
`typedef` and no methods — functions take pointers:

```holyc
class CAnimal { I64 age; };
class CDog : CAnimal { U8 name[32]; };

CDog *d = MAlloc(sizeof(CDog));
d->age = 3;
```

`union` works the same way with overlapping members. `sizeof(type|expr)`
and `offset(Class.member)` are compile-time constants.

## Exceptions

`throw(ch)` throws an exception carrying up to 8 chars. Catch blocks run
while the handler search is in progress: a catch that wants to *consume*
the exception must say so with `Fs->catch_except = TRUE` (or call
`PutExcept`), otherwise the search continues with the next outer handler,
and an unconsumed exception terminates the program. On native backends,
`Fs` and the handler stack are local to each host thread (see
[memory.md](memory.md) for the full thread-local story):

```holyc
try {
  throw('oops');
} catch {
  "%c\n", Fs->except_ch;
  Fs->catch_except = TRUE;
}
```

## Preprocessor

`#include "file"` (no `<>` form), object-like `#define NAME tokens`,
`#undef`, `#ifdef/#ifndef/#else/#endif`. There are no function-like
macros ("I'm not a fan" — T. Davis). `#exe{...}` runs the block at
compile time inside the compiler and splices its `StreamPrint` output
into the stream, like TempleOS; see `doc/exe.md` for the design, the
extra API available inside blocks, and the limitations.

The prelude defines `TRUE`, `FALSE`, `NULL`, `ON`, `OFF`, `Bool`,
`I64_MAX`, `I64_MIN` and declares the runtime API (see below).

## Runtime library

Console: `Print(fmt,...)`, `PutChars(i64)`, `PutS(s)`, `GetChar()`,
`GetStr(prompt=NULL)`.
Memory: `MAlloc`, `CAlloc`, `Free`, `MSize`, `MemCpy`, `MemSet`, `MemCmp`.
Strings: `StrLen`, `StrCpy`, `StrCat`, `StrCmp`, `StrNew`,
`StrPrint(dst,fmt,...)`, `MStrPrint(fmt,...)`,
`StrPrintJoin(dst,fmt,argc,argv)` (varargs forwarding, TempleOS style).
Math: `Sqrt Sin Cos Tan ASin ACos ATan Exp Ln Log10 Log2 Ceil Floor Abs
AbsI64 Round ToI64 ToF64 ToBool MinI64 MaxI64 Seed RandI64 Rand`.
Exceptions: `throw(ch=0)`, `PutExcept(catch_it=TRUE)`, `Fs->except_ch`,
`Fs->catch_except`.
Misc: `Exit(code=0)`.

`Print` supports `%d %u %x %X %o %c %s %f %e %g %p %%` with `-`, `0`,
width and precision. `%c` prints all packed characters of its argument.
Note there is no type inference in formats: `%f` expects an `F64`
argument, `%d` an integer.

## Deviations from TempleOS

mhc targets normal OSes with portable backends, so:

* **No inline `asm{}`** — rejected with an error.
* `#exe{}` works at compile time only (`doc/exe.md`); the runtime half
  of the TempleOS compiler API (`ExePrint`, `ExeFile`, `StreamExePrint`,
  `RunFile`) is absent, since final binaries contain no compiler.
* `U0 *` pointer arithmetic advances by 1 byte (TempleOS adds 0; Terry's
  own guidelines say don't use `U0 *`).
* `reg`/`noreg` are parsed but have no effect; there are no register
  variables.
* Sub-int access on plain integers (`i.u8[3]`), `lastclass`, and class
  member metadata are not supported.
* `lock{}` compiles its body without atomicity.
* Graphics, tasks, and everything tied to the TempleOS kernel are absent;
  the runtime is a small portable console library.
* Exception `try` nesting is limited to 256 frames; jumping out of a
  `try{}` block with `goto` is undefined (use `return` or exceptions).
* The JS backend represents I64 as a JS number: exact only to 53 bits.
