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
  CArenaBlock *blocks;
  I64 count;
  I64 bytes;
};

U0 ArenaInit(CAllocationManager *manager)
{
  manager->blocks = NULL;
  manager->count = 0;
  manager->bytes = 0;
}

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
