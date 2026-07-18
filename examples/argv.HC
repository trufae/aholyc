// Build and run with, for example:
//   aholyc run examples/argv.HC alpha "two words" -x
//
// argc/argv belong to global startup code.  Forward the pair explicitly to
// whichever function the program uses as its entry point.
U0 Main(I64 argc, I64 *argv)
{
  I64 i;

  for (i = 0; i < argc; i++)
    "argv[%d] = \"%s\"\n", i, argv[i];
}

Main(argc, argv);
