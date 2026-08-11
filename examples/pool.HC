#include "../lib/alloc/pool.hc"

U0 PoolExample()
{
  U8 storage[160];
  CPoolAllocator pool;
  CAllocator *allocator = PoolAllocatorInit(&pool, storage, sizeof(storage),
    16, 16);
  I64 initial = PoolAllocatorAvailable(&pool);
  U8 *first = AllocatorAlloc(allocator, 8, 16);
  U8 *second = AllocatorAlloc(allocator, 16, 16);
  Bool aligned = !(first(U64) & 15) && !(second(U64) & 15);
  first[0] = 42;
  U8 *resized = AllocatorRealloc(allocator, first, 8, 16, 16);
  Bool in_place = resized == first && resized[0] == 42;
  Bool rejected = !AllocatorRealloc(allocator, resized, 16, 17, 16);
  AllocatorFree(allocator, resized, 16, 16);
  U8 *reused = AllocatorAlloc(allocator, 16, 16);
  Bool reuse = reused == first;
  Bool counts = PoolAllocatorAvailable(&pool) == initial - 2;

  PoolAllocatorReset(&pool);
  Bool reset = PoolAllocatorAvailable(&pool) == initial;
  "aligned=%d reuse=%d in-place=%d rejected=%d counts=%d reset=%d\n",
    aligned, reuse, in_place, rejected, counts, reset;
}

PoolExample;
