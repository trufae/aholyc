// lib/io/dir.hc fixture: creation, listing through raw kernel records with
// several scratch sizes, exact error codes, cancellation, and recursive
// removal that must not follow links. Every step returns a distinct status.
#include "lib/io/dir.hc"
#include "lib/io/file.hc"

#ifdef DIR_WINDOWS
#define LONG_NAME 200
#else
#define LONG_NAME 255
extern I64 symlink(U8 *target, U8 *path);
#endif

#define MANY 300
#define DEEP 60

I64 entries;
I64 directories;
Bool seen_item;
I64 stop_calls;

Bool CountEntry(U8 *path, CDirEntry *entry, U0 *user)
{
  I64 *counter = user;

  entries++;
  if (entry->type == DIR_TYPE_DIR)
    directories++;
  if (!StrCmp(path, "tests/out/io-dir/a/b") && !StrCmp(entry->name, "item") &&
    entry->name_length == 4 &&
    (entry->type == DIR_TYPE_FILE || entry->type == DIR_TYPE_UNKNOWN))
    seen_item = TRUE;
  if (counter)
    (*counter)++;
  return TRUE;
}

Bool StopEntry(U8 *path, CDirEntry *entry, U0 *user)
{
  stop_calls++;
  return FALSE;
}

// A second, independent iterator inside a callback of the first one.
Bool NestedEntry(U8 *path, CDirEntry *entry, U0 *user)
{
  CDirBuf inner;
  CDirEntry item;
  I64 count = 0;

  entries++;
  if (StrLen(entry->name) != entry->name_length)
    return FALSE;
  if (!DirOpen(&inner, "tests/out/io-dir/a/b"))
    return FALSE;
  while (DirRead(&inner, &item) > 0)
    count++;
  return !DirClose(&inner) && count == 1;
}

// Entries below path using a caller scratch; longest receives the longest
// name. Negative on any failure.
I64 CountWith(U8 *path, U8 *scratch, I64 size, I64 *longest)
{
  CDir dir;
  CDirEntry entry;
  I64 count = 0;
  I64 result;

  if (DirOpenBuf(&dir, path, scratch, size) < 0)
    return -1;
  while ((result = DirRead(&dir, &entry)) > 0) {
    if (StrLen(entry.name) != entry.name_length)
      return -2;
    if (entry.name_length > *longest)
      *longest = entry.name_length;
    count++;
  }
  if (result < 0 || DirClose(&dir) < 0)
    return -3;
  return count;
}

