#ifndef AHOLYC_LIB_LINE_HC
#define AHOLYC_LIB_LINE_HC

// Minimal line editor for building REPLs, in the spirit of radare2's
// dietline.  Input and raw mode come from lib/term, so the same code runs
// on POSIX terminals and Windows consoles; legacy Win32 consoles and
// non-interactive input degrade to cooked reads automatically.
//
// There are no globals, no allocations, and no tunables: all state lives
// in a CLine instance backed by caller storage, so one program can run
// any number of independent line editors.  lib/line/defaults.hc wires
// ready-made storage and an in-memory history for the common case.
//
//   Bool LineInit(CLine *line, U8 *buffer, I64 capacity,
//                 U8 *stash=NULL, I64 stash_capacity=0);
//   U8  *LineRead(CLine *line, U8 *prompt="> ");
//                          // "" on ^C, NULL on end of input; the returned
//                          // pointer is the line buffer, valid until the
//                          // next LineRead on the same instance
//   U0   LineFini();       // restore the terminal (shared by all instances)
//
// Editing: arrows, Home/End/Delete, ^A ^E ^B ^F ^D ^H ^K ^U ^W ^L ^T,
// Alt-b/Alt-f (or Ctrl-arrows) for words, ^P/^N and Up/Down for history,
// ^R for reverse incremental search, Tab for completion.  Text is UTF-8;
// the line scrolls horizontally when longer than the screen.  The stash
// buffer, when given, preserves the fresh line while browsing history.
//
// History is a pair of callbacks, so entries can live anywhere — in the
// default pool from defaults.hc, a database, or a radare2-style command
// log.  Index 0 is the oldest entry:
//
//   I64  LineHistCountCallback(CLine *line, U8 *user);
//   Bool LineHistGetCallback(CLine *line, I64 index, CStrs *entry, U8 *user);
//   U0   LineSetHistory(CLine *line, count_callback, get_callback, user=NULL);
//
// Completion: on Tab the callback is handed the whole line and the byte
// cursor, and offers candidates for the word being completed with
// LineCompAdd.  The word is any blank-delimited argument, not just the
// first one: LineCompArg tells which argument the cursor is on and
// LineCompWord yields it, so command-specific syntaxes can complete each
// position differently.  Candidates that do not start with the word are
// ignored, so callbacks can blindly offer everything; they are consumed
// during the LineCompAdd call and never stored, but the callback may run
// twice per Tab, so it must offer the same candidates both times:
//
//   U0 Complete(CLine *line, CStrs *text, I64 cursor, U8 *user)
//   {
//     if (!LineCompArg(line)) {
//       LineCompAdd(line, "open");     // first word: commands
//       LineCompAdd(line, "quit");
//     } else if (StrsStartsWithS(text, "open"))
//       LineCompAdd(line, "file.txt"); // arguments of open: files
//   }
//   LineSetCompletion(&line, &Complete);
//
// A unique match is inserted (plus a space), a common prefix is extended,
// and multiple candidates are listed.  LineCompFrom(line, start) moves the
// start of the replaced region for non-blank syntaxes.
//
// The prompt is borrowed for the duration of the call and may contain
// UTF-8 and ANSI color escapes; both are measured correctly.  LineRead
// owns the terminal while it runs: callbacks must not print.

#include "../term/term.hc"
#include "../text/strs.hc"

#define LINE_MORE   0
#define LINE_ACCEPT 1
#define LINE_END    2
#define LINE_CANCEL 3

class CLine;
U0 LineCompletionCallback(CLine *line, CStrs *text, I64 cursor, U8 *user);
I64 LineHistCountCallback(CLine *line, U8 *user);
Bool LineHistGetCallback(CLine *line, I64 index, CStrs *entry, U8 *user);

class CLine
{
  // The buffer holds bytes without a terminator (one is added when the
  // line is handed out); cursor is a byte offset on a rune boundary.
  U8 *buffer;
  I64 capacity;
  I64 length;
  I64 cursor;
  I64 scroll;         // first visible column
  U8 *prompt;         // borrowed while LineRead runs
  U8 *stash;          // optional: the fresh line, while browsing history
  I64 stash_capacity;
  I64 stash_length;
  Bool tty;           // TermInit succeeded: raw editing works

