#ifndef AHOLYC_LIB_ALLOC_LINEAR_HC
#define AHOLYC_LIB_ALLOC_LINEAR_HC

#include "alloc.hc"

// Fixed-buffer bump allocator. Free is a no-op; use a mark or reset to
// release allocations together. The newest allocation can resize in place.
class CLinearAllocator
{
  CAllocator allocator;
  U8 *memory;
  I64 capacity;
  I64 used;
};

U8 *LinearAllocatorRealloc(U8 *context, U8 *memory, I64 old_size,
  I64 new_size, I64 alignment)
{
  CLinearAllocator *linear = context(CLinearAllocator *);
  U64 address;
  I64 position;
  I64 padding;
  I64 remaining;
  U8 *result;

  if (!linear || old_size < 0 || new_size < 0 ||
    !AllocAlignmentValid(alignment) || linear->capacity < 0 ||
    linear->used < 0 || linear->used > linear->capacity ||
    (!linear->memory && linear->capacity))
    return NULL;

  if (memory) {
    address = memory(U64);
    if ((address & (alignment - 1)) || address < linear->memory(U64))
      return NULL;
    address -= linear->memory(U64);
    if (address > I64_MAX)
      return NULL;
    position = address;
    if (position > linear->used || old_size > linear->used - position)
      return NULL;
    if (position + old_size == linear->used) {
      if (new_size > linear->capacity - position)
        return NULL;
      linear->used = position + new_size;
      if (!new_size)
        return NULL;
      return memory;
    }
    if (!new_size)
      return NULL;
    if (new_size <= old_size)
      return memory;
  } else if (old_size || !new_size) {
    return NULL;
  }

  address = linear->memory(U64) + linear->used;
  if (address < linear->memory(U64))
    return NULL;
  padding = address & (alignment - 1);
  if (padding)
    padding = alignment - padding;
  remaining = linear->capacity - linear->used;
  if (padding > remaining || new_size > remaining - padding)
    return NULL;
  position = linear->used + padding;
  result = linear->memory + position;
  linear->used = position + new_size;
  if (memory)
    MemCpy(result, memory, old_size);
  return result;
}

CAllocator *LinearAllocatorInit(CLinearAllocator *linear, U8 *memory,
  I64 capacity)
{
  if (!linear || capacity < 0 || (!memory && capacity))
    return NULL;
  MemSet(linear, 0, sizeof(CLinearAllocator));
  linear->allocator.realloc_fn = &LinearAllocatorRealloc;
  linear->allocator.context = linear(U8 *);
  linear->memory = memory;
  linear->capacity = capacity;
  return &linear->allocator;
}

I64 LinearAllocatorMark(CLinearAllocator *linear)
{
  if (!linear)
    return -1;
  return linear->used;
}

Bool LinearAllocatorRewind(CLinearAllocator *linear, I64 mark)
{
  if (!linear || linear->used < 0 || linear->used > linear->capacity ||
    mark < 0 || mark > linear->used)
    return FALSE;
  linear->used = mark;
  return TRUE;
}

U0 LinearAllocatorReset(CLinearAllocator *linear)
{
  if (linear)
    linear->used = 0;
}

I64 LinearAllocatorAvailable(CLinearAllocator *linear)
{
  if (!linear || linear->used < 0 || linear->capacity < linear->used)
    return 0;
  return linear->capacity - linear->used;
}

#endif
