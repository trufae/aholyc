// try/catch/throw. throw() takes up to 8 chars packed in an I64.
// A catch block must consume the exception (PutExcept or
// Fs->catch_except=TRUE) or the search continues to the outer handler.
U0 Risky(I64 n)
{
  if (n > 3)
    throw('2BIG');
  "ok %d\n", n;
}

try {
  Risky(1);
  Risky(5);
  "never reached\n";
} catch {
  "caught: %c\n", Fs->except_ch;
  Fs->catch_except = TRUE;
}

// nested: inner catch declines, outer handles
try {
  try {
    throw('Deep');
  } catch {
    "inner saw %c\n", Fs->except_ch;
    // not consuming: propagate up
  }
} catch {
  "outer got %c\n", Fs->except_ch;
  Fs->catch_except = TRUE;
}
"done\n";
