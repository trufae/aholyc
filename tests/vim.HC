#define VIM_TEST
#define HTK_NODESK
#include "../examples/vim.hc"

U0 Check(Bool ok, U8 *name)
{
  if (!ok) { "FAIL vim: %s\n", name; Exit(1); }
}

Bool Equal(CEdit *edit, U8 *text)
{
  return StrsLen(&edit->text) == StrLen(text) && !MemCmp(edit->text.a, text, StrLen(text));
}

U0 Key(I64 key, I64 mods=0)
{
  CTermEvent e;

  e.type = TERM_EVENT_KEY; e.key = key; e.mods = mods;
  HtkKey(&e);
}

I64 PaneCount(CVimApp *app)
{
  CVimPane *pane = app->panes;
  I64 count = 0;

  while (pane) { count++; pane = pane->next; }
  return count;
}

U0 Command(CVimApp *app, U8 *text)
{
  Key(':');
  Check(app->prompt == ':' && htk_focus == app->command && !app->commandbar->hidden,
    "colon opens focused command line");
  HtkSetText(app->command, text); app->command->cursor = StrLen(text);
  Key(TERM_KEY_ENTER);
  Check(!app->prompt && app->commandbar->hidden, "Enter closes command line");
}

U0 TestSplits()
{
  CVimApp *app = VimNew;
  CVimPane *first = app->active, *second, *third;
  CVimBuffer *buffer = first->buffer;
  CHtkMarkdown *view;
  CEdit *edit = &buffer->edit;
  I64 saved, anchor;

  StrBufPutS(&edit->text, "one\né two\nthree\n");
  edit->cursor = 4; VimPaneChanged(first->ctl);
  Check(first->ctl->vim_mode && first->ctl->data(CHtkMarkdown *)->mode == HTK_MD_SOURCE,
    "example starts in shared HTK Vim source mode");
  HtkWindowLayout(app->window);
  Check(first->ctl->data(CHtkMarkdown *)->hide_status && app->status->h == 1 &&
    first->ctl->y + first->ctl->h == app->status->y &&
    app->status->y == app->window->y + app->window->h - 2,
    "editor uses entire pane height above one shared status line");
  Command(app, "split"); second = app->active;
  HtkWindowLayout(app->window);
  Check(PaneCount(app) == 2 && second->buffer == buffer && edit->cursor == 4,
    "split shares buffer and starts at existing cursor");
  Check(first->ctl->parent->kind == HTK_SPLIT && first->ctl->parent->vertical &&
    first->ctl->h > 0 && second->ctl->h > 0 && first->ctl->y < second->ctl->y,
    "horizontal split lays out above/below");
  edit->cursor = 0; VimPaneChanged(second->ctl);
  Key('i'); Key('Z'); Key(TERM_KEY_ESCAPE);
  Check(Equal(edit, "Zone\né two\nthree\n") && first->cursor == 5,
    "shared insertion updates other pane's UTF-8 caret");
  Key('w', TERM_MOD_CTRL); Key('w');
  Check(app->active == first && edit->cursor == 5, "Ctrl-W w switches independent cursor");
  Key('u');
  Check(Equal(edit, "one\né two\nthree\n") && second->cursor == 0,
    "undo is shared and remaps inactive cursor");
  Key('r', TERM_MOD_CTRL);
  Check(Equal(edit, "Zone\né two\nthree\n"), "redo works through shared handler");
  edit->cursor = 5; edit->anchor = 7; VimPaneChanged(first->ctl);
  saved = edit->cursor; anchor = edit->anchor;
  HtkClipAll; HtkDrawCtl(second->ctl);
  Check(edit->cursor == saved && edit->anchor == anchor, "inactive drawing preserves model cursor and selection");
  Key('w', TERM_MOD_CTRL); Key('v'); third = app->active;
  HtkWindowLayout(app->window);
  Check(PaneCount(app) == 3 && !third->ctl->parent->vertical && third->ctl->x > first->ctl->x,
    "Ctrl-W v makes nested left/right split");
  Key('w', TERM_MOD_CTRL); Key('h');
  Check(app->active == first, "Ctrl-W h moves geometrically to left pane");
  Key('w', TERM_MOD_CTRL); Key('l');
  Check(app->active == third, "Ctrl-W l moves geometrically to right pane");
  Key('w', TERM_MOD_CTRL); Key('w', TERM_MOD_CTRL);
  Check(app->active != third, "repeated Ctrl-W cycles panes");
  VimFocus(third); Command(app, "q");
  Check(PaneCount(app) == 2 && first->ctl->parent->kind == HTK_SPLIT,
    "closing nested split collapses its container");
  Command(app, "only");
  Check(PaneCount(app) == 1 && app->workspace->kids == app->active->ctl,
    "only collapses split tree and retains shared dirty buffer");
  Check(!VimCommand(app, "q") && !app->window->closed, "last dirty pane refuses ordinary quit");
  Check(VimCommand(app, "qa!") && app->window->closed, "forced quit closes window");
  VimFree(app);
}

