// Process argc/argv belong to the synthetic top-level entry.  Functions must
// receive them explicitly; resolving argc here would leak another function's
// parameter into this scope.
U0 MustForward()
{
  "%d\n", argc;
}

MustForward;
