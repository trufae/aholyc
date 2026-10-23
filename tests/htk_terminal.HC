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

U0 TestBatch()
{
  CHtkTerm a, b;
  U8 *text = "plain text\x1B[31;1mred\x1B[0m é😀\r\n"
    "\x1B[2;3Hxy\x1B[2@Z\x1B[P\x1B[2;4r\x1B[4;1H\n"
    "\x1B[2T\x1B[3S\x1B[2J\x1B]0;title\x07more\x1B[?25l";
  U8 bytes[257];
  U64 random = 17;
  I64 i, j, n, length = StrLen(text);

  InitTerm(&a, 11, 4); InitTerm(&b, 11, 4);
  for (i = 0; i < length; i++) {
    HtkTermByte(&a, text[i]);
    HtkTermFeed(&b, text + i, 1);  // split every escape and UTF-8 boundary
  }
  Check(!MemCmp(a.cells, b.cells, 44 * sizeof(U64)) &&
    a.cx == b.cx && a.cy == b.cy && a.state == b.state,
    "fragmented batches preserve parser state");
  for (i = 0; i < length; i++)
    HtkTermByte(&a, text[i]);
  HtkTermFeed(&b, text, length);
  Check(!MemCmp(a.cells, b.cells, 44 * sizeof(U64)) &&
    a.cx == b.cx && a.cy == b.cy && a.state == b.state,
    "contiguous batches preserve wrapping, scrolling and pen changes");
  for (i = 0; i < 2000; i++) {
    n = i % sizeof(bytes) + 1;
    for (j = 0; j < n; j++) {
      random = random * 6364136223846793005 + 1;
      bytes[j] = random >> 32;
      HtkTermByte(&a, bytes[j]);
    }
    HtkTermFeed(&b, bytes, n);
    if (MemCmp(a.cells, b.cells, 44 * sizeof(U64)) ||
      a.cx != b.cx || a.cy != b.cy || a.fg != b.fg || a.bg != b.bg ||
      a.attr != b.attr || a.state != b.state || a.utf8_len != b.utf8_len ||
      a.top != b.top || a.bottom != b.bottom) {
        Check(FALSE, "batch parser matches byte parser for mixed output");
        break;
      }
  }
  Free(a.cells); Free(b.cells);
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

// Compare the optimized draw with the original per-cell drawing contract.
U0 ReferenceDraw(HtkCtl *c)
{
  CHtkTerm *t = HtkTermOf(c);
  I64 x, y, fg, bg, attr;
  U64 cell;

  for (y = 0; y < t->rows; y++)
    for (x = 0; x < t->cols; x++) {
      cell = t->cells[y * t->cols + x];
      fg = TermCellFg(cell); bg = TermCellBg(cell); attr = TermCellAttr(cell);
      if (attr & TERM_REVERSE) { fg = TermCellBg(cell); bg = TermCellFg(cell); }
      HtkChr(c->x + x, c->y + y, TermCellChar(cell), fg, bg, attr & ~TERM_REVERSE);
    }
}

U0 DrawBackground()
{
  TermClear;
  TermCell(2, 2, 0x754C);  // continuation under the terminal's first cell
  TermCell(6, 3, 0x754C);  // wide glyphs must be cleaned up on overwrite
}

U0 TestDraw()
{
  CHtkTerm t;
  HtkCtl *c = HtkNew(HTK_TERM);
  U64 *expected = MAlloc(term_width * term_height * sizeof(U64));
  I64 i, variant;

  InitTerm(&t, 12, 4);
  c->data = &t; c->w = 12; c->h = 4;
  for (i = 0; i < 48; i++)
    t.cells[i] = 'A' + i % 26 | (TERM_BOLD << 21) |
      (TERM_RED << 28) | (TERM_BLUE << 46);
  t.cells[15] = 0x754C | (TERM_WHITE << 28);
  t.cells[25] |= TERM_REVERSE << 21;
  t.cells[26] = 0xE9 | (TERM_WHITE << 28);
  for (variant = 0; variant < 8; variant++) {
    c->x = 3; c->y = 2;
    if (variant & 1) { c->x = -4; c->y = -1; }
    htk_theme.ascii = (variant & 2) != 0;
    htk_paint_dim = (variant & 4) != 0;
    HtkClipAll; HtkClipSet(1, 1, term_width - 2, term_height - 2);
    DrawBackground; ReferenceDraw(c);
    MemCpy(expected, term_back, term_width * term_height * sizeof(U64));
    DrawBackground; HtkTermDraw(c);
    Check(!MemCmp(expected, term_back, term_width * term_height * sizeof(U64)),
      "packed draw preserves clipping, Unicode, reverse, serial and dim colors");
  }
  htk_paint_dim = FALSE; HtkThemeDefault; HtkClipAll;
  Free(expected); Free(t.cells); HtkDestroy(c);
}

U0 TestRefresh()
{
  CHtkTerm t;
  HtkCtl *w = HtkWindowNew("Terminal", 24, 8);
  HtkCtl *c = HtkNew(HTK_TERM), *other;
  HtkNotice *notice;

  InitTerm(&t);
  c->data = &t; c->focusable = TRUE; c->expand = TRUE;
  HtkAdd(w, c); HtkWindowLayout(w); HtkSetFocus(c);
  Check(HtkTermCanRefresh(c), "unobscured top terminal can refresh directly");
  Feed(&t, "\x1B[Htest"); t.repaint = TRUE;
  TermCell(0, 0, 'Z');
  HtkTermRefresh;
  Check(!t.repaint && TermCellChar(TermPeek(c->x, c->y)) == 't' &&
    TermCellChar(TermPeek(0, 0)) == 'Z', "refresh changes only terminal contents");
  notice = HtkNotify("Overlay");
  Check(!HtkTermCanRefresh(c), "notifications require full composition");
  HtkNoticeClose(notice);
  HtkWindowMenuOpen(w, w->x, w->y);
  Check(!HtkTermCanRefresh(c), "menus require full composition");
  HtkPopupClose;
  HtkWindowMoveBegin(w, 0, 0);
  Check(!HtkTermCanRefresh(c), "window move prompt requires full composition");
  HtkWindowMoveEnd;
  other = HtkWindowNew("Above", 20, 6);
  Check(!HtkTermCanRefresh(c), "background terminals require full composition");
  HtkWindowClose(other); HtkDestroy(other);
  c->data = NULL; Free(t.cells);
  HtkWindowClose(w); HtkDestroy(w);
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
TestBatch;
TestPump;
term_width = 32; term_height = 12;
TermBuffersAlloc; HtkThemeDefault;
TestDraw;
TestRefresh;
Free(term_back); Free(term_front);
alarm(0);
Free(term.cells);
"htk terminal: %d failures\n", failures;
Exit(failures != 0);
