#include "../lib/data/ht.hc"

CHashTable scores;
CHashEntry *entry;
I64 score;
I64 index;

HtInit(&scores);

HtPut(&scores, "Ada", 98);
HtPut(&scores, "Linus", 95);
HtPut(&scores, "Terry", 100);

// Putting an existing key replaces its value without increasing the count.
HtPut(&scores, "Linus", 99);

if (HtGet(&scores, "Linus", &score))
  "Linus: %d\n", score;

HtDelete(&scores, "Ada");

"%d scores:\n", scores.count;
index = HtNext(&scores, 0, &entry);
while (index >= 0) {
  "  %s: %d\n", entry->key, entry->value;
  index = HtNext(&scores, index + 1, &entry);
}

// Keys are borrowed, so only the table's slot array is released.
HtFini(&scores);
