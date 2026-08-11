#ifndef AHOLYC_LIB_ALLOC_ARENA_HC
#define AHOLYC_LIB_ALLOC_ARENA_HC

#include "alloc.hc"

// A tiny allocation manager inspired by the linked allocations in src/util.c.
//
// This is deliberately a learning example, not a fast or hardened allocator:
// every managed allocation has a header and ArenaFree performs a linear scan.

class CArenaBlock
{
  CArenaBlock *next;
  I64 size;
};

class CAllocationManager
{
  CAllocator allocator;
  CArenaBlock *blocks;
  I64 count;
  I64 bytes;
};

// With no manager these helpers behave like the normal heap routines.
U8 *ArenaAlloc(I64 size, CAllocationManager *manager=NULL)
{
  CArenaBlock *block;

  if (!manager)
    return MAlloc(size);
  block = MAlloc(sizeof(CArenaBlock) + size);
  block->next = manager->blocks;
  block->size = size;
  manager->blocks = block;
  manager->count++;
  manager->bytes += size;
  return block + 1;
}

U8 *ArenaCAlloc(I64 size, CAllocationManager *manager=NULL)
{
  U8 *p = ArenaAlloc(size, manager);
  MemSet(p, 0, size);
  return p;
}

U8 *ArenaMemDup(U8 *src, I64 size, CAllocationManager *manager=NULL)
{
  return MemCpy(ArenaAlloc(size, manager), src, size);
}

U8 *ArenaStrDup(U8 *s, CAllocationManager *manager=NULL)
{
  return ArenaMemDup(s, StrLen(s) + 1, manager);
}

// HolyC variadics expose argc/argv, so StrPrintJoin can do the formatting.
U8 *ArenaSPrint(CAllocationManager *manager=NULL, U8 *fmt, ...)
{
  U8 *temporary = StrPrintJoin(NULL, fmt, argc, argv);
  U8 *result;

  if (!manager)
    return temporary;
  result = ArenaStrDup(temporary, manager);
  Free(temporary);
  return result;
}

// Returns FALSE when p is not owned by manager.
Bool ArenaFree(U8 *p, CAllocationManager *manager=NULL)
{
  CArenaBlock *block;
  CArenaBlock *previous = NULL;

  if (!p)
    return TRUE;
  if (!manager) {
    Free(p);
    return TRUE;
  }
  block = manager->blocks;
  while (block && block + 1 != p) {
    previous = block;
    block = block->next;
  }
  if (!block)
    return FALSE;
  if (previous)
    previous->next = block->next;
  else
    manager->blocks = block->next;
  manager->count--;
  manager->bytes -= block->size;
  Free(block);
  return TRUE;
}

// CAllocator adapter. The descriptor's size arguments are checked against
// the arena header so a bad resize cannot copy beyond the owned allocation.
U8 *ArenaAllocatorRealloc(U8 *context, U8 *memory, I64 old_size,
  I64 new_size, I64 alignment)
{
  CAllocationManager *manager = context(CAllocationManager *);
  CArenaBlock *block;
  U8 *result;
  I64 copy_size;

  if (!manager || old_size < 0 || new_size < 0 ||
    !AllocAlignmentValid(alignment) || alignment > ALLOC_DEFAULT_ALIGNMENT)
    return NULL;
  if (!memory) {
    if (old_size || !new_size)
      return NULL;
    return ArenaAlloc(new_size, manager);
  }
  if (memory(U64) & (alignment - 1))
    return NULL;
  block = manager->blocks;
  while (block && block + 1 != memory)
    block = block->next;
  if (!block || block->size != old_size)
    return NULL;
  if (!new_size) {
    ArenaFree(memory, manager);
    return NULL;
  }
  if (new_size == old_size)
    return memory;
  result = ArenaAlloc(new_size, manager);
  copy_size = old_size;
  if (copy_size > new_size)
    copy_size = new_size;
  if (copy_size)
    MemCpy(result, memory, copy_size);
  ArenaFree(memory, manager);
  return result;
}

U0 ArenaAllocatorFree(U8 *context, U8 *memory, I64 size, I64 alignment)
{
  CAllocationManager *manager = context(CAllocationManager *);
  CArenaBlock *block;

  if (!manager || !memory || size < 0 ||
    !AllocAlignmentValid(alignment) || alignment > ALLOC_DEFAULT_ALIGNMENT ||
    (memory(U64) & (alignment - 1)))
    return;
  block = manager->blocks;
  while (block && block + 1 != memory)
    block = block->next;
  if (block && block->size == size)
    ArenaFree(memory, manager);
}

CAllocator *ArenaInit(CAllocationManager *manager)
{
  if (!manager)
    return NULL;
  MemSet(manager, 0, sizeof(CAllocationManager));
  manager->allocator.realloc_fn = &ArenaAllocatorRealloc;
  manager->allocator.free_fn = &ArenaAllocatorFree;
  manager->allocator.context = manager(U8 *);
  return &manager->allocator;
}

U0 ArenaFreeAll(CAllocationManager *manager)
{
  CArenaBlock *block = manager->blocks;
  CArenaBlock *next;

  while (block) {
    next = block->next;
    Free(block);
    block = next;
  }
  ArenaInit(manager);
}

#endif
