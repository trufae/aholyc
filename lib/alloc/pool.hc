#ifndef AHOLYC_LIB_ALLOC_POOL_HC
#define AHOLYC_LIB_ALLOC_POOL_HC

#include "alloc.hc"

class CPoolBlock
{
  CPoolBlock *next;
};

// Fixed-size blocks backed by caller-owned memory. Free blocks store their
// next pointer in place, so allocation and free need no external metadata.
class CPoolAllocator
{
  CAllocator allocator;
  U8 *memory;
  CPoolBlock *free_list;
  I64 block_size;
  I64 stride;
  I64 count;
  I64 available;
  I64 alignment;
};

U8 *PoolAllocatorRealloc(U8 *context, U8 *memory, I64 old_size,
  I64 new_size, I64 alignment)
{
  CPoolAllocator *pool = context(CPoolAllocator *);
  CPoolBlock *block;
  U64 address;
  I64 position;

  if (!pool || old_size < 0 || new_size < 0 ||
    !AllocAlignmentValid(alignment) || alignment > pool->alignment ||
    !pool->memory || pool->block_size < sizeof(CPoolBlock) ||
    pool->stride < pool->block_size || pool->count <= 0 ||
    pool->available < 0 || pool->available > pool->count)
    return NULL;
  if (!memory) {
    if (old_size || !new_size || new_size > pool->block_size ||
      !pool->available || !pool->free_list)
      return NULL;
    block = pool->free_list;
    pool->free_list = block->next;
    pool->available--;
    return block(U8 *);
  }

  address = memory(U64);
  if ((address & (alignment - 1)) || address < pool->memory(U64))
    return NULL;
  address -= pool->memory(U64);
  if (address > I64_MAX)
    return NULL;
  position = address;
  if (position % pool->stride || position / pool->stride >= pool->count ||
    old_size > pool->block_size || pool->available >= pool->count)
    return NULL;
  if (!new_size) {
    block = memory(CPoolBlock *);
    block->next = pool->free_list;
    pool->free_list = block;
    pool->available++;
    return NULL;
  }
  if (new_size > pool->block_size)
    return NULL;
  return memory;
}

U0 PoolAllocatorFree(U8 *context, U8 *memory, I64 size, I64 alignment)
{
  CPoolAllocator *pool = context(CPoolAllocator *);
  CPoolBlock *block;
  U64 address;
  I64 position;

  if (!pool || !memory || size < 0 || size > pool->block_size ||
    !AllocAlignmentValid(alignment) || alignment > pool->alignment ||
    !pool->memory || pool->block_size < sizeof(CPoolBlock) ||
    pool->stride < pool->block_size || pool->count <= 0 ||
    pool->available < 0 || pool->available >= pool->count)
    return;
  address = memory(U64);
  if ((address & (alignment - 1)) || address < pool->memory(U64))
    return;
  address -= pool->memory(U64);
  if (address > I64_MAX)
    return;
  position = address;
  if (position % pool->stride || position / pool->stride >= pool->count)
    return;
  block = memory(CPoolBlock *);
  block->next = pool->free_list;
  pool->free_list = block;
  pool->available++;
}

U0 PoolAllocatorReset(CPoolAllocator *pool)
{
  CPoolBlock *block;
  I64 i;

  if (!pool || !pool->memory || pool->stride < pool->block_size ||
    pool->block_size < sizeof(CPoolBlock) || pool->count <= 0)
    return;
  pool->free_list = NULL;
  for (i = pool->count; i; i--) {
    block = (pool->memory + (i - 1) * pool->stride)(CPoolBlock *);
    block->next = pool->free_list;
    pool->free_list = block;
  }
  pool->available = pool->count;
}

CAllocator *PoolAllocatorInit(CPoolAllocator *pool, U8 *memory, I64 capacity,
  I64 block_size, I64 alignment=8)
{
  U64 address;
  I64 padding;
  I64 stride;
  I64 remainder;
  I64 count;

  if (!pool || !memory || capacity < 0 ||
    block_size < sizeof(CPoolBlock) || !AllocAlignmentValid(alignment) ||
    block_size > I64_MAX - (alignment - 1))
    return NULL;
  address = memory(U64);
  padding = address & (alignment - 1);
  if (padding)
    padding = alignment - padding;
  if (padding > capacity || address + padding < address)
    return NULL;
  stride = block_size;
  remainder = stride & (alignment - 1);
  if (remainder)
    stride += alignment - remainder;
  count = (capacity - padding) / stride;
  if (!count)
    return NULL;
  MemSet(pool, 0, sizeof(CPoolAllocator));
  pool->allocator.realloc_fn = &PoolAllocatorRealloc;
  pool->allocator.free_fn = &PoolAllocatorFree;
  pool->allocator.context = pool(U8 *);
  pool->memory = memory + padding;
  pool->block_size = block_size;
  pool->stride = stride;
  pool->count = count;
  pool->alignment = alignment;
  PoolAllocatorReset(pool);
  return &pool->allocator;
}

I64 PoolAllocatorAvailable(CPoolAllocator *pool)
{
  if (!pool || pool->available < 0 || pool->available > pool->count)
    return 0;
  return pool->available;
}

#endif