  LineCompletionCallback *comp_callback;
  U8 *comp_user;
  I64 comp_start;     // byte offset the completion replaces from
  I64 comp_count;     // matches seen this pass
  I64 comp_first;     // full byte length of the first match
  I64 comp_prefix;    // common prefix bytes (capped by comp_text)
  I64 comp_stored;    // bytes of the first match held in comp_text
  I64 comp_width;     // widest match, in columns
  I64 comp_columns;   // list layout; 0 during the measuring pass
  I64 comp_index;     // matches printed by the listing pass
  U8 comp_text[128];  // common prefix accumulator: a longer shared prefix
  // simply completes over two Tabs

  LineHistCountCallback *hist_count;
  LineHistGetCallback *hist_get;
  U8 *hist_user;
  I64 hist_index;     // == count while editing a fresh line

  U8 query[128];      // ^R pattern; longer searches are truncated
  I64 query_length;

  U8 out[256];        // staged terminal output, flushed when full
  I64 out_length;
};

// Overlap-safe forward copy, for deleting within the fixed buffers
// (MemCpy is libc memcpy, whose behavior on overlap is undefined).
U0 LineMoveBytes(U8 *dst, U8 *src, I64 count)
{
  I64 i;

  for (i = 0; i < count; i++)
    dst[i] = src[i];
}

U0 LineView(CLine *line, CStrs *view)
{
  StrsInitN(view, line->buffer, line->length);
}

public Bool LineInit(CLine *line, U8 *buffer, I64 capacity,
  U8 *stash=NULL, I64 stash_capacity=0)
{
  if (!line || !buffer || capacity < 2)
    return FALSE;
  MemSet(line, 0, sizeof(CLine));
  line->buffer = buffer;
  line->capacity = capacity;
  line->stash = stash;
  line->stash_capacity = stash_capacity;
  line->tty = TermInit(FALSE, FALSE);
  return TRUE;
}

public U0 LineFini()
{
  TermFini;
}

// --- rune and word navigation ------------------------------------------

I64 LinePrevPos(CLine *line, I64 pos)
{
  if (pos <= 0)
    return 0;
  pos--;
  while (pos > 0 && line->buffer[pos] & 0xC0 == 0x80)
    pos--;
  return pos;
}

I64 LineNextPos(CLine *line, I64 pos)
{
  if (pos >= line->length)
    return line->length;
  pos++;
  while (pos < line->length && line->buffer[pos] & 0xC0 == 0x80)
    pos++;
  return pos;
}

I64 LineWordLeft(CLine *line, I64 pos)
{
  while (pos > 0 && line->buffer[pos - 1] == ' ')
    pos--;
  while (pos > 0 && line->buffer[pos - 1] != ' ')
    pos--;
  return pos;
}

I64 LineWordRight(CLine *line, I64 pos)
{
  while (pos < line->length && line->buffer[pos] == ' ')
    pos++;
  while (pos < line->length && line->buffer[pos] != ' ')
    pos++;
  return pos;
}

// Display columns of a slice; ANSI color escapes count as zero width.
I64 LineWidth(CStrs *text)
{
  I64 at = 0;
  I64 length = StrsLen(text);
  I64 columns = 0;
  I64 rune, consumed;

  while (at < length) {
    if (text->a[at] == 0x1B) {
      at++;
      if (at < length && text->a[at] == '[') {
        at++;
        while (at < length && text->a[at] < 0x40)
          at++;
        if (at < length)
          at++;
      }
    } else {
      consumed = Utf8DecodeRune(text->a + at, length - at, &rune);
      if (!consumed)
        consumed = 1;
      at += consumed;
      columns++;
    }
  }
  return columns;
}

// --- staged output -------------------------------------------------------

U0 LineFlush(CLine *line)
{
  TermWrite(line->out, line->out_length);
  line->out_length = 0;
}

U0 LineOutN(CLine *line, U8 *bytes, I64 count)
{
  if (line->out_length + count > 256)
    LineFlush(line);
  if (count > 256) {  // never stage more than fits
    TermWrite(bytes, count);
    return;
  }
  MemCpy(line->out + line->out_length, bytes, count);
  line->out_length += count;
}

U0 LineOutS(CLine *line, U8 *text)
{
  LineOutN(line, text, StrLen(text));
}

U0 LineOutRune(CLine *line, I64 rune)
{
  U8 bytes[4];
  I64 count = Utf8EncodeRune(rune, bytes);

  if (!count) {
    bytes[0] = '?';
    count = 1;
  }
  LineOutN(line, bytes, count);
}

U0 LineBell()
{
  TermWrite("\x07", 1);
}

// --- editing primitives --------------------------------------------------

