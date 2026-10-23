#define HTK_NODESK
#include "../lib/htk/htk.hc"

extern U32 alarm(U32 seconds);
extern I64 lseek(I64 fd, I64 offset, I64 whence);
extern I32 mkstemp(U8 *path);
extern I32 unlink(U8 *path);
extern I32 getpid();

I64 failures;

U0 Check(Bool condition, U8 *name)
{
  if (!condition) {
    "FAIL %s\n", name;
    failures++;
  }
}

U0 Feed(CHtkTerm *t, U8 *text)
{
  I64 i;

  for (i = 0; text[i]; i++)
    HtkTermByte(t, text[i]);
}

U0 InitTerm(CHtkTerm *t, I64 cols=80, I64 rows=24)
{
  MemSet(t, 0, sizeof(CHtkTerm));
  t->fd = -1;
  t->fg = TERM_WHITE;
  t->bg = TERM_BLACK;
  HtkTermResize(t, cols, rows);
}

U0 TestPump()
{
  CHtkTerm t;
  U8 path[64] = "/tmp/aholyc-htk-pump-XXXXXX";
  U8 bytes[4096];
  I64 fd = mkstemp(path), i;

  Check(fd >= 0, "open pump fixture");
  if (fd < 0)
    return;
  unlink(path);
  MemSet(bytes, 'a', sizeof(bytes));
  for (i = 0; i < 32; i++)
    Check(write(fd, bytes, sizeof(bytes)) == sizeof(bytes), "write pump fixture");
  lseek(fd, 0, 0);
  InitTerm(&t);
  t.fd = fd;
  t.pid = getpid();  // no child to reap for this synthetic output stream
  Check(HtkTermPump(&t), "pump consumes pending output");
  i = lseek(fd, 0, 1);
  Check(i > 0 && i <= HTK_TERM_PUMP_BYTES && i < 32 * sizeof(bytes) && t.pending_output,
    "one pump yields with unread output remaining");
  Check(HtkTermPump(&t) && lseek(fd, 0, 1) == 32 * sizeof(bytes),
    "next pump resumes remaining output");
  Check(!HtkTermPump(&t) && !t.pending_output, "idle pump resumes ordinary polling");
  t.exited = TRUE;
  Check(!HtkTermPump(&t), "exited pump is idle");
  close(fd); Free(t.cells);
}

CHtkTerm term;
InitTerm(&term);
// A C0 byte in CSI used to recurse forever in the unchanged parser state.
// ESC can occur when an application abandons a partially written sequence.
alarm(5);
Feed(&term, "\x1B[31\r;1mX");
Check(term.state == 0 && term.cx == 1 && term.fg == TERM_RED &&
  term.attr == TERM_BOLD, "C0 executes without abandoning CSI");
Feed(&term, "\x1B[12;\x1B[2;3HY");
Check(term.state == 0 && term.cx == 3 && term.cy == 1 &&
  TermCellChar(term.cells[82]) == 'Y', "ESC restarts an incomplete CSI");
Feed(&term, "\x1B[12;\x18Z\x1B[12;\x1AQ");
Check(term.state == 0 && term.cx == 5 &&
  TermCellChar(term.cells[83]) == 'Z' && TermCellChar(term.cells[84]) == 'Q',
  "CAN and SUB cancel incomplete CSI");
Feed(&term, "\x1B[999999999999999999999999999999999999999999H");
Check(term.cx == 0 && term.cy == term.rows - 1, "oversized CSI parameters saturate");
TestPump;
alarm(0);
Free(term.cells);
"htk terminal: %d failures\n", failures;
Exit(failures != 0);
