U0 Quiet(I64 n)
{
  if (n)
    Quiet(n - 1);
}

U0 Risky(I64 ch)
{
  throw(ch);
}

U0 CallsRisky(I64 ch)
{
  Risky(ch);
}

U0 SelfRisky(I64 n)
{
  if (n)
    SelfRisky(n - 1);
  else
    throw('Self');
}

U0 QuietA(I64 n);
U0 QuietB(I64 n)
{
  if (n)
    QuietA(n - 1);
}
U0 QuietA(I64 n)
{
  if (n)
    QuietB(n - 1);
}

U0 MutualRiskyA(I64 n);
U0 MutualRiskyB(I64 n)
{
  if (n)
    MutualRiskyA(n - 1);
  else
    throw('Mut');
}
U0 MutualRiskyA(I64 n)
{
  MutualRiskyB(n);
}

// No throwing path: the catch and its handler are omitted.
try {
  Quiet(2);
  QuietA(3);
  "quiet\n";
} catch {
  "unreachable\n";
  Fs->catch_except = TRUE;
}

// A direct throw in this function needs only a branch.
try {
  throw('Loc');
} catch {
  "local %c\n", Fs->except_ch;
  Fs->catch_except = TRUE;
}

// An exception crossing Risky's call frame keeps the dynamic handler.
try {
  Risky('Call');
} catch {
  "call %c\n", Fs->except_ch;
  Fs->catch_except = TRUE;
}

// Throwing effects propagate through ordinary callers and recursive cycles.
try {
  CallsRisky('Wrap');
} catch {
  "wrapper %c\n", Fs->except_ch;
  Fs->catch_except = TRUE;
}
try {
  SelfRisky(2);
} catch {
  "self %c\n", Fs->except_ch;
  Fs->catch_except = TRUE;
}
try {
  MutualRiskyA(2);
} catch {
  "mutual %c\n", Fs->except_ch;
  Fs->catch_except = TRUE;
}

// The inner handler is dynamic, but its unconsumed rethrow can branch to the
// lexical outer handler in this function.
try {
  try {
    Risky('Nest');
  } catch {
    "inner %c\n", Fs->except_ch;
  }
} catch {
  "outer %c\n", Fs->except_ch;
  Fs->catch_except = TRUE;
}

// Force a dynamic outer handler. The local inner catch must rethrow through
// that handler rather than skipping it for another lexical label.
try {
  if (0)
    Risky('Nope');
  try {
    throw('Mix');
  } catch {
    "mixed inner %c\n", Fs->except_ch;
  }
} catch {
  "mixed outer %c\n", Fs->except_ch;
  Fs->catch_except = TRUE;
}
