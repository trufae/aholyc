# Allocators

`alloc.hc` defines the small allocator contract shared by libraries that need
dynamic storage without imposing an allocation policy.

```c
class CAllocator
{
  U8 *(*realloc_fn)(U8 *context, U8 *memory, I64 old_size, I64 new_size,
    I64 alignment);
  U0 (*free_fn)(U8 *context, U8 *memory, I64 size, I64 alignment);
  U8 *context;
};
```

Allocation is the subset `realloc(context, NULL, 0, size, alignment)`.
`old_size` lets arenas resize without storing a header for every allocation.
The callback preserves the old allocation when it cannot resize. `free` may
be `NULL` for a monotonic arena.

`AllocatorAlloc(allocator, size, alignment)` is the allocation shorthand;
the alignment defaults to 8. `AllocatorRealloc` and `AllocatorFree` retain
the explicit old/current size so headerless allocators can validate requests.

Library APIs accept `CAllocator *`; `NULL` selects `MAlloc`/`Free` through a
portable allocate-copy-free implementation. The default supports alignments
up to `ALLOC_DEFAULT_ALIGNMENT` (16). Custom allocators may support larger
alignments.

`linear.hc` is a fixed-buffer bump allocator for scratch data and grouped
lifetimes. Individual frees are no-ops. The newest allocation can resize in
place; growing an older allocation moves it to the end and leaves the old
storage occupied. Marks, rewind, and reset release allocations in bulk.

`stack.HC` implements this interface as a fixed-buffer LIFO allocator.
`StackAllocatorInit` returns its `CAllocator *` on success, so initialization
and passing the allocator takes one expression. The backing buffer may itself
live on the stack, in static storage, or inside a larger arena.

`arena.hc` tracks heap-backed allocations and releases them individually or
as a group. `ArenaInit(&arena)` initializes a `CAllocationManager` and returns
the `CAllocator *` accepted by allocator-aware APIs. The adapter supports
allocation, resize, and free with alignments up to 16 bytes.
