// Default args don't have to be trailing, and holes pick the default.
U0 Test(I64 i=4, I64 j, I64 k=5)
{
  "%X %X %X\n", i, j, k;
}

Test(,3);      // i=4 (default), j=3, k=5 (default)
Test(1,2,3);
Test(,7,);     // trailing hole also defaults

// Functions with no needed args can be called without parentheses.
U0 Hi()
{
  "hi\n";
}
Hi;
Hi();