U0 LineInsert(CLine *line, U8 *bytes, I64 count)
{
  I64 i;

  if (count <= 0)
    return;
  if (line->length + count > line->capacity - 1) {
    LineBell;
    return;
  }
  for (i = line->length - 1; i >= line->cursor; i--)
    line->buffer[i + count] = line->buffer[i];
  MemCpy(line->buffer + line->cursor, bytes, count);
  line->cursor += count;
  line->length += count;
}

U0 LineDelete(CLine *line, I64 from, I64 to)
{
  if (from < 0)
    from = 0;
  if (to > line->length)
    to = line->length;
  if (from >= to)
    return;
  LineMoveBytes(line->buffer + from, line->buffer + to, line->length - to);
  line->length -= to - from;
  if (line->cursor > to)
    line->cursor -= to - from;
  else if (line->cursor > from)
    line->cursor = from;
}

U0 LineSet(CLine *line, CStrs *text)
{
  I64 length = StrsLen(text);

  if (length > line->capacity - 1) {
    length = line->capacity - 1;
    while (length > 0 && text->a[length] & 0xC0 == 0x80)
      length--;  // never cut a rune in half
  }
  if (length)
    MemCpy(line->buffer, text->a, length);
  line->length = length;
  line->cursor = length;
}

// --- rendering -------------------------------------------------------------

U0 LineRefresh(CLine *line)
{
  CStrs prompt, view;
  I64 width = TermWidth;
  I64 prompt_width, column, available, at, rune, consumed, index;
  U8 sequence[16];

  StrsInitS(&prompt, line->prompt);
  StrsInitN(&view, line->buffer, line->cursor);
  prompt_width = LineWidth(&prompt);
  column = LineWidth(&view);
  if (width < 1)
    width = 80;
  available = width - prompt_width - 1;
  if (available < 1)
    available = 1;
  if (column < line->scroll)
    line->scroll = column;
  if (column - line->scroll > available)
    line->scroll = column - available;
  LineOutN(line, "\r", 1);
  LineOutS(line, line->prompt);
  at = 0;
  index = 0;
  while (index < line->length) {
    consumed = Utf8DecodeRune(line->buffer + index, line->length - index,
      &rune);
    if (!consumed) {
      rune = RUNE_REPLACEMENT;
      consumed = 1;
    }
    index += consumed;
    if (at >= line->scroll && at - line->scroll <= available)
      LineOutRune(line, rune);
    at++;
  }
  LineOutS(line, "\x1B[K\r");
  if (prompt_width + column - line->scroll > 0) {
    StrPrint(sequence, "\x1B[%dC", prompt_width + column - line->scroll);
    LineOutS(line, sequence);
  }
  LineFlush(line);
}

// --- history -------------------------------------------------------------

// callbacks: count returns how many entries exist; get fills a borrowed
// slice for one of them, index 0 being the oldest.  Entries can live
// anywhere; defaults.hc has a ready-made pool implementation.
public U0 LineSetHistory(CLine *line, LineHistCountCallback *count,
  LineHistGetCallback *get, U8 *user=NULL)
{
  line->hist_count = count;
  line->hist_get = get;
  line->hist_user = user;
}

I64 LineHistCount(CLine *line)
{
  if (!line->hist_count || !line->hist_get)
    return 0;
  return line->hist_count(line, line->hist_user);
}

U0 LineHistBrowse(CLine *line, I64 direction)
{
  CStrs entry;
  I64 count = LineHistCount(line);

  if (direction < 0) {
    if (!line->hist_index) {
      LineBell;
      return;
    }
    if (line->hist_index > count)
      line->hist_index = count;
    if (line->hist_index == count && line->stash) {
      line->stash_length = line->length;
      if (line->stash_length > line->stash_capacity)
        line->stash_length = line->stash_capacity;
      MemCpy(line->stash, line->buffer, line->stash_length);
    }
    line->hist_index--;
    if (line->hist_get(line, line->hist_index, &entry, line->hist_user))
      LineSet(line, &entry);
    return;
  }
  if (line->hist_index >= count) {
    LineBell;
    return;
  }
  line->hist_index++;
  if (line->hist_index == count) {
    StrsInitN(&entry, line->stash, line->stash_length);
    LineSet(line, &entry);
  } else if (line->hist_get(line, line->hist_index, &entry,
      line->hist_user))
    LineSet(line, &entry);
}

// --- completion ------------------------------------------------------------

