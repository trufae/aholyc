#ifndef AHOLYC_LIB_ALLOC_ALLOC_HC
#define AHOLYC_LIB_ALLOC_ALLOC_HC

// Common allocator interface. A NULL CAllocator pointer selects MAlloc/Free.
// Custom realloc callbacks receive the old size so arenas do not need hidden
// allocation headers. realloc(NULL, 0, size, alignment) is allocation.

#define ALLOC_DEFAULT_ALIGNMENT 16

class CAllocator
{
  I64 realloc_fn;
  I64 free_fn;
  U8 *context;
};

Bool AllocAlignmentValid(I64 alignment)
{
  return alignment > 0 && !(alignment & (alignment - 1));
}

U8 *AllocDefaultRealloc(U8 *context, U8 *memory, I64 old_size,
  I64 new_size, I64 alignment)
{
  U8 *result;
  I64 copy_size;

  if (old_size < 0 || new_size < 0 ||
    !AllocAlignmentValid(alignment) || alignment > ALLOC_DEFAULT_ALIGNMENT)
    return NULL;
  if (!new_size) {
    Free(memory);
    return NULL;
  }
  result = MAlloc(new_size);
  if (!result)
    return NULL;
  if (memory) {
    copy_size = old_size;
    if (copy_size > new_size)
      copy_size = new_size;
    if (copy_size)
      MemCpy(result, memory, copy_size);
    Free(memory);
  }
  return result;
}

U0 AllocDefaultFree(U8 *context, U8 *memory, I64 size, I64 alignment)
{
  Free(memory);
}

U8 *AllocatorRealloc(CAllocator *allocator, U8 *memory, I64 old_size,
  I64 new_size, I64 alignment=8)
{
  if (old_size < 0 || new_size < 0 || !AllocAlignmentValid(alignment))
    return NULL;
  if (!allocator || !allocator->realloc_fn)
    return AllocDefaultRealloc(NULL, memory, old_size, new_size, alignment);
  return allocator->realloc_fn(allocator->context, memory, old_size, new_size,
    alignment);
}

U0 AllocatorFree(CAllocator *allocator, U8 *memory, I64 size,
  I64 alignment=8)
{
  if (!allocator || !allocator->realloc_fn) {
    AllocDefaultFree(NULL, memory, size, alignment);
  } else if (allocator->free_fn) {
    allocator->free_fn(allocator->context, memory, size, alignment);
  }
}

#endif
