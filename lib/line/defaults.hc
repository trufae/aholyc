#ifndef AHOLYC_LIB_LINE_DEFAULTS_HC
#define AHOLYC_LIB_LINE_DEFAULTS_HC

// Ready-made storage and history for lib/line, so the common case needs no
// wiring.  The core in line.hc is storage- and policy-free; this file picks
// good defaults: a 4K line with a stash for history browsing, and a 32K
// in-memory history of up to 256 entries that forgets the oldest when full.
// Programs with other needs (bigger lines, histories in a database, ...)
// can size CLine themselves or implement the two history callbacks instead.
//
//   CLineBuf line;               // a CLine with built-in buffers
//   CLineHistory history;        //   entries in caller storage
//   CLineHistoryBuf history;     //   entries in built-in storage
//
//   Bool LineBufInit(CLineBuf *line);
//   U0   LineHistoryInit(CLineHistory *history, U8 *pool, I64 capacity,
//                        CStrs *entries, I64 max);
//   U0   LineHistoryBufInit(CLineHistoryBuf *history);
//   U0   LineHistoryAttach(CLine *line, CLineHistory *history);
//   U0   LineHistoryAdd(CLineHistory *history, U8 *text);
//   Bool LineHistoryLoad(CLineHistory *history, U8 *path);
//   Bool LineHistorySave(CLineHistory *history, U8 *path);

#include "line.hc"
#include "../io/file.hc"

class CLineBuf : CLine
{
  U8 buffer_data[4096];
  U8 stash_data[4096];
};

public Bool LineBufInit(CLineBuf *line)
{
  return LineInit(line, line->buffer_data, 4096, line->stash_data, 4096);
}

// Entries sit back to back in the pool, each followed by '\n', so the pool
// prefix is exactly the history-file format and saving is a single write.
// The slices borrow from the pool and exclude the '\n'.
class CLineHistory
{
  U8 *pool;
  I64 capacity;
  I64 used;
  CStrs *entries;
  I64 max;
  I64 count;
};

public U0 LineHistoryInit(CLineHistory *history, U8 *pool, I64 capacity,
  CStrs *entries, I64 max)
{
  history->pool = pool;
  history->capacity = capacity;
  history->used = 0;
  history->entries = entries;
  history->max = max;
  history->count = 0;
}

class CLineHistoryBuf : CLineHistory
{
  U8 pool_data[32768];
  CStrs entry_slices[256];
};

public U0 LineHistoryBufInit(CLineHistoryBuf *history)
{
  LineHistoryInit(history, history->pool_data, 32768,
    history->entry_slices, 256);
}

U0 LineHistoryDrop(CLineHistory *history)  // forget the oldest entry
{
  I64 first = StrsLen(&history->entries[0]) + 1;
  I64 i;

  LineMoveBytes(history->pool, history->pool + first,
    history->used - first);
  history->used -= first;
  history->count--;
  for (i = 0; i < history->count; i++)
    StrsInit(&history->entries[i], history->entries[i + 1].a - first,
      history->entries[i + 1].b - first);
}

U0 LineHistoryAddStrs(CLineHistory *history, CStrs *text)
{
  I64 length = StrsLen(text);

  if (!length || length + 1 > history->capacity)
    return;
  if (history->count &&
    StrsEquals(&history->entries[history->count - 1], text))
    return;
  while (history->count == history->max ||
    history->used + length + 1 > history->capacity)
    LineHistoryDrop(history);
  MemCpy(history->pool + history->used, text->a, length);
  history->pool[history->used + length] = '\n';
  StrsInitN(&history->entries[history->count],
    history->pool + history->used, length);
  history->count++;
  history->used += length + 1;
}

// Skips empties and repeats of the newest entry.
public U0 LineHistoryAdd(CLineHistory *history, U8 *text)
{
  CStrs slice;

  if (!text)
    return;
  StrsInitS(&slice, text);
  LineHistoryAddStrs(history, &slice);
}

public Bool LineHistoryLoad(CLineHistory *history, U8 *path)
{
  I64 size;
  U8 *data = FileRead(path, &size);
  CStrs rest, entry;

  if (!data)
    return FALSE;
  StrsInitN(&rest, data, size);
  while (!StrsEmpty(&rest)) {
    StrsSplitC(&rest, '\n', &entry, &rest);
    LineHistoryAddStrs(history, &entry);
  }
  Free(data);
  return TRUE;
}

public Bool LineHistorySave(CLineHistory *history, U8 *path)
{
  return FileWrite(path, history->pool, history->used);
}

// The lib/line callbacks over a CLineHistory.
I64 LineHistoryCount(CLine *line, U8 *user)
{
  return user(CLineHistory *)->count;
}

Bool LineHistoryGet(CLine *line, I64 index, CStrs *entry, U8 *user)
{
  CLineHistory *history = user(CLineHistory *);

  if (index < 0 || index >= history->count)
    return FALSE;
  *entry = history->entries[index];
  return TRUE;
}

public U0 LineHistoryAttach(CLine *line, CLineHistory *history)
{
  LineSetHistory(line, &LineHistoryCount, &LineHistoryGet, history(U8 *));
}

#endif
