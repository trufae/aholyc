// HolyC operator quirks: ` is power, comparisons chain, shifts bind tight.
"%d\n", ToI64(2`10);     // 1024 (` is power and always yields F64)

I64 age = 16;
if (13 <= age < 20)
  "Teen-ager\n";

I64 a = 5, b = 9;
if (1 < a < b < 100)
  "ordered\n";

// In HolyC, << and >> bind tighter than *
"%d\n", 2 * 3 << 1;      // 2 * (3<<1) = 12

F64 x = 2.0 ` 0.5;
"sqrt2 ~ %f\n", x;

// logical xor
"%d %d\n", 1 ^^ 0, 1 ^^ 1;
