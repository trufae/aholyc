// Variadic functions get implicit argc/argv, like 'this' in C++.
// TempleOS model: there is no va_list; argc counts only the extras and
// each extra occupies one full I64 slot of the argv array.
I64 AddNums(...)
{
  I64 i, res = 0;
  for (i = 0; i < argc; i++)
    res += argv[i];
  return res;
}

// F64 extras are bit-copied into their I64 slot; the postfix cast
// reinterprets the slot (ToF64/ToI64 convert the value instead).
F64 AddReals(...)
{
  I64 i;
  F64 res = 0.0;
  for (i = 0; i < argc; i++)
    res += argv[i](F64);
  return res;
}

// Forwarding without va_list: pass argc/argv as plain arguments to a
// join-style helper, the way Print hands off to StrPrintJoin.
I64 SumJoin(I64 base, I64 cnt, I64 *vec)
{
  I64 i;
  for (i = 0; i < cnt; i++)
    base += vec[i];
  return base;
}

// Fixed params come before the ...; only the extras land in argv.
I64 SumFrom(I64 base, ...)
{
  return SumJoin(base, argc, argv);
}

// Default args fill omitted fixed slots; extras still go to argv.
I64 Scale(I64 k=2, ...)
{
  return k * SumJoin(0, argc, argv);
}

"%d\n", AddNums(1, 2, 3);
"%d\n", AddNums(10, 20, 30, 40);
"%d\n", AddNums();
"%f\n", AddReals(1.5, 2.25);
"%d\n", SumFrom(100, 1, 2, 3);
"%d\n", Scale(3, 10, 1);
"%d\n", Scale(, 10, 1);