U0 TestSource()
{
  CVimApp *app = VimNew;
  CEdit *edit = &app->active->buffer->edit;
  CHtkMarkdown *view = app->active->ctl->data;
  I64 cursor, cells, i;

  StrBufPutS(&edit->text, "|  |  |\n| --- | --- |\n|  |  |\n");
  edit->cursor = 3; VimPaneChanged(app->active->ctl);
  Key('i'); Key(TERM_KEY_TAB); Key(TERM_KEY_ESCAPE);
  Check(edit->text.a[3] == '\t' && StrsLen(&edit->text) == 31,
    "Tab inserts source tab inside table-shaped text");
  Key('u'); Check(StrsLen(&edit->text) == 30, "source Tab has shared undo");
  Command(app, "set number wrap");
  Check(view->line_numbers && !view->no_wrap, "set supports multiple view options");
  Check(!VimCommand(app, "set nonumber garbage") && view->line_numbers,
    "invalid option list has no partial effects");
  Command(app, "set nonumber nowrap readonly");
  Check(!view->line_numbers && view->no_wrap && edit->readonly && view->mode == HTK_MD_SOURCE_READ,
    "readonly changes model and renderer mode");
  cursor = edit->cursor; Key('x'); Key('J');
  Check(StrsLen(&edit->text) == 30 && cursor == edit->cursor, "readonly rejects source edits");
  Command(app, "set noreadonly");
  Key('/'); Check(app->prompt == '/' && !StrCmp(app->prompt_label->text, "/"), "search prompt marker");
  HtkSetText(app->command, "---"); Key(TERM_KEY_ENTER);
  Check(edit->cursor == 10 && edit->anchor == -1, "forward literal search");
  Key('n'); Check(edit->cursor == 16, "n repeats forward search");
  Key('N'); Check(edit->cursor == 10, "N reverses search");
  Key('?'); HtkSetText(app->command, "---"); Key(TERM_KEY_ENTER);
  Check(edit->cursor == 16, "backward search wraps to last match");
  Key('n'); Check(edit->cursor == 10, "n retains backward direction");
  Command(app, "3"); Check(edit->cursor == 22, "numeric command goes to source line");
  Key(':'); Key(TERM_KEY_TAB);
  Check(htk_focus == app->command && app->prompt, "Tab keeps command line focus");
  HtkWindowLayout(app->window);
  Check(app->commandbar->h == 1 && app->commandbar->y == app->window->y + app->window->h - 2 &&
    app->active->ctl->y + app->active->ctl->h == app->commandbar->y,
    "command prompt occupies same single status row");
  Key(TERM_KEY_ESCAPE);
  Check(!app->prompt && htk_focus == app->active->ctl, "Esc cancels command line");
  Command(app, "set novim"); Check(!app->active->ctl->vim_mode, "generic Vim toggle is reusable");
  VimPrompt(app); HtkSetText(app->command, "set vim"); Key(TERM_KEY_ENTER);
  Check(app->active->ctl->vim_mode, "command line re-enables Vim mode");
  // Long source lines scroll horizontally without losing UTF-8 positions.
  edit->cursor = 0; edit->anchor = -1;
  StrBufClear(&edit->text);
  for (i = 0; i < 100; i++) StrBufPutS(&edit->text, "é");
  edit->cursor = 198; VimPaneChanged(app->active->ctl);
  HtkWindowLayout(app->window); HtkMdRender(view);
  Check(view->rows == 1 && view->columns == 100, "nowrap keeps long source line intact");
  view->no_wrap = FALSE; HtkMdRender(view); cells = view->viewport;
  Check(view->rows > 1 && view->columns <= cells, "wrap uses pane width");
  StrBufClear(&edit->text); StrBufPutS(&edit->text, "- [ ] task\n");
  edit->cursor = 3; edit->anchor = -1; edit->readonly = TRUE;
  view->mode = HTK_MD_SOURCE_READ; Key(' ');
  Check(Equal(edit, "- [ ] task\n") && edit->readonly,
    "Vim source-file readonly mode does not permit Markdown task mutations");
  VimFree(app);
}