// callback: U0 (*)(CLine *line, CStrs *text, I64 cursor, U8 *user), ran on
// Tab; it offers candidates with LineCompAdd and may move the replaced
// region's start with LineCompFrom (default: the blank-delimited word at
// the cursor).  LineCompArg and LineCompWord identify which argument is
// being completed, for per-position syntaxes.
public U0 LineSetCompletion(CLine *line, LineCompletionCallback *callback,
  U8 *user=NULL)
{
  line->comp_callback = callback;
  line->comp_user = user;
}

public U0 LineCompFrom(CLine *line, I64 start)
{
  if (start >= 0 && start <= line->cursor)
    line->comp_start = start;
}

// The word being completed: buffer bytes from the replaced region's start
// to the cursor.
public U0 LineCompWord(CLine *line, CStrs *word)
{
  StrsInitN(word, line->buffer + line->comp_start,
    line->cursor - line->comp_start);
}

// Which blank-delimited argument the cursor is on: 0 for the command
// itself, 1 for its first argument, and so on.
public I64 LineCompArg(CLine *line)
{
  I64 i, arg = 0;
  Bool in_word = FALSE;

  for (i = 0; i < line->comp_start; i++) {
    if (line->buffer[i] == ' ')
      in_word = FALSE;
    else if (!in_word) {
      in_word = TRUE;
      arg++;
    }
  }
  return arg;
}

public U0 LineCompAdd(CLine *line, U8 *text)
{
  CStrs candidate, word;
  I64 length, item_width, i;

  if (!text)
    return;
  StrsInitS(&candidate, text);
  LineCompWord(line, &word);
  if (!StrsStartsWith(&candidate, &word))
    return;
  length = StrsLen(&candidate);
  if (!line->comp_columns) {  // measuring pass
    line->comp_count++;
    if (line->comp_count == 1) {
      line->comp_first = length;
      line->comp_stored = length;
      if (line->comp_stored > 128)
        line->comp_stored = 128;
      MemCpy(line->comp_text, text, line->comp_stored);
      line->comp_prefix = line->comp_stored;
    } else {
      i = 0;
      while (i < line->comp_prefix && i < length &&
        line->comp_text[i] == text[i])
        i++;
      line->comp_prefix = i;
    }
    item_width = LineWidth(&candidate);
    if (item_width > line->comp_width)
      line->comp_width = item_width;
    return;
  }
  // Listing pass: print in columns as the candidates stream by.
  LineOutN(line, candidate.a, StrsLen(&candidate));
  line->comp_index++;
  if (line->comp_index % line->comp_columns)
    for (item_width = LineWidth(&candidate);
    item_width < line->comp_width + 2; item_width++)
    LineOutN(line, " ", 1);
  else
    LineOutS(line, "\r\n");
}

U0 LineComplete(CLine *line)
{
  CStrs view;
  I64 word, width;

  if (!line->comp_callback)
    return;
  line->comp_start = LineWordLeft(line, line->cursor);
  while (line->comp_start < line->cursor &&
    line->buffer[line->comp_start] == ' ')
    line->comp_start++;
  line->comp_count = 0;
  line->comp_prefix = 0;
  line->comp_stored = 0;
  line->comp_first = 0;
  line->comp_width = 0;
  line->comp_columns = 0;
  LineView(line, &view);
  line->comp_callback(line, &view, line->cursor, line->comp_user);
  if (!line->comp_count) {
    LineBell;
    return;
  }
  while (line->comp_prefix > 0 && line->comp_prefix < line->comp_stored &&
    line->comp_text[line->comp_prefix] & 0xC0 == 0x80)
    line->comp_prefix--;  // never cut a rune in half
  word = line->cursor - line->comp_start;
  if (line->comp_prefix > word) {
    LineInsert(line, line->comp_text + word, line->comp_prefix - word);
    if (line->comp_count == 1 && line->comp_prefix == line->comp_first)
      LineInsert(line, " ", 1);
    return;
  }
  if (line->comp_count == 1) {  // already fully typed
    LineInsert(line, " ", 1);
    return;
  }
  // Several candidates share only the current word: list them in columns
  // by running the callback a second time.
  width = TermWidth;
  if (width < 1)
    width = 80;
  line->comp_columns = width / (line->comp_width + 2);
  if (line->comp_columns < 1)
    line->comp_columns = 1;
  line->comp_index = 0;
  LineOutS(line, "\r\n");
  line->comp_callback(line, &view, line->cursor, line->comp_user);
  if (line->comp_index % line->comp_columns)
    LineOutS(line, "\r\n");
  LineFlush(line);
}

