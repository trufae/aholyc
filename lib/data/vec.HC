// Contiguous, growable vectors for HolyC.
//
// CVec is the data-driven form: item_size is supplied at initialization, so
// one implementation handles any trivially-copyable type.  For hot code,
// define VEC_NAME and VEC_TYPE (as strings) before including this file.  The
// #exe block then emits a compact, statically typed vector for that type:
//
//   class CPoint { I64 x; I64 y; };
//   #define VEC_NAME "CPointVec"
//   #define VEC_TYPE "CPoint"
//   #include "../lib/data/vec.HC"
//
// Generated vectors store only data/count/capacity and expose CPointVecInit,
// CPointVecReserve, CPointVecEmplace, CPointVecPush, CPointVecAt,
// CPointVecLast, CPointVecPop, CPointVecErase, CPointVecFind,
// CPointVecFindIf, CPointVecSort, CPointVecClear, and CPointVecFini.
// Include this file again with another pair of definitions to generate
// another type.  Elements must be trivially copyable.

#ifndef AHOLYC_LIB_DATA_VEC_HC
#define AHOLYC_LIB_DATA_VEC_HC

/* @align */ class CVec
{
  U8 *data;
  I64 item_size;
  I64 count;
  I64 capacity;
};

// Double capacity: fewer allocations and copies for append-heavy workloads.
// Returns 0 when the requested capacity cannot be represented.
I64 VecCapacityFor(I64 capacity, I64 needed)
{
  I64 result;

  if (needed < 0)
    return 0;
  result = capacity;
  if (result < 8)
    result = 8;
  while (result < needed) {
    if (result > I64_MAX / 2)
      return 0;
    result *= 2;
  }
  return result;
}

U0 VecInit(CVec *vector, I64 item_size)
{
  vector->data = NULL;
  vector->item_size = item_size;
  vector->count = 0;
  vector->capacity = 0;
}

Bool VecReserve(CVec *vector, I64 needed)
{
  U8 *data;
  I64 capacity;

  if (needed <= vector->capacity)
    return TRUE;
  if (vector->item_size <= 0)
    return FALSE;
  capacity = VecCapacityFor(vector->capacity, needed);
  if (!capacity || capacity > I64_MAX / vector->item_size)
    return FALSE;
  data = MAlloc(capacity * vector->item_size);
  if (!data)
    return FALSE;
  if (vector->data) {
    MemCpy(data, vector->data, vector->count * vector->item_size);
    Free(vector->data);
  }
  vector->data = data;
  vector->capacity = capacity;
  return TRUE;
}

// Reserve one uninitialized element.  Fill it before making another call
// that can reallocate the vector.
U8 *VecEmplace(CVec *vector)
{
  U8 *item;

  if (vector->count == I64_MAX || !VecReserve(vector, vector->count + 1))
    return NULL;
  item = vector->data + vector->count * vector->item_size;
  vector->count++;
  return item;
}

Bool VecPush(CVec *vector, U8 *item)
{
  U8 *destination = VecEmplace(vector);

  if (!destination)
    return FALSE;
  MemCpy(destination, item, vector->item_size);
  return TRUE;
}

// Appending a vector to itself is supported.
Bool VecAppend(CVec *vector, CVec *items)
{
  I64 old_count;
  I64 bytes;
  I64 i;

  if (vector->item_size != items->item_size || items->count < 0)
    return FALSE;
  if (items->count > I64_MAX - vector->count)
    return FALSE;
  old_count = vector->count;
  if (!VecReserve(vector, old_count + items->count))
    return FALSE;
  bytes = items->count * vector->item_size;
  if (vector == items) {
    // Destination begins after the source, so a forward byte copy is safe.
    for (i = 0; i < bytes; i++)
      vector->data[old_count * vector->item_size + i] = vector->data[i];
  } else if (bytes) {
    MemCpy(vector->data + old_count * vector->item_size, items->data, bytes);
  }
  vector->count = old_count + items->count;
  return TRUE;
}

U8 *VecAt(CVec *vector, I64 index)
{
  if (index < 0 || index >= vector->count)
    return NULL;
  return vector->data + index * vector->item_size;
}

U8 *VecLast(CVec *vector)
{
  return VecAt(vector, vector->count - 1);
}

Bool VecPop(CVec *vector, U8 *item)
{
  if (!vector->count)
    return FALSE;
  vector->count--;
  if (item)
    MemCpy(item, vector->data + vector->count * vector->item_size,
      vector->item_size);
  return TRUE;
}

