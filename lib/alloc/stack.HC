#ifndef AHOLYC_LIB_ALLOC_STACK_HC
#define AHOLYC_LIB_ALLOC_STACK_HC

#include "alloc.hc"

// Fixed-buffer LIFO allocator. Allocations carry no headers; the caller-
// supplied old size is enough to resize or release the most recent block.
class CStackAllocator
{
  CAllocator allocator;
  U8 *memory;
  I64 capacity;
  I64 used;
};

U8 *StackAllocatorRealloc(U8 *context, U8 *memory, I64 old_size,
  I64 new_size, I64 alignment)
{
  CStackAllocator *stack = context(CStackAllocator *);
  U64 address;
  I64 position;
  I64 padding;
  I64 remaining;
  U8 *result;

  if (!stack || old_size < 0 || new_size < 0 ||
    !AllocAlignmentValid(alignment) || stack->capacity < 0 ||
    stack->used < 0 || stack->used > stack->capacity ||
    (!stack->memory && stack->capacity))
    return NULL;

  if (!memory) {
    if (old_size || !new_size)
      return NULL;
    address = stack->memory(U64) + stack->used;
    if (address < stack->memory(U64))
      return NULL;
    padding = address & (alignment - 1);
    if (padding)
      padding = alignment - padding;
    remaining = stack->capacity - stack->used;
    if (padding > remaining || new_size > remaining - padding)
      return NULL;
    position = stack->used + padding;
    result = stack->memory + position;
    stack->used = position + new_size;
    return result;
  }

  address = memory(U64);
  if ((address & (alignment - 1)) || address < stack->memory(U64))
    return NULL;
  address -= stack->memory(U64);
  if (address > I64_MAX)
    return NULL;
  position = address;
  if (position > stack->capacity ||
    old_size > stack->capacity - position ||
    position + old_size != stack->used)
    return NULL;

  if (!new_size) {
    stack->used = position;
    return NULL;
  }
  if (new_size <= stack->capacity - position) {
    stack->used = position + new_size;
    return memory;
  }
  return NULL;
}

U0 StackAllocatorFree(U8 *context, U8 *memory, I64 size, I64 alignment)
{
  CStackAllocator *stack = context(CStackAllocator *);
  U64 address;
  I64 position;

  if (!stack || !memory || size < 0 ||
    !AllocAlignmentValid(alignment) || stack->capacity < 0 ||
    stack->used < 0 || stack->used > stack->capacity ||
    (!stack->memory && stack->capacity))
    return;
  address = memory(U64);
  if ((address & (alignment - 1)) || address < stack->memory(U64))
    return;
  address -= stack->memory(U64);
  if (address > I64_MAX)
    return;
  position = address;
  if (position <= stack->capacity &&
    size <= stack->capacity - position &&
    position + size == stack->used)
    stack->used = position;
}

Bool StackAllocatorInit(CStackAllocator *stack, U8 *memory, I64 capacity)
{
  if (!stack || capacity < 0 || (!memory && capacity))
    return FALSE;
  MemSet(stack, 0, sizeof(CStackAllocator));
  stack->allocator.realloc_fn = &StackAllocatorRealloc;
  stack->allocator.free_fn = &StackAllocatorFree;
  stack->allocator.context = stack(U8 *);
  stack->memory = memory;
  stack->capacity = capacity;
  return TRUE;
}

CAllocator *StackAllocatorGet(CStackAllocator *stack)
{
  if (!stack)
    return NULL;
  return &stack->allocator;
}

I64 StackAllocatorMark(CStackAllocator *stack)
{
  if (!stack)
    return -1;
  return stack->used;
}

Bool StackAllocatorRewind(CStackAllocator *stack, I64 mark)
{
  if (!stack || stack->used < 0 || stack->used > stack->capacity ||
    mark < 0 || mark > stack->used)
    return FALSE;
  stack->used = mark;
  return TRUE;
}

U0 StackAllocatorReset(CStackAllocator *stack)
{
  if (stack)
    stack->used = 0;
}

I64 StackAllocatorAvailable(CStackAllocator *stack)
{
  if (!stack || stack->used < 0 || stack->capacity < stack->used)
    return 0;
  return stack->capacity - stack->used;
}

#endif
