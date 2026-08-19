# lib/line

A minimal line editor for building REPLs, in the spirit of radare2's
`dietline`.  It layers on `lib/term`, so the same code runs on POSIX
terminals and Windows consoles; legacy Win32 consoles and non-interactive
input (pipes, files) degrade to cooked reads automatically.  `^C` cancels
the line, `^D` on an empty line ends input, and everything is UTF-8 —
cursor movement, deletion, and completion operate on runes, never bytes.

The core has no globals, no allocations, and no tunables: all state lives
in a `CLine` instance backed by caller storage, so one program can run any
number of independent line editors.  History is a pair of callbacks, so
entries can live anywhere; completion candidates are consumed as they are
offered and never stored.  `defaults.hc` provides ready-made storage and
an in-memory history for the common case.  Strings are handled as `CStrs`
byte slices from `lib/text/strs.hc` rather than NUL-terminated buffers.

## Core API (`line.hc`)

```holyc
#include "lib/line/line.hc"

Bool LineInit(CLine *line, U8 *buffer, I64 capacity,
              U8 *stash=NULL, I64 stash_capacity=0);
U8  *LineRead(CLine *line, U8 *prompt="> ");
                         // "" on ^C, NULL on end of input; the returned
                         // pointer is the buffer, valid until the next
                         // LineRead on the same instance
U0   LineFini();         // restore the terminal (shared by all instances)

U0   LineSetCompletion(CLine *line, callback, U8 *user=NULL);
U0   LineCompAdd(CLine *line, U8 *candidate);  // inside the callback
U0   LineCompFrom(CLine *line, I64 start);     // move the replaced region
U0   LineCompWord(CLine *line, CStrs *word);   // the word being completed
I64  LineCompArg(CLine *line);                 // which argument it is

U0   LineSetHistory(CLine *line, count_callback, get_callback, U8 *user=NULL);
```

The optional stash buffer preserves the fresh line while browsing history.

## Keys

* Move: arrows, Home/End, `^A` `^E` `^B` `^F`, Alt-b/Alt-f or
  Ctrl-arrows for words.
* Edit: Backspace, Delete, `^D`, `^K` (kill to end), `^U` (kill to
  start), `^W` (kill word), `^T` (transpose), `^L` (clear screen).
* History: Up/Down or `^P`/`^N`; `^R` starts a reverse incremental
  search — type to narrow, `^R` again for older matches, Esc/`^G`
  cancels, any other key edits the found line.
* Tab completes; `^C` cancels the line; `^D` on an empty line returns
  `NULL`.

Long lines scroll horizontally.  The prompt may contain UTF-8 and ANSI
color escapes; both are measured correctly.

## Completion

On Tab the callback receives the whole line as a `CStrs` slice plus the
byte cursor, and offers candidates with `LineCompAdd`.  The completed word
is any blank-delimited argument, not just the first one: `LineCompArg`
tells which argument the cursor is on (0 = the command itself) and
`LineCompWord` yields it, so command-specific syntaxes can complete each
position differently, readline/dietline style.  Candidates that do not
start with the word are ignored, so callbacks can blindly offer
everything:

```holyc
U0 Complete(CLine *line, CStrs *text, I64 cursor, U8 *user)
{
  if (!LineCompArg(line)) {
    LineCompAdd(line, "open");      // first word: commands
    LineCompAdd(line, "quit");
  } else if (StrsStartsWithS(text, "open "))
    LineCompAdd(line, "file.txt");  // arguments of open: files
}
LineSetCompletion(&line, &Complete);
```

A unique match is inserted (plus a trailing space), a common prefix is
extended, and multiple candidates are listed in columns.  Candidates are
only read during the `LineCompAdd` call, never stored — but the callback
may run twice per Tab (measure, then list), so it must offer the same
candidates both times.  `LineCompFrom(line, start)` moves the start of
the replaced region for non-blank syntaxes.

## History

The core only knows two callbacks — how many entries exist and how to
borrow one (index 0 is the oldest) — and implements Up/Down browsing and
`^R` on top, so a custom handler is two small functions:

```holyc
I64  MyCount(CLine *line, U8 *user);
Bool MyGet(CLine *line, I64 index, CStrs *entry, U8 *user);
LineSetHistory(&line, &MyCount, &MyGet, mystate);
```

## Defaults (`defaults.hc`)

`defaults.hc` picks good defaults so the common case needs no wiring: a
`CLineBuf` embeds a 4K line and stash, and a `CLineHistoryBuf` embeds a
32K pool for up to 256 entries that forgets the oldest when full.  The
pool stores entries back to back, each terminated by `\n`, so saving is a
single write and the file format is one entry per line.  `CLineHistory`
takes caller storage instead, for other sizes.

```holyc
#include "lib/line/defaults.hc"

CLineBuf line;
CLineHistoryBuf history;

U0 Main()
{
  U8 *text;

  LineBufInit(&line);
  LineHistoryBufInit(&history);
  LineHistoryAttach(&line, &history);
  LineHistoryLoad(&history, ".history");
  while (TRUE) {
    text = LineRead(&line, "\x1B[1;32m>\x1B[0m ");
    if (!text || !StrCmp(text, "exit"))
      break;
    LineHistoryAdd(&history, text);  // skips empties and repeats
    "%s\n", text;
  }
  LineHistorySave(&history, ".history");
  LineFini;
}
Main;
```

See `examples/line.hc` for the full demo with per-argument completion.