// --- key handling ------------------------------------------------------------

I64 LineSearch(CLine *line);

I64 LineKey(CLine *line, CTermEvent *event)
{
  I64 key = event->key;
  I64 mods = event->mods;
  U8 bytes[4];
  I64 count, swap;

  if (mods & TERM_MOD_CTRL) {
    switch (key) {
      case 'a':
        line->cursor = 0;
        break;
      case 'e':
        line->cursor = line->length;
        break;
      case 'b':
        line->cursor = LinePrevPos(line, line->cursor);
        break;
      case 'f':
        line->cursor = LineNextPos(line, line->cursor);
        break;
      case 'd':
        if (!line->length)
          return LINE_END;
        LineDelete(line, line->cursor, LineNextPos(line, line->cursor));
        break;
      case 'h':
        LineDelete(line, LinePrevPos(line, line->cursor), line->cursor);
        break;
      case 'k':
        LineDelete(line, line->cursor, line->length);
        break;
      case 'u':
        LineDelete(line, 0, line->cursor);
        break;
      case 'w':
        LineDelete(line, LineWordLeft(line, line->cursor), line->cursor);
        break;
      case 't':  // transpose the runes around the cursor
        if (line->cursor > 0 && line->length > 1) {
          if (line->cursor < line->length)
            line->cursor = LineNextPos(line, line->cursor);
          swap = LinePrevPos(line, line->cursor);
          count = line->cursor - swap;
          MemCpy(bytes, line->buffer + swap, count);
          LineDelete(line, swap, line->cursor);
          line->cursor = LinePrevPos(line, line->cursor);
          LineInsert(line, bytes, count);
          line->cursor = LineNextPos(line, line->cursor);
        }
        break;
      case 'l':
        TermWrite("\x1B[2J\x1B[H", 7);
        break;
      case 'p':
        LineHistBrowse(line, -1);
        break;
      case 'n':
        LineHistBrowse(line, 1);
        break;
      case 'r':
        return LineSearch(line);
      case TERM_KEY_LEFT:
        line->cursor = LineWordLeft(line, line->cursor);
        break;
      case TERM_KEY_RIGHT:
        line->cursor = LineWordRight(line, line->cursor);
        break;
    }
    return LINE_MORE;
  }
  if (mods & TERM_MOD_ALT) {
    if (key == 'b')
      line->cursor = LineWordLeft(line, line->cursor);
    else if (key == 'f')
      line->cursor = LineWordRight(line, line->cursor);
    else if (key == TERM_KEY_BACKSPACE)
      LineDelete(line, LineWordLeft(line, line->cursor), line->cursor);
    return LINE_MORE;
  }
  switch (key) {
    case TERM_KEY_ENTER:
      return LINE_ACCEPT;
    case TERM_KEY_BACKSPACE:
      LineDelete(line, LinePrevPos(line, line->cursor), line->cursor);
      break;
    case TERM_KEY_DELETE:
      LineDelete(line, line->cursor, LineNextPos(line, line->cursor));
      break;
    case TERM_KEY_TAB:
      LineComplete(line);
      break;
    case TERM_KEY_LEFT:
      line->cursor = LinePrevPos(line, line->cursor);
      break;
    case TERM_KEY_RIGHT:
      line->cursor = LineNextPos(line, line->cursor);
      break;
    case TERM_KEY_HOME:
      line->cursor = 0;
      break;
    case TERM_KEY_END:
      line->cursor = line->length;
      break;
    case TERM_KEY_UP:
      LineHistBrowse(line, -1);
      break;
    case TERM_KEY_DOWN:
      LineHistBrowse(line, 1);
      break;
    case TERM_KEY_ESCAPE:
      break;
    default:
      if (key >= ' ' && key <= RUNE_MAX) {
        count = Utf8EncodeRune(key, bytes);
        if (count)
          LineInsert(line, bytes, count);
      }
  }
  return LINE_MORE;
}

// --- reverse incremental search (^R) -------------------------------------

U0 LineSearchRefresh(CLine *line)
{
  LineOutS(line, "\r(reverse-i-search)`");
  LineOutN(line, line->query, line->query_length);
  LineOutS(line, "': ");
  LineOutN(line, line->buffer, line->length);
  LineOutS(line, "\x1B[K");
  LineFlush(line);
}

