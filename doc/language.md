# The HolyC language, as implemented by aholyc

This documents the language aholyc accepts. It follows TempleOS HolyC
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

There is currently no builtin `U128` or `I128` type.  The `@bits=N`
source hint does not create a wider type: it narrows the value width of an
existing integer declaration, and a hint must not exceed that declaration's
storage width.  Consequently, `/* @bits=128 */ U64 x;` is rejected even
though hint values up to 128 are accepted by the lexer.

For a 128-bit storage object, use a class containing two 64-bit halves:

```holyc
class U128 {
	U64 lo;
	U64 hi;
};
```

This provides 16 bytes of storage only; it does not provide native 128-bit
arithmetic, comparisons, shifts, literals, or formatting.  Those operations
must be implemented by helper functions, for example by adding the low
halves and carrying into `hi`.  A real scalar `U128`/`I128` would require
front-end and backend support in aholyc (including the JS backend's numeric
representation).

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

Integer lvalues also expose their bytes and words as little-endian
arrays of smaller ints — `q.u8[5]`, `q.i16[2]`, chained as
`q.i32[1].u8[2]` — exactly like TempleOS. See `doc/subint.md`.

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

For an AOT program launched as an ordinary command-line executable, this
synthetic top-level entry has two implicit parameters: `I64 argc` and
`I64 *argv`. They contain only the arguments supplied by the user; unlike C,
the executable name is not included. `argv[0]` is the first user argument,
`argc` is zero when there are none, and `argv[argc]` is always `NULL`. Each
`argv` slot contains a `U8 *` pointer to a NUL-terminated argument string.

The pair is in top-level scope only. aholyc does not search for or invoke a
function named `Main`; pass the pair explicitly to the entry function you
choose:

```holyc
U0 Main(I64 argc, I64 *argv)
{
  I64 i;
  for (i = 0; i < argc; i++)
    "arg %d: %s\n", i, argv[i];
}

Main(argc, argv);
```

Global startup returns the hosted process status. Falling off the end, or a
bare `return;`, returns zero; use a value to report failure to the invoking
shell:

```holyc
if (!Ready)
  return 1;
return 0;
```

`Exit(code)` still terminates immediately and is useful from inside nested
functions. This is another hosted adaptation: TempleOS `Exit()` takes no
status and terminates the current task, while `RunFile` returns the value from
`LastFun`. aholyc maps the top-level return value to a POSIX-style process
status instead.

