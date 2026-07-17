// Recursion and F64 math.
I64 Fib(I64 n)
{
  if (n < 2)
    return n;
  return Fib(n - 1) + Fib(n - 2);
}

I64 i;
for (i = 0; i < 10; i++)
  "%d ", Fib(i);
"\n";

F64 golden = (1.0 + Sqrt(5.0)) / 2.0;
"golden ratio ~ %f\n", golden;
