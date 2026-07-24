// A compact string -> I64 hash table.
//
// Keys are borrowed: they must remain valid and unchanged while present in
// the table.  This keeps every slot to just a key pointer and an I64 value.
// Slots use linear probing; deletion shifts the following probe cluster back,
// so there are no tombstones and lookup cost does not deteriorate over time.

class CHashEntry
{
  U8 *key;
  I64 value;
};

class CHashTable
{
  CHashEntry *entries;
  I64 capacity; // Always a power of two.
  I64 count;
};

// FNV-1a followed by a 64-bit finalizer.  The finalizer matters because table
// indices are the low bits of the hash when capacity is a power of two.
/* @inline */ U64 HtHash(U8 *key)
{
  U64 hash = 1469598103934665603;

  while (*key) {
    hash ^= *key++;
    hash *= 1099511628211;
  }
  hash ^= hash >> 33;
  hash *= 0xff51afd7ed558ccd;
  hash ^= hash >> 33;
  hash *= 0xc4ceb9fe1a85ec53;
  return hash ^ hash >> 33;
}

/* @inline */ Bool HtKeyEquals(U8 *a, U8 *b)
{
  while (*a == *b) {
    if (!*a)
      return TRUE;
    a++;
    b++;
  }
  return FALSE;
}

/* @inline */ I64 HtRoundCapacity(I64 capacity)
{
  I64 result = 8;

  while (result < capacity)
    result *= 2;
  return result;
}

/* @inline */ U0 HtInitCapacity(CHashTable *table, I64 capacity)
{
  if (capacity < 8)
    capacity = 8;
  table->capacity = HtRoundCapacity(capacity);
  table->entries = CAlloc(table->capacity * sizeof(CHashEntry));
  table->count = 0;
}

/* @inline */ U0 HtInit(CHashTable *table)
{
  HtInitCapacity(table, 8);
}

// Return the occupied slot for key, or NULL when it is absent.
/* @inline */ CHashEntry *HtFind(CHashTable *table, U8 *key)
{
  I64 mask;
  I64 index;
  CHashEntry *entry;

  if (!table->entries || !key)
    return NULL;
  mask = table->capacity - 1;
  index = HtHash(key) & mask;
  while (TRUE) {
    entry = &table->entries[index];
    if (!entry->key)
      return NULL;
    if (HtKeyEquals(entry->key, key))
      return entry;
    index = (index + 1) & mask;
  }
}

/* @inline */ Bool HtGet(CHashTable *table, U8 *key, I64 *value)
{
  CHashEntry *entry = HtFind(table, key);

  if (!entry)
    return FALSE;
  if (value)
    *value = entry->value;
  return TRUE;
}

/* @inline */ U0 HtResize(CHashTable *table, I64 capacity)
{
  CHashEntry *old_entries = table->entries;
  I64 old_capacity = table->capacity;
  I64 i;

  HtInitCapacity(table, capacity);
  for (i = 0; i < old_capacity; i++) {
    CHashEntry *old = &old_entries[i];
    I64 index;
    I64 mask;

    if (old->key) {
      mask = table->capacity - 1;
      index = HtHash(old->key) & mask;
      while (table->entries[index].key)
        index = (index + 1) & mask;
      table->entries[index] = *old;
      table->count++;
    }
  }
  Free(old_entries);
}

// Insert or replace key.  Returns TRUE only when a new key was inserted.
/* @inline */ Bool HtPut(CHashTable *table, U8 *key, I64 value)
{
  CHashEntry *entry;
  I64 index;
  I64 mask;

  if (!key)
    return FALSE;
  if (!table->entries)
    HtInit(table);
  entry = HtFind(table, key);
  if (entry) {
    entry->value = value;
    return FALSE;
  }
  // Keep the load factor at or below 75%; this is a good speed/space point
  // for cache-friendly linear probing without per-entry metadata.
  if ((table->count + 1) * 4 > table->capacity * 3)
    HtResize(table, table->capacity * 2);

  mask = table->capacity - 1;
  index = HtHash(key) & mask;
  while (table->entries[index].key)
    index = (index + 1) & mask;
  table->entries[index].key = key;
  table->entries[index].value = value;
  table->count++;
  return TRUE;
}

// Delete key using backward-shift deletion.  It preserves every probe chain
// and avoids the extra state byte or tombstone required by other schemes.
/* @inline */ Bool HtDelete(CHashTable *table, U8 *key)
{
  CHashEntry *entry = HtFind(table, key);
  I64 hole;
  I64 scan;
  I64 mask;

  if (!entry)
    return FALSE;
  mask = table->capacity - 1;
  hole = entry - table->entries;
  scan = (hole + 1) & mask;
  while (table->entries[scan].key) {
    I64 home = HtHash(table->entries[scan].key) & mask;

    if (((scan - home) & mask) > ((hole - home) & mask)) {
      table->entries[hole] = table->entries[scan];
      hole = scan;
    }
    scan = (scan + 1) & mask;
  }
  table->entries[hole].key = NULL;
  table->entries[hole].value = 0;
  table->count--;
  return TRUE;
}

/* @inline */ U0 HtClear(CHashTable *table)
{
  if (table->entries)
    MemSet(table->entries, 0, table->capacity * sizeof(CHashEntry));
  table->count = 0;
}

/* @inline */ U0 HtFini(CHashTable *table)
{
  Free(table->entries);
  table->entries = NULL;
  table->capacity = 0;
  table->count = 0;
}

// Pass index = 0 for the first entry, then pass the returned index + 1.
// Returns -1 when no more entries exist.
/* @inline */ I64 HtNext(CHashTable *table, I64 index, CHashEntry **entry)
{
  while (index < table->capacity) {
    if (table->entries[index].key) {
      if (entry)
        *entry = &table->entries[index];
      return index;
    }
    index++;
  }
  if (entry)
    *entry = NULL;
  return -1;
}
