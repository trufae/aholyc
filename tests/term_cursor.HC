#include "../lib/term/term.hc"
#include "../lib/text/strbuf.hc"

extern I32 pipe(I32 *fds);
extern I32 dup(I32 fd);
extern I32 dup2(I32 from, I32 to);
extern I32 close(I32 fd);

I64 failures;

U0 Check(Bool ok, U8 *name)
{
  if (!ok) { "FAIL cursor: %s\n", name; failures++; }
}

// Capture real POSIX backend writes; no terminal or escape-code stub.
U8 *Capture(Bool fini=FALSE)
{
  I32 descriptors[2], saved = dup(1);
  I64 size;
  U8 bytes[256];
  CStrBuf output;

  if (saved < 0 || pipe(descriptors) || dup2(descriptors[1], 1) < 0) Exit(1);
  if (fini) TermFini;
  else TermCommit;
  dup2(saved, 1); close(saved); close(descriptors[1]);
  StrBufInit(&output);
  while ((size = read(descriptors[0], bytes, sizeof(bytes))) > 0) StrBufPutN(&output, bytes, size);
  close(descriptors[0]); return StrBufTake(&output);
}

// Headless setup, matching TermInit's buffer ownership without requiring a tty.
term_width = 2; term_height = 1;
TermBuffersAlloc;
term_out_capacity = 4096; term_out = MAlloc(term_out_capacity);
term_posix_old_int = signal(TERM_SIGINT, &TermPosixInterrupt);
term_posix_old_winch = signal(TERM_SIGWINCH, &TermPosixResize);
term_started = TRUE;
TermShowCursor;
TermSetCursorShape(TERM_CURSOR_BLOCK);
U8 *output = Capture;
Check(MemMem(output, StrLen(output), "\x1B[2 q", 5), "block cursor output"); Free(output);
output = Capture;
Check(!*output, "unchanged commit emits nothing"); Free(output);
TermSetCursorShape(TERM_CURSOR_BAR);
output = Capture;
Check(MemMem(output, StrLen(output), "\x1B[6 q", 5) && term_committed_shape == TERM_CURSOR_BAR,
  "shape-only change commits without text or movement"); Free(output);
TermShowCursor(FALSE); output = Capture; Free(output);
TermSetCursorShape(TERM_CURSOR_BLOCK); output = Capture;
Check(MemMem(output, StrLen(output), "\x1B[2 q", 5) && !MemMem(output, StrLen(output), "\x1B[?25h", 6),
  "hidden cursor changes shape without becoming visible"); Free(output);
TermShowCursor; output = Capture;
Check(MemMem(output, StrLen(output), "\x1B[?25h", 6) && !MemMem(output, StrLen(output), "\x1B[2 q", 5),
  "showing cursor retains shape without resending it"); Free(output);
TermSetCursorShape(99); output = Capture;
Check(!*output && term_cursor_shape == TERM_CURSOR_BLOCK, "invalid shape leaves cursor unchanged"); Free(output);
TermSetCursorShape; output = Capture;
Check(MemMem(output, StrLen(output), "\x1B[0 q", 5), "explicit default resets cursor style"); Free(output);
TermSetCursorShape(TERM_CURSOR_BAR); output = Capture; Free(output);
output = Capture(TRUE);
Check(MemMem(output, StrLen(output), "\x1B[0 q", 5) && !term_started,
  "shutdown resets cursor style and releases terminal"); Free(output);
"term cursor: %d failures\n", failures;
Exit(failures != 0);
