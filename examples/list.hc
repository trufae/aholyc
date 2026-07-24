#include "../lib/data/list.HC"

// Example usage.
CList numbers;
CListNode *twenty;
CListNode *found;
I64 popped;

ListInit(&numbers);
ListPushBack(&numbers, 10);
twenty = ListPushBack(&numbers, 20);
ListPushFront(&numbers, 5);
ListInsertBefore(&numbers, twenty, 15);
ListInsertAfter(&numbers, twenty, 25);

ListPrintForward(&numbers);
ListPrintBackward(&numbers);
"count=%d valid=%d\n", numbers.count, ListIsValid(&numbers);

found = ListFind(&numbers, 15);
if (found)
  ListErase(&numbers, found);

if (ListPopFront(&numbers, &popped))
  "popped front: %d\n", popped;
if (ListPopBack(&numbers, &popped))
  "popped back: %d\n", popped;

ListPrintForward(&numbers);
"count=%d valid=%d\n", numbers.count, ListIsValid(&numbers);

ListClear(&numbers);
"after clear: count=%d empty=%d valid=%d\n",
  numbers.count, ListIsEmpty(&numbers), ListIsValid(&numbers);
