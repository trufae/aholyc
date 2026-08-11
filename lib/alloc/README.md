# Allocators

`alloc.hc` defines the small allocator contract shared by libraries that need
dynamic storage without imposing an allocation policy.

```c
class CAllocator
{
  I64 realloc_fn;
  I64 free_fn;
  U8 *context;
};
```

`realloc_fn` is the address of
`U8 *Realloc(U8 *context, U8 *memory, I64 old_size, I64 new_size,
I64 alignment)`. `free_fn` is the address of
`U0 Free(U8 *context, U8 *memory, I64 size, I64 alignment)`.

Allocation is the subset `realloc(context, NULL, 0, size, alignment)`.
`old_size` lets arenas resize without storing a header for every allocation.
The callback preserves the old allocation when it cannot resize. `free` may
be `NULL` for a monotonic arena.

Library APIs accept `CAllocator *`; `NULL` selects `MAlloc`/`Free` through a
portable allocate-copy-free implementation. The default supports alignments
up to `ALLOC_DEFAULT_ALIGNMENT` (16). Custom allocators may support larger
alignments.
