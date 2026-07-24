// A small owning doubly linked list.
//
// Each node points at both of its neighbours.  The list keeps pointers to
// both ends, so inserting or removing a known node is constant-time.  Finding
// a value is still linear because nodes are not indexed.

class CListNode
{
  CListNode *previous;
  CListNode *next;
  I64 value;
};

class CList
{
  CListNode *head;
  CListNode *tail;
  I64 count;
};

U0 ListInit(CList *list)
{
  list->head = NULL;
  list->tail = NULL;
  list->count = 0;
}

Bool ListIsEmpty(CList *list)
{
  return list->head == NULL;
}

CListNode *ListNodeNew(I64 value)
{
  CListNode *node = MAlloc(sizeof(CListNode));
  node->previous = NULL;
  node->next = NULL;
  node->value = value;
  return node;
}

// A NULL position means "insert at the front".
CListNode *ListInsertAfter(CList *list, CListNode *position, I64 value)
{
  CListNode *node = ListNodeNew(value);

  node->previous = position;
  if (position)
    node->next = position->next;
  else
    node->next = list->head;

  if (node->previous)
    node->previous->next = node;
  else
    list->head = node;

  if (node->next)
    node->next->previous = node;
  else
    list->tail = node;

  list->count++;
  return node;
}

// A NULL position means "insert at the back".
CListNode *ListInsertBefore(CList *list, CListNode *position, I64 value)
{
  CListNode *node = ListNodeNew(value);

  node->next = position;
  if (position)
    node->previous = position->previous;
  else
    node->previous = list->tail;

  if (node->next)
    node->next->previous = node;
  else
    list->tail = node;

  if (node->previous)
    node->previous->next = node;
  else
    list->head = node;

  list->count++;
  return node;
}

CListNode *ListPushFront(CList *list, I64 value)
{
  return ListInsertAfter(list, NULL, value);
}

CListNode *ListPushBack(CList *list, I64 value)
{
  return ListInsertBefore(list, NULL, value);
}

CListNode *ListFind(CList *list, I64 value)
{
  CListNode *node = list->head;

  while (node) {
    if (node->value == value)
      return node;
    node = node->next;
  }
  return NULL;
}

// Unlink a node without freeing it.  The node must belong to list.
CListNode *ListDetach(CList *list, CListNode *node)
{
  if (!node)
    return NULL;

  if (node->previous)
    node->previous->next = node->next;
  else
    list->head = node->next;

  if (node->next)
    node->next->previous = node->previous;
  else
    list->tail = node->previous;

  node->previous = NULL;
  node->next = NULL;
  list->count--;
  return node;
}

// Remove and free node, returning the following node for easy iteration.
CListNode *ListErase(CList *list, CListNode *node)
{
  CListNode *next;

  if (!node)
    return NULL;
  next = node->next;
  Free(ListDetach(list, node));
  return next;
}

Bool ListPopFront(CList *list, I64 *value)
{
  CListNode *node = list->head;

  if (!node)
    return FALSE;
  if (value)
    *value = node->value;
  ListErase(list, node);
  return TRUE;
}

Bool ListPopBack(CList *list, I64 *value)
{
  CListNode *node = list->tail;

  if (!node)
    return FALSE;
  if (value)
    *value = node->value;
  ListErase(list, node);
  return TRUE;
}

U0 ListClear(CList *list)
{
  CListNode *node = list->head;
  CListNode *next;

  while (node) {
    next = node->next;
    Free(node);
    node = next;
  }
  ListInit(list);
}

// Check the links and bookkeeping from both directions.
Bool ListIsValid(CList *list)
{
  CListNode *node;
  CListNode *previous = NULL;
  CListNode *next = NULL;
  I64 forward_count = 0;
  I64 backward_count = 0;

  if (!list->head)
    return !list->tail && list->count == 0;
  if (!list->tail || list->head->previous || list->tail->next)
    return FALSE;

  node = list->head;
  while (node) {
    if (node->previous != previous)
      return FALSE;
    previous = node;
    node = node->next;
    forward_count++;
  }
  if (previous != list->tail || forward_count != list->count)
    return FALSE;

  node = list->tail;
  while (node) {
    if (node->next != next)
      return FALSE;
    next = node;
    node = node->previous;
    backward_count++;
  }
  return next == list->head && backward_count == list->count;
}

U0 ListPrintForward(CList *list)
{
  CListNode *node = list->head;

  "forward:";
  while (node) {
    " %d", node->value;
    node = node->next;
  }
  "\n";
}

U0 ListPrintBackward(CList *list)
{
  CListNode *node = list->tail;

  "backward:";
  while (node) {
    " %d", node->value;
    node = node->previous;
  }
  "\n";
}
