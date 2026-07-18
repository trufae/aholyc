# Classes, unions and the `$$` offset

How aholyc lays out `class` and `union` types, what `sizeof` and `offset`
report, and how `$$` lets you place members at explicit offsets — all
faithful to the TempleOS compiler (`Compiler/PrsVar.HC`), which treats a
class as a byte map you draw yourself, not something the compiler is
allowed to rearrange.

## Packed layout

Members are laid out in declaration order, **packed back to back with no
alignment and no padding** — where C would insert holes, HolyC does not:

```holyc
class CPacked
{
  U8  a;  // offset 0
  U16 b;  // offset 1
  U8  c;  // offset 3
  I64 d;  // offset 4
};          // sizeof(CPacked) == 12   (C would say 24)
```

* `sizeof(Class)` and `offset(Class.member)` are compile-time constants
  over exactly this layout.
* Single inheritance (`class CDog : CAnimal`) places the parent's
  members first; the child's own members start at `sizeof(parent)`.
* `union` members all share the union base (offset 0 by default); the
  union's size is the end of its widest member.
* The layout is computed once in `parse_class()` (`src/parse.c`) and
  every backend consumes the resulting byte offsets, so the same class
  is byte-identical on `c`, `llvm` and `js`.

Packing means unaligned loads and stores. x86-64 shrugs; if you ever
target something stricter, order members widest-first like the TempleOS
sources do.

## `$$` — the offset cursor

Inside a `class` or `union` body, `$$` is the offset at which the next
member will land. A statement of the form

```holyc
$$ = expression;
```

moves that cursor: the expression is any compile-time constant, and it
may itself read `$$`. This is the TempleOS idiom for matching a layout
that some external thing already fixed — a file header, a packet, a
foreign struct. aholyc itself uses it in `runtime/exe.hc` to pin the HolyC
`Token` class to the C compiler's aligned `struct Token`.

```holyc
class CHdr
{
  U8 magic;      // offset 0
  $$ = 8;
  I64 value;     // offset 8, skipping 7 bytes of reserved space
  $$ = $$ + 4;   // skip 4 more bytes past 'value'
  U32 crc;       // offset 20
};                 // sizeof == 24
```

The rules, exactly as in TempleOS:

* **Forward** moves leave a gap; the gap bytes exist but are unnamed.
* **Backward** moves overlay members, so you can build union-like views
  without a union:

  ```holyc
  class COverlay
  {
    U32 whole;
    $$ = 0;
    U8 bytes[4];  // aliases the bytes of 'whole'
  };                // sizeof == 4
  ```

* **Trailing** `$$ = n;` statements are allowed — with no member after
  them they simply set where the class ends, e.g. reserving space:

  ```holyc
  class CSector { U8 tag; $$ = 512; };  // sizeof == 512
  ```

* In a **union**, `$$ = n;` moves the union base: members declared after
  it start at `n` instead of 0. The size is still the furthest end seen.

  ```holyc
  union UReg
  {
    U8 bytes[8];  // offset 0
    $$ = 4;
    U32 hi;       // offset 4, aliasing bytes[4..7]
  };                // sizeof == 8
  ```

* Several `$$ = n;` in a row are fine, and stray `;` in a body is
  ignored, as in the original parser.

### Negative offsets

`$$` may go negative. Members then sit *below* the object pointer, and
the most negative offset grows `sizeof` (TempleOS `neg_offset`): the
class occupies `[lowest offset, last position]` and `sizeof` is that
span. This mirrors `Demo/Lectures/NegDisp.HC`, which Terry used to get
short signed x86 displacements:

```holyc
class CNeg
{
  $$ = -16;
  I64 lo;   // offset -16
  I64 hi;   // offset -8
};            // sizeof == 16

I64 base = MAlloc(sizeof(CNeg));
CNeg *p = base + 16;   // bias the pointer past the negative members
p->lo = 7;             // touches base[0..8)
```

You allocate normally and bias the pointer yourself — exactly what the
TempleOS demo does with `MAlloc(sizeof(Person))(I64)+128`.

### One honest quirk, kept on purpose

`sizeof` is the **last** cursor position (plus the negative span), not
the furthest byte ever reached. Rewind `$$` and leave it there, and the
class is smaller than its members:

```holyc
class CQuirk { I64 a; $$ = 1; };  // sizeof == 1, 'a' still at offset 0
```

TempleOS behaves the same way; if you rewind to overlay, either declare
the wide member last or re-advance `$$` before the closing brace.

## `$$` outside a class

In ordinary expression context `$$` is the **current code address** —
the TempleOS instruction pointer. aholyc compiles it to a tiny runtime call
(`__hc_rip`) whose return address is the generated code right after the
point of use:

```holyc
U8 *here = $$;
"%p\n", here;
```

* `c` and `llvm` backends: a real address inside the compiled program.
* `js` backend: JavaScript has no code addresses, so the runtime hands
  out distinct, monotonically increasing fake ones — comparisons and
  ordering still behave.

TempleOS gives `$$` a third meaning inside `asm { }` blocks (the
instruction's own address); aholyc has no inline assembler, so that meaning
does not apply.