// Stable removal.  This is intentionally a byte loop: the source and
// destination overlap, whereas MemCpy is only guaranteed for disjoint data.
Bool VecErase(CVec *vector, I64 index)
{
  I64 from;
  I64 bytes;
  I64 i;

  if (index < 0 || index >= vector->count)
    return FALSE;
  from = index * vector->item_size;
  bytes = (vector->count - index - 1) * vector->item_size;
  for (i = 0; i < bytes; i++)
    vector->data[from + i] = vector->data[from + vector->item_size + i];
  vector->count--;
  return TRUE;
}

// Unstable O(1) removal for order-insensitive data.
Bool VecEraseSwap(CVec *vector, I64 index)
{
  if (index < 0 || index >= vector->count)
    return FALSE;
  vector->count--;
  if (index != vector->count)
    MemCpy(vector->data + index * vector->item_size,
      vector->data + vector->count * vector->item_size, vector->item_size);
  return TRUE;
}

// Return the index of the first element for which compare returns zero, or
// -1.  compare is the address of I64 Compare(U8 *item, U8 *needle).
I64 VecFind(CVec *vector, U8 *needle, I64 compare)
{
  I64 i;

  if (!compare)
    return -1;
  for (i = 0; i < vector->count; i++) {
    if (!compare(vector->data + i * vector->item_size, needle))
      return i;
  }
  return -1;
}

// Predicate form for searches that are not equality comparisons.  matches is
// the address of Bool Matches(U8 *item, U8 *context); context may be NULL.
I64 VecFindIf(CVec *vector, I64 matches,
  U8 *context=NULL)
{
  I64 i;

  if (!matches)
    return -1;
  for (i = 0; i < vector->count; i++) {
    if (matches(vector->data + i * vector->item_size, context))
      return i;
  }
  return -1;
}

U0 VecSwapItems(CVec *vector, I64 a, I64 b, U8 *temporary)
{
  U8 *left;
  U8 *right;

  if (a == b)
    return;
  left = vector->data + a * vector->item_size;
  right = vector->data + b * vector->item_size;
  MemCpy(temporary, left, vector->item_size);
  MemCpy(left, right, vector->item_size);
  MemCpy(right, temporary, vector->item_size);
}

// Sift the item at root down a max heap ending at end (inclusive).
U0 VecSiftDown(CVec *vector, I64 root, I64 end,
  I64 compare, U8 *temporary)
{
  I64 child;

  while (root * 2 + 1 <= end) {
    child = root * 2 + 1;
    if (child + 1 <= end &&
      compare(vector->data + child * vector->item_size,
        vector->data + (child + 1) * vector->item_size) < 0)
      child++;
    if (compare(vector->data + root * vector->item_size,
      vector->data + child * vector->item_size) >= 0)
      return;
    VecSwapItems(vector, root, child, temporary);
    root = child;
  }
}

// In-place heap sort: O(n log n) worst case, O(1) auxiliary storage apart
// from one element-sized swap buffer, and no recursion or fragile pivot case.
// compare is the address of I64 Compare(U8 *a, U8 *b).  The vector is
// ordered ascending when Compare(a, b) is negative for a < b.
Bool VecSort(CVec *vector, I64 compare)
{
  U8 *temporary;
  I64 root;
  I64 end;

  if (!compare || vector->count < 2)
    return compare != NULL;
  temporary = MAlloc(vector->item_size);
  if (!temporary)
    return FALSE;
  root = vector->count / 2;
  while (root) {
    root--;
    VecSiftDown(vector, root, vector->count - 1, compare, temporary);
  }
  end = vector->count;
  while (end > 1) {
    end--;
    VecSwapItems(vector, 0, end, temporary);
    VecSiftDown(vector, 0, end - 1, compare, temporary);
  }
  Free(temporary);
  return TRUE;
}

U0 VecClear(CVec *vector)
{
  vector->count = 0;
}

U0 VecFini(CVec *vector)
{
  Free(vector->data);
  VecInit(vector, 0);
}

U0 VecSwap(CVec *a, CVec *b)
{
  CVec temporary = *a;

  *a = *b;
  *b = temporary;
}

#endif

