// Variadic functions get implicit argc/argv, like 'this' in C++.
I64 AddNums(...)
{
  I64 i, res = 0;
  for (i = 0; i < argc; i++)
    res += argv[i];
  return res;
}

"%d\n", AddNums(1, 2, 3);
"%d\n", AddNums(10, 20, 30, 40);
"%d\n", AddNums();
