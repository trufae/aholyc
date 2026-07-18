// Class layout the TempleOS way: packed members, sizeof/offset, and
// '$$' to place the next member at an explicit offset. See doc/struct.md.

// members are packed back to back, no padding (unlike C)
class CPacked
{
  U8  a;
  U16 b;
  U8  c;
  I64 d;
};
"packed: %d %d %d %d sizeof=%d\n",
  offset(CPacked.a), offset(CPacked.b), offset(CPacked.c),
  offset(CPacked.d), sizeof(CPacked);

// $$ = n places the next member at an explicit offset
class CGap
{
  U8 magic;
  $$ = 8;
  I64 value;
};
"gap: %d %d sizeof=%d\n", offset(CGap.magic), offset(CGap.value), sizeof(CGap);

// inside the body, $$ reads back the current offset
class CSkip
{
  U8 a;
  $$ = $$ + 3;
  U32 b;
};
"skip: %d %d sizeof=%d\n", offset(CSkip.a), offset(CSkip.b), sizeof(CSkip);

// moving $$ backward overlays members, like a union
class COverlay
{
  U32 whole;
  $$ = 0;
  U8 bytes[4];
};
COverlay o;
o.whole = 0x04030201;
"overlay: %d %d %d %d sizeof=%d\n",
  o.bytes[0], o.bytes[1], o.bytes[2], o.bytes[3], sizeof(COverlay);

// trailing $$ statements set the final size; several in a row are fine
class CFixed
{
  U8 tag;
  $$ = 16;
  $$ = $$ + 16;
};
"fixed: sizeof=%d\n", sizeof(CFixed);

// negative offsets grow the class downward (see Demo/Lectures/NegDisp.HC)
class CNeg
{
  $$ = -16;
  I64 lo;
  I64 hi;
};
"neg: %d %d sizeof=%d\n", offset(CNeg.lo), offset(CNeg.hi), sizeof(CNeg);
I64 base = MAlloc(sizeof(CNeg));
CNeg *p = base + 16; // bias the pointer past the negative members
p->lo = 7;
p->hi = 9;
"neg vals: %d %d\n", p->lo, p->hi;
Free(base);

// unions overlap members at the union base; $$ moves the base
union UReg
{
  U8 bytes[8];
  $$ = 4;
  U32 hi;
};
UReg r;
r.bytes[4] = 42;
r.bytes[5] = 0;
r.bytes[6] = 0;
r.bytes[7] = 0;
"union: %d %d sizeof=%d hi=%d\n",
  offset(UReg.bytes), offset(UReg.hi), sizeof(UReg), r.hi;

// outside a class, $$ is the current address in the code
U8 *here = $$;
"rip: %d\n", here != 0;
