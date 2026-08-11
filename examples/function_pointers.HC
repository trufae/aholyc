F64 Twice(F64 value)
{
  return value * 2.0;
}

I64 Inc(I64 value)
{
  return value + 1;
}

I64 Apply(I64 (*callback)(I64), I64 value)
{
  return callback(value);
}

I64 Sum(I64 first, ...)
{
  I64 i;
  I64 result = first;

  for (i = 0; i < argc; i++)
    result += argv[i];
  return result;
}

F64 (*twice)(F64 value) = &Twice;
I64 (*apply)(I64 (*callback)(I64 value), I64 value) = &Apply;
I64 (*sum)(I64 first, ...) = &Sum;

"%.1f\n", twice(3);
"%d\n", apply(&Inc, 41);
"%d\n", sum(1, 2, 3);
