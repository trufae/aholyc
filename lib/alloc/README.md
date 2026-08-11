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

Library APIs accept `CAllocator *`; `NULL` selects `MAlloc`/`Free` through a
portable allocate-copy-free implementation. The default supports alignments
up to `ALLOC_DEFAULT_ALIGNMENT` (16). Custom allocators may support larger
alignments.

`stack.HC` implements this interface as a fixed-buffer LIFO allocator. Its
backing buffer may itself live on the stack, in static storage, or inside a
larger arena.