U0 TestFiles()
{
  U8 *one = "tests/out/vim-one.txt", *two = "tests/out/vim two.txt", *missing = "tests/out/vim-new.txt";
  U8 *text, raw[5] = {'a', 0, 'b', '\n', 'z'};
  CVimApp *app;
  CVimBuffer *buffer;
  CVimPane *first;
  CEdit *edit;
  I64 size;

  remove(missing);
  Check(FileWrite(one, raw, sizeof(raw)) && FileWrite(two, "second"), "prepare binary-safe fixtures");
  app = VimNew(one); edit = &app->active->buffer->edit; first = app->active;
  Check(StrsLen(&edit->text) == sizeof(raw) && !MemCmp(edit->text.a, raw, sizeof(raw)), "open preserves embedded NUL");
  Key('A'); Key('!'); Key(TERM_KEY_ESCAPE);
  Check(VimModified(first->buffer), "typing marks buffer modified");
  Check(!VimCommand(app, "e tests/out/vim two.txt"), "edit protects last view's unsaved changes");
  Check(!VimCommand(app, "o tests/out/vim two.txt") && app->active == first &&
    VimModified(first->buffer) && PaneCount(app) == 1, "open alias protects unsaved text and preserves the pane");
  Command(app, "vsplit tests/out/vim two.txt");
  Check(PaneCount(app) == 2 && app->active->buffer != first->buffer,
    "vsplit with filename opens independent buffer");
  Key('A'); Key('!'); Key(TERM_KEY_ESCAPE);
  Check(!VimCommand(app, "only") && PaneCount(app) == 2, "only protects another dirty buffer");
  Check(!VimCommand(app, "w tests/out/vim-one.txt"), "write rejects destination owned by another buffer");
  Check(!VimCommand(app, "wq tests/out/no-dir/file") && PaneCount(app) == 2 && !app->window->closed,
    "failed wq preserves pane and dirty content");
  Check(VimCommand(app, "w"), "write active buffer");
  text = FileRead(two, &size); Check(size == 7 && !MemCmp(text, "second!", size), "saved expected contents"); Free(text);
  VimFocus(first); Check(VimCommand(app, "w"), "write original binary buffer");
  text = FileRead(one, &size); Check(size == 6 && text[1] == 0 && text[3] == '!', "write preserves binary-safe length"); Free(text);
  Check(VimCommand(app, "only") && PaneCount(app) == 1, "only closes clean other buffer");
  Check(!VimCommand(app, "w tests/out/vim two.txt"), "closed cached buffer still protects destination");
  Key('x'); Check(VimCommand(app, "e!") && !VimModified(first->buffer), "forced reload discards changes");
  Command(app, "o \"tests/out/vim two.txt\"");
  Check(app->active == first && PaneCount(app) == 1 && !StrCmp(first->buffer->path.a, two) &&
    Equal(&first->buffer->edit, "second!"), "colon o opens a quoted filename with spaces in the current pane");
  Key('x');
  Check(!VimCommand(app, "o") && Equal(&first->buffer->edit, "econd!") && VimModified(first->buffer),
    "colon o without a filename protects an unsaved reload");
  Command(app, "o!");
  Check(Equal(&first->buffer->edit, "second!") && !VimModified(first->buffer),
    "colon o bang reloads the current file");
  Command(app, "open tests/out/vim-one.txt");
  Check(!StrCmp(first->buffer->path.a, one) && StrsLen(&first->buffer->edit.text) == 6,
    "long open command reuses the existing named buffer");
  Check(VimCommand(app, "e tests/out/vim-new.txt"), "edit can name a new file");
  buffer = app->active->buffer;
  Check(!StrsLen(&buffer->edit.text) && !StrCmp(buffer->path.a, missing), "new named buffer is empty");
  Key('i'); Key('é'); Key(TERM_KEY_ESCAPE);
  Check(VimCommand(app, "set readonly") && !VimCommand(app, "w") && VimModified(buffer),
    "readonly prevents write and preserves dirty state");
  Check(VimCommand(app, "w!") && !VimModified(buffer), "explicit forced write saves readonly buffer");
  Check(VimCommand(app, "set noreadonly") && VimCommand(app, "bn"), "buffer cycling reuses cached buffers");
  Check(app->active->buffer != buffer, "next buffer changes active model");
  Check(VimCommand(app, "b 3") && app->active->buffer == buffer, "numeric buffer selection");
  Check(!VimCommand(app, "b 99"), "unknown buffer reports failure");
  Check(VimCommand(app, "qa") && app->window->closed, "clean quit closes all panes");
  VimFree(app);
  remove(one); remove(two); remove(missing);
}