This is an aholyc AOT adaptation, not TempleOS `RunFile`/`LastFun` semantics.
Those facilities call a file's last-defined function with forwarded, typed
HolyC arguments. Process arguments here are byte strings delivered only to
the synthetic top-level entry, which must forward them explicitly. The
TempleOS runtime compiler facilities remain outside aholyc's AOT runtime; see
[exe.md](exe.md#the-runtime-half-on-posix).

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
* `=lastclass` as a default passes the class name of the previous
  argument as a string, pointer levels stripped (`I64`, `F64`, `U0` for
  non-class types):

```holyc
U0 StructName(U8 *d, U8 *class_name=lastclass)
{
  "it is a \"%s\".\n", class_name;
}
CDog rex;
StructName(&rex);  // it is a "CDog".
```
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

  Each extra fills one I64 slot; an F64 lands as its bit pattern and is
  read back with the postfix cast, `argv[i](F64)`, which reinterprets
  the bits (`ToF64`/`ToI64` convert numerically, C-style). There is no
  `va_list`: a variadic forwards by passing `argc, argv` to a helper
  declared `(I64 argc, I64 *argv)`, the way `Print` hands off to
  `StrPrintJoin`. A bodiless `extern` declared with `...` is different —
  it imports a real C varargs function such as `printf` and calls it
  with the C ABI (see [usage.md](usage.md)).

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

`throw(ch)` throws an exception carrying up to 8 chars. The argument is a
**char constant** — single quotes, `throw('oops')` — packed into the i64
`Fs->except_ch`, not a `"string"` (which would pass a pointer and print as a
raw address). An unhandled exception prints `Unhandled Exception '<chars>'`,
falling back to hex if the value is not printable. Catch blocks run
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
`#undef`, `#if/#ifdef/#ifndef/#else/#endif`, and `#assert <expr>` (a
compile-time warning when a constant expression is false, same grammar as
`#if`). There are no function-like macros ("I'm not a fan" — T. Davis), and
no `#elif` (as in TempleOS).
See [pp.md](pp.md) for the full preprocessor reference, predefined macros,
and the roadmap of what is still missing versus standard HolyC.

`#if <expr>` keeps its branch when a constant integer expression is
non-zero. The expression may use the arithmetic, bitwise, shift, comparison
and logical operators — evaluated with HolyC's precedence, so `1<<2*3` is
`(1<<2)*3` — plus `defined(NAME)` / `defined NAME`, which is 1 when a macro
is defined. Object-like macros in the expression are expanded first; an
identifier with no macro evaluates to 0.

```holyc
#if defined(DEBUG) && LEVEL >= 2
  "verbose\n";
#endif
```

### `#exe{}` — compile-time execution

`#exe {...}` runs the block *inside the compiler* at compile time and
splices its `StreamPrint` output into the source stream before output-backend
selection, like TempleOS:

```holyc
#exe {StreamPrint("#define BUILT_AT %d\n", Now);}
"compiled at %d\n", BUILT_AT;
```

Blocks share the macro table with the program, may inject any source
(including further directives), and can inspect and rewrite the token
stream after them through `ExeStream`/`ExeStreamSet`. `Cd`, `Now`,
`__FILE__` and `__DIR__` are available; the whole runtime prelude
works inside a block. `#exe` must start its line, and blocks run on
the build machine even when cross-compiling. See [exe.md](exe.md) for
the design, the full API, the limitations, and how the runtime half of
the TempleOS compiler API (`ExePrint`, `ExeFile`, `RunFile`) could be
provided on POSIX.

The prelude defines `TRUE`, `FALSE`, `NULL`, `ON`, `OFF`, `Bool`,
`I64_MAX`, `I64_MIN` and declares the runtime API (see below).

## Runtime library

Console: `Print(fmt,...)`, `PutChars(i64)`, `PutS(s)`, `GetChar()`,
`GetStr(prompt=NULL)`.
Memory: `MAlloc`, `CAlloc`, `Free`, `MSize`, `MemCpy`, `MemSet`, `MemCmp`.
Strings: `StrLen`, `StrCpy`, `StrCat`, `StrCmp`, `StrNew`,
`StrPrint(dst,fmt,...)`, `MStrPrint(fmt,...)`,
`StrPrintJoin(dst,fmt,argc,argv)` (varargs forwarding, TempleOS style).
Bits: `Bsf(val)`/`Bsr(val)` scan a value for the lowest/highest set bit
(-1 if none), `BCnt(val)` counts set bits; `Bt`, `Btc`, `Btr`, `Bts`
and `BEqu(bit_field,bit,val)` test/complement/reset/set a bit in a bit
field through a byte pointer (signed bit offsets, like x86 `BT`), and
return the old bit; `LBtc`, `LBtr`, `LBts`, `LBEqu` are the same but
atomic across threads (TempleOS "locked" forms). These compile to the
native bit instructions: the LLVM backend emits them as intrinsics and
the C backend inlines them via the C compiler.
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

aholyc targets normal OSes with portable backends, so:

* **No inline `asm{}`** — rejected with an error.
* `#exe{}` works at compile time only (`doc/exe.md`); the runtime half
  of the TempleOS compiler API (`ExePrint`, `ExeFile`, `StreamExePrint`,
  `RunFile`) is absent, since final binaries contain no compiler.
  `doc/exe.md` evaluates how it could be provided on POSIX without
  giving up small binaries.
* `U0 *` pointer arithmetic advances by 1 byte (TempleOS adds 0; Terry's
  own guidelines say don't use `U0 *`).
* `reg`/`noreg` are parsed but have no effect; there are no register
  variables.
* Class member metadata is not supported.
* `lock{}` compiles its body without atomicity.
* Graphics, tasks, and everything tied to the TempleOS kernel are absent;
  the runtime is a small portable console library.
* Exception `try` nesting is limited to 256 frames; jumping out of a
  `try{}` block with `goto` is undefined (use `return` or exceptions).
* The JS backend represents I64 as a JS number: exact only to 53 bits.