I64 Main()
{
  CDirBuf dir;
  CDirEntry entry;
  U8 path[512];
  U8 big[16384];
  U8 *name;
  I64 i, counter, longest, prefix;

  DirRemove("tests/out/io-dir", TRUE);

  // Creation
  if (!DirCreate("tests/out/io-dir/a/b", TRUE))
    return 1;
  if (!DirIsDir("tests/out/io-dir/a/b") || !DirExists("tests/out/io-dir/a"))
    return 2;
  if (!DirCreate("tests/out/io-dir/a/b/", TRUE) ||
    !DirCreate("tests/out/io-dir/./a//b", TRUE))
    return 3;
  if (DirCreate("tests/out/io-dir/a/b"))
    return 4;
  if (DirCreateEx("tests/out/io-dir/a/b") != DIR_ERROR_EXISTS)
    return 5;
  if (!FileWrite("tests/out/io-dir/a/b/item", "ok"))
    return 6;
  if (DirIsDir("tests/out/io-dir/a/b/item"))
    return 7;
  if (DirCreate("tests/out/io-dir/a/b/item", TRUE))
    return 8;
  if (DirCreate("tests/out/io-dir/a/b/item/x", TRUE))
    return 9;

  // Streaming iteration
  if (!DirOpen(&dir, "tests/out/io-dir/a/b"))
    return 10;
  if (DirRead(&dir, &entry) != 1 || StrCmp(entry.name, "item") ||
    entry.name_length != 4)
    return 11;
  if (DirRead(&dir, &entry) || DirRead(&dir, &entry))
    return 12;
  if (DirRewind(&dir) < 0 || !(name = DirNext(&dir)) ||
    StrCmp(name, "item") || DirNext(&dir) || dir.error)
    return 13;
  if (DirClose(&dir) || DirClose(&dir))
    return 14;
  if (DirRead(&dir, &entry) != DIR_ERROR_CLOSED)
    return 15;

  // Exact errors
  if (DirOpenBuf(&dir, "tests/out/io-dir/nope", dir.buffer,
      DIR_BUFFER_SIZE) != DIR_ERROR_NOT_FOUND)
    return 16;
  if (DirOpenBuf(&dir, "tests/out/io-dir/a/b/item", dir.buffer,
      DIR_BUFFER_SIZE) != DIR_ERROR_NOT_DIR)
    return 17;
  if (DirOpenBuf(&dir, "tests/out/io-dir/a/b", dir.buffer,
      DIR_SCRATCH_MIN - 1) != DIR_ERROR_INVALID || DirClose(&dir))
    return 18;

  // Callbacks, user data, and cancellation
  entries = 0;
  directories = 0;
  seen_item = FALSE;
  if (DirForEach("tests/out/io-dir/a/b", &CountEntry) != 1 || entries != 1 ||
    !seen_item)
    return 19;
  counter = 0;
  if (DirForEach("tests/out/io-dir/a", &CountEntry, &counter) != 1 ||
    counter != 1 || directories != 1)
    return 20;
  if (DirForEach("tests/out/io-dir/a/b", &StopEntry) != 0 || stop_calls != 1)
    return 21;
  if (DirForEach("tests/out/io-dir/nope", &CountEntry) != DIR_ERROR_NOT_FOUND)
    return 22;

  // Many entries across several scratch refills, plus a maximal name
  if (!DirCreate("tests/out/io-dir/many", TRUE))
    return 23;
  for (i = 0; i < MANY; i++) {
    StrPrint(path, "tests/out/io-dir/many/f%d", i);
    if (!FileWrite(path, "x"))
      return 24;
  }
  StrPrint(path, "tests/out/io-dir/many/");
  prefix = StrLen(path);
  MemSet(path + prefix, 'x', LONG_NAME);
  path[prefix + LONG_NAME] = 0;
  if (!FileWrite(path, "x"))
    return 25;
  longest = 0;
  if (CountWith("tests/out/io-dir/many", dir.buffer, DIR_BUFFER_SIZE,
      &longest) != MANY + 1 || longest != LONG_NAME)
    return 26;
  longest = 0;
  if (CountWith("tests/out/io-dir/many", big, sizeof(big), &longest) !=
    MANY + 1 || longest != LONG_NAME)
    return 27;
  longest = 0;
  if (CountWith("tests/out/io-dir/many", big, DIR_SCRATCH_MIN, &longest) !=
    MANY + 1 || longest != LONG_NAME)
    return 28;
  entries = 0;
  if (DirForEach("tests/out/io-dir/many", &NestedEntry) != 1 ||
    entries != MANY + 1)
    return 29;

  #ifndef DIR_WINDOWS
  // Links: never followed on removal, refused as a removal root
  if (!DirCreate("tests/out/io-dir/outside", TRUE) ||
    !FileWrite("tests/out/io-dir/outside/keep", "x"))
    return 30;
  if (symlink("../../outside", "tests/out/io-dir/a/b/link")(I32) ||
    symlink("item", "tests/out/io-dir/a/b/itemlink")(I32) ||
    symlink("nowhere", "tests/out/io-dir/a/dangling")(I32) ||
    symlink("outside", "tests/out/io-dir/rootlink")(I32))
    return 31;
  if (!DirIsDir("tests/out/io-dir/a/b/link"))
    return 32;
  entries = 0;
  if (DirForEach("tests/out/io-dir/a/b", &CountEntry) != 1 || entries != 3)
    return 33;
  if (DirRemoveEx("tests/out/io-dir/rootlink", TRUE) != DIR_ERROR_NOT_DIR ||
    !DirIsDir("tests/out/io-dir/outside"))
    return 34;
  if (!DirRemove("tests/out/io-dir/a", TRUE))
    return 35;
  if (!FileExists("tests/out/io-dir/outside/keep") ||
    DirIsDir("tests/out/io-dir/a"))
    return 36;
  #endif

  // Deep tree and empty-only removal
  StrPrint(path, "tests/out/io-dir/deep");
  for (i = 0; i < DEEP; i++)
    StrPrint(path + StrLen(path), "/d");
  if (!DirCreate(path, TRUE))
    return 37;
  StrPrint(path + StrLen(path), "/leaf");
  if (!FileWrite(path, "x"))
    return 38;
  if (DirRemove("tests/out/io-dir/deep") ||
    DirRemoveEx("tests/out/io-dir/deep") != DIR_ERROR_NOT_EMPTY)
    return 39;
  if (!DirRemove("tests/out/io-dir/deep", TRUE) ||
    DirIsDir("tests/out/io-dir/deep"))
    return 40;
  if (!DirRemove("tests/out/io-dir", TRUE) || DirIsDir("tests/out/io-dir"))
    return 41;
  if (DirRemoveEx("tests/out/io-dir", TRUE) != DIR_ERROR_NOT_FOUND)
    return 42;
  return 0;
}

I64 status = Main;

if (status)
  "io_dir: step %d failed\n", status;
return status;
