#ifndef AHOLYC_LIB_HTK_CHOICE_HC
#define AHOLYC_LIB_HTK_CHOICE_HC

#include "htk.hc"

U0 HtkChoiceHit(HtkCtl *button)
{
  HtkCtl *window = HtkOwnerWindow(button);

  window->value = button->data;
  HtkWindowClose(window);
}

// Stack-local result lives in the dialog. Escape/close return -1.
I64 HtkChoiceFor(HtkCtl *owner, U8 *title, U8 **items, I64 count,
  I64 columns=1)
{
  HtkCtl *grid = HtkNew(HTK_GRID), *window, *button;
  I64 i, result;

  columns = MaxI64(1, MinI64(HTK_GRID_MAX, columns));
  for (i = 0; i < count && i / columns < HTK_GRID_MAX; i++) {
    button = HtkToolButtonNew(items[i]);
    button->col = i % columns;
    button->row = i / columns;
    button->data = i;
    button->changed = &HtkChoiceHit;
    HtkAdd(grid, button);
  }
  window = HtkDialogNew(title, grid);
  window->value = -1;
  HtkWindowSetControls(window, HTK_WINDOW_CLOSE);
  HtkSetFocus(grid->kids);
  HtkModalFor(window, owner);
  result = window->value;
  HtkDestroy(window);
  return result;
}

U0 HtkListChoiceAccept(HtkCtl *c)
{
  HtkCtl *list = c, *window = HtkOwnerWindow(c);

  if (c->kind != HTK_TREE) list = c->user;
  if (list->link) { window->value = list->link->data; HtkWindowClose(window); }
}

// Scrollable alternative for long lists. Selecting a row is reversible;
// Enter or the Apply button accepts, Escape cancels.
I64 HtkListChoiceFor(HtkCtl *owner, U8 *title, U8 **items, I64 count, I64 selected=0)
{
  HtkCtl *box = HtkNew(HTK_BOX), *list = HtkTreeNew, *node, *button, *window;
  I64 i, result;

  box->vertical = TRUE;
  list->expand = TRUE;
  list->min_w = 54; list->min_h = 12;
  list->submit = &HtkListChoiceAccept;
  for (i = 0; i < count; i++) {
    node = HtkTreeAdd(list, NULL, items[i]);
    node->data = i;
    if (i == selected) list->link = node;
  }
  HtkAdd(box, list);
  button = HtkToolButtonNew("Apply");
  button->user = list; button->changed = &HtkListChoiceAccept;
  HtkAdd(box, button);
  window = HtkDialogNew(title, box);
  window->value = -1;
  HtkWindowSetControls(window, HTK_WINDOW_CLOSE);
  HtkSetFocus(list);
  HtkModalFor(window, owner);
  result = window->value;
  HtkDestroy(window);
  return result;
}

// Returns owned UTF-8 text, or NULL. The document accepts arbitrary emoji too.
U8 *HtkEmojiPick(HtkCtl *owner)
{
  U8 *items[48] = {"😀", "😃", "😄", "😁", "😆", "😅", "😂", "🙂",
    "🙃", "😉", "😊", "😍", "🤔", "😎", "😭", "😴",
    "👍", "👎", "👏", "🙌", "🙏", "💪", "👋", "🤝",
    "🔥", "✨", "💡", "🎉", "🎯", "🚀", "✅", "❌",
    "🐱", "🐶", "🐧", "🐝", "🌱", "🌳", "🌻", "🍀",
    "🍎", "🍕", "☕", "🌍", "🏠", "📁", "📝", "🔗"};
  I64 at = HtkChoiceFor(owner, "Emoji", items, 48, 8);

  if (at < 0) return NULL;
  return StrNew(items[at]);
}

#endif