U0 TestVisual()
{
  CVimApp *app = VimNew;
  CVimPane *first = app->active, *second;
  CEdit *edit = &first->buffer->edit;
  CHtkMarkdown *view = first->ctl->data;
  HtkCtl *menu;
  I64 at;

  StrBufPutS(&edit->text, "one\né😀 two\nlast"); edit->cursor = 6;
  Key('V'); HtkWindowLayout(app->window); HtkClipAll; HtkMdDraw(first->ctl);
  Check(first->ctl->vim_visual == 2 && edit->anchor == 4 && edit->cursor == 15 &&
    view->caret_y == 1 && view->caret_x == 1,
    "Visual line caret stays on selected character instead of next line");
  at = (first->ctl->y + view->inset + 1) * TermWidth + first->ctl->x + view->gutter;
  Check(TermCellBg(term_back[at]) == HTK_C_SEL_BG &&
    MemMem(app->status->text, StrLen(app->status->text), "V-LINE | 2:2", 12),
    "Visual line paints selection and reports logical caret in single status row");
  Check(VimCommand(app, "vsplit"), "split while keeping original pane's Visual selection");
  second = app->active;
  edit->cursor = 0; edit->anchor = -1; Key('i'); Key('Z'); Key(TERM_KEY_ESCAPE);
  Check(first->ctl->vim_start == 7 && first->ctl->vim_head == 7 && first->cursor == 16,
    "shared insertion remaps inactive Visual marks and selection");
  VimFocus(first); Key('j');
  Check(first->ctl->vim_head == 17 && edit->anchor == 5 && edit->cursor == 20,
    "returning to Visual pane extends remapped whole-line selection");
  Key('y'); Check(!first->ctl->vim_visual && edit->cursor == 5, "Visual pane yank returns to Normal");
  Key('V'); Key('c'); Key('X'); Key(TERM_KEY_ESCAPE); Key('u');
  Check(Equal(edit, "Zone\né😀 two\nlast"), "Visual change and typing share undo in split buffer");
  Key('V'); VimCommand(app, "set novim");
  Check(!first->ctl->vim_visual && edit->anchor == -1,
    "per-pane setting cancels Visual selection through Markdown mode callback");
  VimCommand(app, "set vim"); Key('v'); VimCopy(app);
  Check(!first->ctl->vim_visual && edit->anchor == -1, "Ctrl-C callback cancels Visual mode after copying");
  menu = app->window->kids;
  while (menu && menu->kind == HTK_MENU) {
    Check(HtkKidAt(menu, 2)->kind == HTK_SEP || HtkKidAt(menu, 3)->kind == HTK_SEP,
      "Vim menus group related commands with separators");
    menu = menu->sib;
  }
  VimFree(app);
}

