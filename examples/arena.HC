// This is deliberately a learning example, not a fast or hardened allocator:
// every managed allocation has a header and ArenaFree performs a linear scan.

#include "../lib/data/arena.HC"

// Example: all three live values are released by one ArenaFreeAll call.
CAllocationManager arena;
ArenaInit(&arena);

U8 *name = ArenaStrDup("Temple", &arena);
I64 *values = ArenaCAlloc(4 * sizeof(I64), &arena);
values[0] = 10;
values[1] = 20;
U8 *message = ArenaSPrint(&arena, "%s: %d + %d = %d",
  name, values[0], values[1], values[0] + values[1]);

"%s\n", message;
"before free-all: %d allocations, %d payload bytes\n",
  arena.count, arena.bytes;

// Individual managed allocations can also be removed early.
ArenaFree(values, &arena);
"after one free: %d allocations\n", arena.count;

ArenaFreeAll(&arena);
"after free-all: %d allocations, %d payload bytes\n",
  arena.count, arena.bytes;

// Omitting the manager gives an ordinary allocation requiring ArenaFree.
U8 *plain = ArenaStrDup("ordinary heap allocation");
"%s\n", plain;
ArenaFree(plain);
