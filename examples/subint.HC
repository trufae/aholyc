// Sub-int access: integer lvalues expose their bytes and words as
// little-endian arrays of smaller ints, TempleOS style (doc/subint.md).
// Values stay under 53 bits so the JS backend prints them exactly.
I64 q = 0x123456789ABC, q1;

"q\t\t=%X\n", q;
q1 = q.u8[0];
"q.u8[0]\t\t=%X\n", q1;
q1 = q.u8[5];
"q.u8[5]\t\t=%X\n", q1;
q1 = q.u16[1];
"q.u16[1]\t=%X\n", q1;
q1 = q.i16[2];
"q.i16[2]\t=%X\n", q1;
q1 = q.u32[0];
"q.u32[0]\t=%X\n", q1;

// chained views: pick a dword, then a byte inside it
q1 = q.i32[0].u8[2];
"q.i32[0].u8[2]\t=%X\n", q1;
q1 = q.i32[1].u8[0];
"q.i32[1].u8[0]\t=%X\n", q1;
q1 = q.i32[0].u16[1].u8[0];
"q.i32[0].u16[1].u8[0]=%X\n", q1;

// writes store into the middle of q
q.u8[0] = 0xFF;
q.u16[1] = 0xBEEF;
q.i32[1] = 0x7777;
"q\t\t=%X\n", q;
q.i32[0].u8[3] = 0x11;
"q\t\t=%X\n", q;

// compound ops and ++ wrap at the view width
q.u8[1] += 1;
q.u8[0]++;
"q\t\t=%X\n", q;

// signed views sign-extend, unsigned views zero-extend
U16 w = 0xABCD;
"w.u8[1]=%X w.i8[1]=%d\n", w.u8[1], w.i8[1];
w.u8[0] = 1;
"w\t=%X\n", w;

// works through pointers and on globals
I64 g = 0x1122334455;
I64 *p = &q;
p->u8[0] = 0x42;
"p->u8[0]=%X g.u8[4]=%X\n", q.u8[0], g.u8[4];

// a view without an index decays to a pointer at the base's address
U8 *b = q.u8;
"b[0]=%X\n", b[0];

// class members are integer lvalues too
class Pair { I64 a; I64 b; };
Pair pr;
pr.b = 0x556677;
pr.b.u8[1] = 0x99;
"pr.b\t\t=%X\n", pr.b;
