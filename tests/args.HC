// AOT process arguments enter only the synthetic top-level function.  A
// program forwards them explicitly to whichever function it uses as Main.
I64 VarCount(...)
{
  return argc;
}

U0 Main(I64 ac, I64 *av)
{
  I64 i;

  "argc=%d\n", ac;
  for (i = 0; i < ac; i++)
    "arg%d=<%s> len=%d\n", i, av[i], StrLen(av[i]);
  "sentinel=%d\n", av[ac] == NULL;
  "varargc=%d\n", VarCount(11, 22, 33);
}

Main(argc, argv);
