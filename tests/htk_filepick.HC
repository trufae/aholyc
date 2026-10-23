#define HTK_NODESK
#include "../lib/htk/filepick.hc"
#include "../lib/io/file.hc"

extern I64 pipe(I32 *fds);
extern I64 dup(I64 fd);
extern U8 *mkdtemp(U8 *path);
extern I32 unlink(U8 *path);
extern I32 rmdir(U8 *path);
extern U32 alarm(U32 seconds);

I32 input[2];
I64 failures, frames;
I64 expected_top;
HtkCtl *expected_selection;
U8 *expected_entry;
U8 directory[64] = "/tmp/aholyc-filepick-XXXXXX";

U0 ObserveTree(HtkCtl *c)
{
  I64 step = 1, span = MaxI64(0, HtkTreeCount(c) - c->h);
  U8 *report;
  CHtkFilePick *pick = c->user;

  HtkTreeDraw(c);
  if (c->top != expected_top || c->link != expected_selection ||
    StrCmp(pick->entry->text, expected_entry))
    failures++;
  I64 thumb = MaxI64(1, c->h * c->h / HtkTreeCount(c));
  I64 at = c->top * (c->h - thumb) / MaxI64(1, span);
  if (!c->scrollbar || TermCellChar(TermPeek(c->x + c->w - 1, c->y + at)) != HTK_R_BLOCK)
    failures++;
  frames++;
  if (frames == 141) {
    expected_selection = c->kids;
    Free(expected_entry);
    expected_entry = MStrPrint("%s/%s", directory, expected_selection->text);
    report = MStrPrint("\x1B[<0;%d;%dM", c->x + 3, c->y + 1);
    write(input[1], report, StrLen(report)); Free(report);
    return;
  }
  if (frames >= 150) {
    write(input[1], "\x1B", 1);
    return;
  }
  if (frames > 70 && frames <= 140 || frames == 3 || frames > 141 && frames % 2) step = -1;
  expected_top = MaxI64(0, MinI64(span, expected_top + step));
  report = MStrPrint("\x1B[<%d;%d;%dM", 65 - (step < 0), c->x + 3, c->y + 2);
  write(input[1], report, StrLen(report));
  Free(report);
}

I64 i, saved_input = dup(0)(I32), saved_output = dup(1)(I32);
I64 quiet = open("/dev/null", 1, 0)(I32);
U8 *path, *result;

if (!mkdtemp(directory) || pipe(input)(I32) || quiet < 0 || saved_input < 0 || saved_output < 0)
  Exit(1);
for (i = 0; i < 60; i++) {
  path = MStrPrint("%s/item-%02d", directory, i);
  if (!FileWrite(path, "fixture\n")) Exit(1);
  Free(path);
}
dup2(input[0], 0); close(input[0]);
dup2(quiet, 1); close(quiet);
term_width = 100; term_height = 40;
TermBuffersAlloc; HtkThemeDefault;
term_out_capacity = 4096; term_out = MAlloc(term_out_capacity);
term_started = TRUE;
HtkOpsInit;
htk_ops_ready = TRUE;
htk_draw[HTK_TREE] = &ObserveTree;
expected_entry = StrNew(directory);
HtkCtl *owner = HtkWindowNew("Owner", 40, 10);
alarm(5);
result = HtkFilePickFor(owner, directory);
alarm(0);
HtkWindowClose(owner); HtkDestroy(owner);
term_started = FALSE;
dup2(saved_input, 0); close(saved_input); close(input[1]);
dup2(saved_output, 1); close(saved_output);
if (result || frames != 150 || expected_top) failures++;
Free(result); Free(expected_entry); Free(term_back); Free(term_front); Free(term_out);
for (i = 0; i < 60; i++) {
  path = MStrPrint("%s/item-%02d", directory, i);
  unlink(path); Free(path);
}
rmdir(directory);
"htk file picker: %d failures, %d frames\n", failures, frames;
Exit(failures != 0);
