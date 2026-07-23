// HolyC <-> C variadic FFI (wired in tests/run.sh with tests/varargs_ffi.c).
// A bodiless extern declared with ... imports a real C varargs function;
// HolyC-bodied variadics keep the TempleOS argc/argv convention.
extern I64 printf(U8 *fmt, ...);
extern I64 snprintf(U8 *buf, I64 n, U8 *fmt, ...);
extern I64 puts(U8 *s);
extern I64 CallHcSum();  // C helper calling back into HcSum below

// C -> HolyC: public variadics keep the implicit argc/argv pair, so the
// C side passes it explicitly: HcSum(3, (int64_t[]){10, 20, 12})
public I64 HcSum(...)
{
  I64 i, res = 0;
  for (i = 0; i < argc; i++)
    res += argv[i];
  return res;
}

// a HolyC variadic consuming F64 slots, handing them on to C printf
U0 Report(U8 *label, ...)
{
  I64 i;
  F64 sum = 0.0;
  for (i = 0; i < argc; i++)
    sum += argv[i](F64);
  printf("%s: %lld floats sum %.2f\n", label, argc, sum);
}

U8 buf[64];
snprintf(buf, 64, "pi=%.2f n=%lld s=%s", 3.14159, 42, "str");
puts(buf);
printf("int %lld str %s f64 %.1f %.1f %.1f\n", 7, "seven", 1.5, 2.5, 3.5);
Report("reals", 0.5, 1.25, 2.25);
"from C: HcSum=%d\n", CallHcSum;
