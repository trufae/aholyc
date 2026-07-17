// Native exception state and handler stacks must be isolated per host thread.
extern U0 TlsBarrier();
extern I64 RunTlsThreads();

public I64 TlsCatch(I64 ch)
{
  I64 got = 0;
  try {
    TlsBarrier();
    throw(ch);
  } catch {
    TlsBarrier();
    got = Fs->except_ch;
    Fs->catch_except = TRUE;
  }
  return got;
}

"tls exceptions: %d\n", RunTlsThreads();