U0 TestCursorShape()
{
  CVimApp *app = VimNew;
  CEdit *edit = &app->active->buffer->edit;

  StrBufPutS(&edit->text, "abc"); HtkRedraw;
  Check(term_cursor_shape == TERM_CURSOR_BLOCK, "Vim window starts with block cursor");
  Key('i'); HtkRedraw;
  Check(term_cursor_shape == TERM_CURSOR_BAR && edit->cursor == 0,
    "Vim Insert redraw changes shape even without a text edit");
  Key(TERM_KEY_ESCAPE); HtkRedraw;
  Check(term_cursor_shape == TERM_CURSOR_BLOCK, "Vim Escape restores block cursor");
  Key(':'); HtkRedraw;
  Check(term_cursor_shape == TERM_CURSOR_BAR, "Vim command prompt uses bar cursor");
  Key(TERM_KEY_ESCAPE); HtkRedraw;
  Check(term_cursor_shape == TERM_CURSOR_BLOCK, "leaving command prompt restores active pane cursor");
  VimFree(app);
}

U0 TestControlKeys()
{
  CVimApp *app = VimNew;
  CVimPane *pane;
  CEdit *edit = &app->active->buffer->edit;
  CHtkMarkdown *view;
  CStrBuf original;
  I64 i, step;

  for (i = 0; i < 40; i++) StrBufPutS(&edit->text, "é😀x\n");
  StrBufInit(&original); StrBufPutStrs(&original, &edit->text);
  Command(app, "split"); pane = app->active;
  HtkWindowLayout(app->window); HtkRedraw;
  view = pane->ctl->data; step = MaxI64(1, view->height - 2);
  Check(view->height == pane->ctl->h && view->height < app->window->h / 2,
    "Vim split reserves no second status line");
  Key('l'); Key('f', TERM_MOD_CTRL); HtkRedraw;
  Check(edit->cursor == 2 + step * 8 && pane->ctl->top == step && !edit->undo,
    "Vim Ctrl-F pages using the split pane's height");
  Key('b', TERM_MOD_CTRL); HtkRedraw;
  Check(edit->cursor == 2 && pane->ctl->top == 0, "Vim Ctrl-B returns viewport and caret");
  Key('v'); Key('f', TERM_MOD_CTRL);
  Check(pane->ctl->vim_visual == 1 && pane->ctl->vim_start == 2 &&
    pane->ctl->vim_head == 2 + step * 8, "Vim Visual page motion keeps selection active");
  Key(TERM_KEY_ESCAPE); Key('i'); Key('b', TERM_MOD_CTRL);
  Check(pane->ctl->vim_insert && edit->cursor == 2, "Vim Insert mode also pages");
  Key('a', TERM_MOD_CTRL); Key('e', TERM_MOD_CTRL); Key('w', TERM_MOD_CTRL);
  Check(edit->cursor == 6 && edit->text.a[6] == '\n' && !app->prefix && PaneCount(app) == 2,
    "Insert Ctrl-W deletes a word without starting pane commands");
  Key('y', TERM_MOD_CTRL);
  Check(Equal(edit, original.a),
    "Vim Insert Ctrl-Y restores cut text");
  Key('t', TERM_MOD_CTRL); Key(TERM_KEY_ESCAPE); Key('u');
  Check(edit->text.a[6] == 'x', "Vim transpose is independently undoable");
  Key('w', TERM_MOD_CTRL); Key('w');
  Check(app->active != pane, "Normal Ctrl-W still switches panes");
  StrBufFini(&original); VimFree(app);
}

term_width = 80; term_height = 24;
TermBuffersAlloc; HtkThemeDefault;
TestSplits;
TestSource;
TestFiles;
TestVisual;
TestCursorShape;
TestControlKeys;
Free(term_back); Free(term_front);
"ok vim\n";