// Newest history entry containing the query, at or before from.
U0 LineSearchSeek(CLine *line, I64 *match, I64 from)
{
  CStrs query, entry;
  I64 i, count = LineHistCount(line);

  StrsInitN(&query, line->query, line->query_length);
  if (StrsEmpty(&query))
    return;
  if (from >= count)
    from = count - 1;
  for (i = from; i >= 0; i--) {
    if (line->hist_get(line, i, &entry, line->hist_user) &&
      StrsFind(&entry, &query)) {
        *match = i;
        LineSet(line, &entry);
        return;
      }
  }
  LineBell;
}

I64 LineSearch(CLine *line)
{
  CTermEvent event;
  I64 match = -1;
  I64 count, action;
  U8 bytes[4];

  line->query_length = 0;
  LineSearchRefresh(line);
  while (TRUE) {
    if (!TermPollEvent(&event)) {
      if (TermInterrupted)
        return LINE_CANCEL;
    } else if (event.type != TERM_EVENT_KEY) {
      LineSearchRefresh(line);
    } else if (event.mods & TERM_MOD_CTRL && event.key == 'r') {
      LineSearchSeek(line, &match, match - 1);
      LineSearchRefresh(line);
    } else if (event.key == TERM_KEY_BACKSPACE) {
      while (line->query_length > 0) {
        line->query_length--;
        if (line->query[line->query_length] & 0xC0 != 0x80)
          break;
      }
      LineSearchSeek(line, &match, LineHistCount(line) - 1);
      LineSearchRefresh(line);
    } else if (event.key == TERM_KEY_ESCAPE ||
      event.mods & TERM_MOD_CTRL && event.key == 'g') {
        return LINE_MORE;
      } else if (!event.mods && event.key >= ' ' && event.key <= RUNE_MAX) {
        count = Utf8EncodeRune(event.key, bytes);
        if (line->query_length + count <= 128) {
          MemCpy(line->query + line->query_length, bytes, count);
          line->query_length += count;
        }
        LineSearchSeek(line, &match, LineHistCount(line) - 1);
        LineSearchRefresh(line);
      } else {
        // Any other key leaves search mode and acts on the found line.
        action = LineKey(line, &event);
        LineRefresh(line);
        return action;
      }
  }
  return LINE_MORE;
}

// --- top level --------------------------------------------------------------

// Cooked fallback: no tty, or a legacy Win32 console that edits by itself.
U8 *LineReadCooked(CLine *line, U8 *prompt)
{
  I64 byte;

  line->length = 0;
  line->cursor = 0;
  if (line->tty) {
    TermWrite(prompt, StrLen(prompt));
    if (TermLegacy) {
      line->length = TermReadLine(line->buffer, line->capacity);
      if (line->length < 0) {
        line->length = 0;
        return NULL;
      }
      return line->buffer;
    }
  }
  while (TRUE) {
    byte = TermReadByte;
    if (byte < 0) {
      if (!line->length)
        return NULL;
      break;
    }
    if (byte == '\n')
      break;
    if (byte != '\r' && line->length < line->capacity - 1)
      line->buffer[line->length++] = byte;
  }
  line->cursor = line->length;
  line->buffer[line->length] = 0;
  return line->buffer;
}

public U8 *LineRead(CLine *line, U8 *prompt="> ")
{
  CTermEvent event;
  I64 action;

  if (!line || !line->buffer)
    return NULL;
  line->prompt = prompt;
  if (!line->tty || TermLegacy)
    return LineReadCooked(line, prompt);
  line->length = 0;
  line->cursor = 0;
  line->scroll = 0;
  line->stash_length = 0;
  line->hist_index = LineHistCount(line);
  TermInterrupted;  // start with a clean flag
  TermRaw(TRUE);
  LineRefresh(line);
  action = LINE_MORE;
  while (action == LINE_MORE) {
    if (!TermPollEvent(&event)) {
      if (TermInterrupted)
        action = LINE_CANCEL;
    } else if (event.type != TERM_EVENT_KEY) {
      LineRefresh(line);
    } else {
      action = LineKey(line, &event);
      if (action == LINE_MORE)
        LineRefresh(line);
    }
  }
  TermRaw(FALSE);
  if (action == LINE_CANCEL) {
    line->length = 0;
    line->cursor = 0;
    TermWrite("^C\r\n", 4);
  } else {
    TermWrite("\r\n", 2);
  }
  if (action == LINE_END)
    return NULL;
  line->buffer[line->length] = 0;
  return line->buffer;
}

#endif