#ifdef VEC_NAME
#ifndef VEC_TYPE
#error VEC_TYPE must be a string when VEC_NAME is defined
#endif
#exe {
  StreamPrint("/* @align */ class %s { %s *data; I64 count; I64 capacity; };",
    VEC_NAME, VEC_TYPE);
  StreamPrint("/* @inline */ U0 %sInit(%s *vector) { vector->data = 0; vector->count = 0; vector->capacity = 0; }",
    VEC_NAME, VEC_NAME);
  StreamPrint("/* @inline */ Bool %sReserve(%s *vector, I64 needed) { %s *data; I64 capacity; if (needed <= vector->capacity) return TRUE; capacity = VecCapacityFor(vector->capacity, needed); if (!capacity || capacity > I64_MAX / sizeof(%s)) return FALSE; data = MAlloc(capacity * sizeof(%s)); if (!data) return FALSE; if (vector->data) { MemCpy(data, vector->data, vector->count * sizeof(%s)); Free(vector->data); } vector->data = data; vector->capacity = capacity; return TRUE; }",
    VEC_NAME, VEC_NAME, VEC_TYPE, VEC_TYPE, VEC_TYPE, VEC_TYPE);
  StreamPrint("/* @inline */ %s *%sEmplace(%s *vector) { %s *item; if (vector->count == I64_MAX || !%sReserve(vector, vector->count + 1)) return 0; item = &vector->data[vector->count++]; return item; }",
    VEC_TYPE, VEC_NAME, VEC_NAME, VEC_TYPE, VEC_NAME);
  StreamPrint("/* @inline */ Bool %sPush(%s *vector, %s *item) { %s *destination = %sEmplace(vector); if (!destination) return FALSE; *destination = *item; return TRUE; }",
    VEC_NAME, VEC_NAME, VEC_TYPE, VEC_TYPE, VEC_NAME);
  StreamPrint("/* @inline */ %s *%sAt(%s *vector, I64 index) { if (index < 0 || index >= vector->count) return 0; return &vector->data[index]; }",
    VEC_TYPE, VEC_NAME, VEC_NAME);
  StreamPrint("/* @inline */ %s *%sLast(%s *vector) { return %sAt(vector, vector->count - 1); }",
    VEC_TYPE, VEC_NAME, VEC_NAME, VEC_NAME);
  StreamPrint("/* @inline */ Bool %sPop(%s *vector, %s *item) { if (!vector->count) return FALSE; vector->count--; if (item) *item = vector->data[vector->count]; return TRUE; }",
    VEC_NAME, VEC_NAME, VEC_TYPE);
  StreamPrint("/* @inline */ Bool %sErase(%s *vector, I64 index) { I64 i; if (index < 0 || index >= vector->count) return FALSE; for (i = index; i + 1 < vector->count; i++) vector->data[i] = vector->data[i + 1]; vector->count--; return TRUE; }",
    VEC_NAME, VEC_NAME);
  StreamPrint("/* @inline */ Bool %sEraseSwap(%s *vector, I64 index) { if (index < 0 || index >= vector->count) return FALSE; vector->count--; if (index != vector->count) vector->data[index] = vector->data[vector->count]; return TRUE; }",
    VEC_NAME, VEC_NAME);
  StreamPrint("/* @inline */ I64 %sFind(%s *vector, %s *needle, I64 compare) { I64 i; if (!compare) return -1; for (i = 0; i < vector->count; i++) if (!compare(&vector->data[i], needle)) return i; return -1; }",
    VEC_NAME, VEC_NAME, VEC_TYPE);
  StreamPrint("/* @inline */ I64 %sFindIf(%s *vector, I64 matches, U8 *context=0) { I64 i; if (!matches) return -1; for (i = 0; i < vector->count; i++) if (matches(&vector->data[i], context)) return i; return -1; }",
    VEC_NAME, VEC_NAME);
  StreamPrint("/* @inline */ U0 %sSwapItems(%s *vector, I64 a, I64 b) { %s temporary; if (a == b) return; temporary = vector->data[a]; vector->data[a] = vector->data[b]; vector->data[b] = temporary; }",
    VEC_NAME, VEC_NAME, VEC_TYPE);
  StreamPrint("/* @inline */ U0 %sSiftDown(%s *vector, I64 root, I64 end, I64 compare) { I64 child; while (root * 2 + 1 <= end) { child = root * 2 + 1; if (child + 1 <= end && compare(&vector->data[child], &vector->data[child + 1]) < 0) child++; if (compare(&vector->data[root], &vector->data[child]) >= 0) return; %sSwapItems(vector, root, child); root = child; } }",
    VEC_NAME, VEC_NAME, VEC_NAME);
  StreamPrint("/* @inline */ Bool %sSort(%s *vector, I64 compare) { I64 root; I64 end; if (!compare) return FALSE; if (vector->count < 2) return TRUE; root = vector->count / 2; while (root) { root--; %sSiftDown(vector, root, vector->count - 1, compare); } end = vector->count; while (end > 1) { end--; %sSwapItems(vector, 0, end); %sSiftDown(vector, 0, end - 1, compare); } return TRUE; }",
    VEC_NAME, VEC_NAME, VEC_NAME, VEC_NAME, VEC_NAME);
  StreamPrint("/* @inline */ U0 %sClear(%s *vector) { vector->count = 0; }",
    VEC_NAME, VEC_NAME);
  StreamPrint("/* @inline */ U0 %sFini(%s *vector) { Free(vector->data); %sInit(vector); }",
    VEC_NAME, VEC_NAME, VEC_NAME);
};
#undef VEC_NAME
#undef VEC_TYPE
#endif
