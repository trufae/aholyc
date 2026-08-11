#include "../lib/alloc/linear.hc"

U0 LinearExample()
{
  U8 storage[128];
  CLinearAllocator linear;
  CAllocator *allocator = LinearAllocatorInit(&linear, storage,
    sizeof(storage));
  U8 *first = AllocatorAlloc(allocator, 4);
  first[0] = 42;
  U8 *middle = AllocatorAlloc(allocator, 8, 16);
  I64 before_free = LinearAllocatorMark(&linear);
  AllocatorFree(allocator, middle, 8, 16);
  Bool free_noop = before_free == LinearAllocatorMark(&linear);
  U8 *grown = AllocatorRealloc(allocator, first, 4, 12);
  Bool moved = grown != first;
  Bool copied = grown[0] == 42;
  U8 *resized = AllocatorRealloc(allocator, grown, 12, 20);
  Bool in_place = resized == grown;
  I64 mark = LinearAllocatorMark(&linear);
  AllocatorAlloc(allocator, 7);
  Bool rewound = LinearAllocatorRewind(&linear, mark) &&
    LinearAllocatorMark(&linear) == mark;
  Bool aligned = !(middle(U64) & 15);

  LinearAllocatorReset(&linear);
  "aligned=%d copied=%d moved=%d in-place=%d free-noop=%d rewind=%d available=%d\n",
    aligned, copied, moved, in_place, free_noop, rewound,
    LinearAllocatorAvailable(&linear);
}

LinearExample;
