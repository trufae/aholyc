#define WORD_TEST
#define HTK_NODESK
#include "../examples/word.hc"

U0 Check(Bool ok, U8 *name)
{
  if (!ok) { "FAIL word: %s\n", name; Exit(1); }
}

Bool Equal(CStrs *text, U8 *expected)
{
  return StrsLen(text) == StrLen(expected) && !MemCmp(text->a, expected, StrsLen(text));
}

U0 Key(CWordDoc *doc, I64 key, I64 mods=0)
{
  CTermEvent event;

  event.key = key;
  event.mods = mods;
  HtkMdKey(doc->view, &event);
}

U0 WindowKey(I64 key, I64 mods=0)
{
  CTermEvent event;

  event.type = TERM_EVENT_KEY; event.key = key; event.mods = mods;
  HtkKey(&event);
}

U0 TestEdit()
{
  CEdit edit;
  CStrs slice, prefix, suffix;
  U8 raw[4] = {'a', 0, 'b', 'c'};

  EditInit(&edit);
  StrsInitN(&slice, raw, sizeof(raw));
  Check(EditInsert(&edit, &slice), "insert unterminated input");
  Check(StrsLen(&edit.text) == 4 && !MemCmp(edit.text.a, raw, 4), "NUL does not truncate");
  HtkClipboardSetStrs(&slice);
  HtkClipboardGet(&slice);
  Check(StrsLen(&slice) == 4 && !MemCmp(slice.a, raw, 4), "clipboard length");
  edit.anchor = 1; edit.cursor = 3;
  StrsInitS(&slice, "é😀");
  Check(EditInsert(&edit, &slice), "replace selection with UTF-8");
  Check(Equal(&edit.text, "aé😀c"), "UTF-8 source");
  Check(!EditReplace(&edit, 2, 3, &slice), "reject split rune");
  edit.anchor = 1; edit.cursor = 7;
  StrsInitS(&prefix, "**"); StrsInitS(&suffix, "**");
  Check(EditWrap(&edit, &prefix, &suffix), "wrap selection");
  Check(Equal(&edit.text, "a**é😀**c"), "bold selection");
  Check(EditWrap(&edit, &prefix, &suffix) && Equal(&edit.text, "aé😀c"), "toggle bold off");
  Check(EditUndo(&edit) && Equal(&edit.text, "a**é😀**c"), "undo wrap");
  Check(EditUndo(&edit, TRUE) && Equal(&edit.text, "aé😀c"), "redo wrap");
  edit.readonly = TRUE;
  Check(!EditInsert(&edit, &slice) && !EditUndo(&edit), "readonly model");
  edit.readonly = FALSE;
  EditFini(&edit);
  EditInit(&edit);
  StrsInitS(&slice, "h"); EditType(&edit, &slice);
  StrsInitS(&slice, "i"); EditType(&edit, &slice);
  Check(EditUndo(&edit) && StrsEmpty(&edit.text), "undo a typing group");
  Check(EditUndo(&edit, TRUE) && Equal(&edit.text, "hi"), "redo a typing group");
  edit.saved = edit.revision;
  StrsInitS(&slice, "!"); EditType(&edit, &slice);
  Check(EditUndo(&edit) && Equal(&edit.text, "hi") && edit.revision == edit.saved, "undo restores saved revision");
  StrsInitS(&slice, "?"); EditInsert(&edit, &slice);
  Check(!EditUndo(&edit, TRUE), "new edits discard redo branch");
  edit.anchor = 0; edit.cursor = StrsLen(&edit.text);
  StrsInitS(&slice, "first\nsecond"); EditInsert(&edit, &slice);
  edit.anchor = 0; edit.cursor = StrsLen(&edit.text);
  Check(MdEditWrap(&edit, &prefix, &suffix) && Equal(&edit.text, "**first**\n**second**"), "multiline formatting");
  Check(MdEditWrap(&edit, &prefix, &suffix) && Equal(&edit.text, "first\nsecond"), "toggle multiline formatting");
  edit.anchor = 0; edit.cursor = StrsLen(&edit.text);
  StrsInitS(&slice, "first\nsecond\n"); EditInsert(&edit, &slice);
  edit.anchor = 0; edit.cursor = StrsLen(&edit.text);
  MdEditWrap(&edit, &prefix, &suffix);
  Check(MdEditWrap(&edit, &prefix, &suffix) && Equal(&edit.text, "first\nsecond\n"), "toggle formatting with trailing newline");
  EditFini(&edit);
}

U0 TestMarkdown()
{
  CStrs input, label, target, cells[4];
  CStrBuf output;
  CMarkdown md;
  CMdExport export;
  U8 *after;
  U8 raw[5] = {'*', '*', 'x', '*', '*'};

  StrBufInit(&output);
  StrsInitN(&input, raw, sizeof(raw));
  MarkdownExport(&input, &output, MD_EXPORT_TEXT);
  Check(Equal(&output, "  x"), "bounded render");
  StrsInitS(&input, "[file](dir/a(b).md)");
  Check(MdLink(input.a, input.b, &label, &target, &after) &&
    Equal(&label, "file") && Equal(&target, "dir/a(b).md") && after == input.b, "balanced link");
  StrsInitS(&input, "[broken](");
  Check(!MdLink(input.a, input.b, &label, &target, &after), "truncated link");
  StrsInitS(&input, "| `a|b` | c\\|d | |");
  Check(MdTableSplitRow(&input, cells, 4) == 3 && Equal(&cells[0], "`a|b`") &&
    Equal(&cells[1], "c\\|d") && StrsEmpty(&cells[2]), "table escaped/code pipes and empty cell");
  StrsInitS(&input, "# Heading\n<span style=\"color:#123456;background-color:#abc\"><u>hi</u></span> [file](a.md)\n| A | B |\n| --- | --- |\n| x | y |\n");
  StrBufClear(&output);
  MarkdownExport(&input, &output, MD_EXPORT_HTML);
  Check(MdFind(output.a, output.b, "<h1 id=\"heading\">Heading</h1>") != NULL, "HTML heading");
  Check(MdFind(output.a, output.b, "color:#123456;") != NULL &&
    MdFind(output.a, output.b, "background-color:#AABBCC;") != NULL, "HTML colors");
  Check(MdFind(output.a, output.b, "<a href=\"a.md\">file</a>") != NULL, "HTML relative link");
  Check(MdFind(output.a, output.b, "<th>A</th>") != NULL &&
    MdFind(output.a, output.b, "<td>y</td>") != NULL, "HTML semantic table");
  StrBufClear(&output);
  MarkdownExport(&input, &output, MD_EXPORT_GEM);
  Check(MdFind(output.a, output.b, "=> a.md\n") != NULL, "Gemtext links");
  StrsInitS(&input, "[x](javascript:alert) <script>bad</script>");
  StrBufClear(&output);
  MarkdownExport(&input, &output, MD_EXPORT_HTML);
  Check(!MdFind(output.a, output.b, "href=\"javascript:") &&
    MdFind(output.a, output.b, "&lt;script&gt;") != NULL, "HTML safe subset");
  StrsInitS(&input, "| Wide column text | B |\n| --- | --- |\n| This is a very long cell | value |\n");
  export.out = &output; export.format = MD_EXPORT_TEXT;
  StrBufInit(&export.links);
  StrBufClear(&output);
  MarkdownInit(&md, &MdExportText, NULL, &export);
  md.width = 20; md.table_fit = TRUE;
  MarkdownRenderStrs(&md, &input);
  U8 *p = output.a;
  while (p < output.b) {
    p = MdNextLine(&output, p, &label);
    Check(MdWidth(&label) <= 20, "fitted table width");
  }
  CMdBlock block;
  StrsInitS(&input, "~~~~hc\n# not a heading\n```\nI64 answer = 42; // comment\n~~~~\n# Real\n");
  Check(MdCodeAt(&input, input.a, &block) && Equal(&block.language, "hc") &&
    Equal(&block.code, "# not a heading\n```\nI64 answer = 42; // comment\n"), "matching fence and bounded code");
  StrBufClear(&output);
  MarkdownExport(&input, &output, MD_EXPORT_HTML);
  Check(MdFind(output.a, output.b, "# not a heading\n```") != NULL, "export preserves nested fences");
  StrBufClear(&output);
  MarkdownExport(&input, &output, MD_EXPORT_TEXT);
  Check(StrsLen(&output) < 200, "text export does not pad code to wrap width");
  StrsInitS(&input, "intro\n# One\ntext\n## Child\nmore\n# Two\nend");
  MdSection(&input, 7, &label);
  Check(Equal(&label, "# One\ntext\n## Child\nmore\n"), "parent section includes children");
  MdSection(&input, 20, &label);
  Check(Equal(&label, "## Child\nmore\n"), "child section range");
  StrBufFini(&export.links);
  StrBufFini(&output);
}

U0 TestWindow()
{
  CWordApp app;
  CWordDoc *doc, *other;
  CStrs slice;
  CHtkMarkdown *view;
  CMdTable table;
  I64 a, b, size;
  U8 *bytes;

  term_width = 100; term_height = 30;
  TermBuffersAlloc;
  HtkThemeDefault;
  TermCell(2, 0, 0x1F600);
  TermCell(1, 0, 0x1F600);
  Check(TermCellChar(term_back[3]) == ' ', "overlapping wide glyph clears trailing cell");
  doc = WordNew(&app);
  view = doc->view->data;
  StrsInitS(&slice, "# Title\nHello **world** and [other](other.md).\n\n| A | B |\n| --- | --- |\n| one | two |\n");
  EditInsert(&doc->edit, &slice);
  WordRefresh(doc->view);
  HtkWindowLayout(doc->window);
  Check(doc->view->w > 40 && doc->view->h > 10, "document layout");
  HtkCtl *bar = HtkWindowContent(doc->window)->kids, *button = bar->kids;
  Check(bar->kind == HTK_TOOLBAR && bar->h == 1 && bar->y == doc->window->y + 2,
    "one toolbar row below the menubar");
  Check(HtkKidCount(bar) == 11 && doc->status->h == 1 &&
    doc->status->y == doc->window->y + doc->window->h - 2, "compact toolbar and docked statusbar");
  Check(doc->outline_button->parent == doc->status &&
    !StrCmp(doc->outline_button->text, "Outline") &&
    doc->outline_button->sib == doc->source &&
    doc->source->parent == doc->status && doc->editable->parent == doc->status &&
    doc->editable->x + doc->editable->w == doc->status->x + doc->status->w,
    "view modes dock at the statusbar bottom right");
  while (button) {
    Check(button->data != WORD_OUTLINE, "outline lives in the statusbar");
    Check(button->data != WORD_NEW && button->data != WORD_OPEN && button->data != WORD_SAVE,
      "file actions only in menus");
    button = button->sib;
  }
  HtkClipAll; HtkStr(0, 0, "☰]V", HTK_C_FG, HTK_C_BG);
  Check(TermCellChar(term_back[0]) == 0x2630 &&
    TermCellChar(term_back[1]) == TERM_CELL_CONT &&
    TermCellChar(term_back[2]) == ']' && TermCellChar(term_back[3]) == 'V',
    "wide trigram rendering preserves following characters");
  Check(Utf8CellWidth(0x2630) == 2 && Utf8CellWidth(0x2637) == 2 && Utf8CellWidth(0x2638) == 1,
    "trigram width range ends before the neighboring narrow symbols");
  doc->window->w = doc->window->min_w;
  HtkWindowLayout(doc->window);
  Check(doc->alignment[MD_ALIGN_JUSTIFY]->x + doc->alignment[MD_ALIGN_JUSTIFY]->w <= bar->x + bar->w && bar->h == 1,
    "toolbar fits the minimum window width");
  Check(doc->editable->x + doc->editable->w == doc->status->x + doc->status->w &&
    doc->stats->x + doc->stats->w < doc->outline_button->x,
    "status modes stay right aligned in a narrow window");
  doc->window->w = 100;
  HtkWindowLayout(doc->window);
  WordAction(doc, WORD_OUTLINE);
  Check(doc->outline->hidden && !doc->outline_button->value, "statusbar outline toggle hides the tree");
  WordAction(doc, WORD_OUTLINE);
  Check(!doc->outline->hidden && doc->outline_button->value, "statusbar outline toggle restores the tree");
  Check(HtkTreeCount(doc->outline) == 1, "heading outline");
  HtkMdRender(view);
  Check(view->rows > 6, "rendered table rows");
  a = MdFind(doc->edit.text.a, doc->edit.text.b, "world") - doc->edit.text.a;
  doc->edit.cursor = a;
  HtkMdRender(view);
  Check(HtkMdHit(view, view->caret_x, view->caret_y) == a, "rendered hit maps to source");
  doc->edit.anchor = a; doc->edit.cursor = a + 5;
  WordAction(doc, WORD_ITALIC);
  Check(MdFind(doc->edit.text.a, doc->edit.text.b, "***world***") != NULL, "format rendered selection");
  HtkMarkdownMode(doc->view, HTK_MD_READ);
  size = StrsLen(&doc->edit.text);
  Key(doc, 'x'); Key(doc, TERM_KEY_DELETE); Key(doc, 'z', TERM_MOD_CTRL);
  Check(StrsLen(&doc->edit.text) == size, "readonly keys do not mutate");
  WordAction(doc, WORD_SOURCE);
  Check(view->mode == HTK_MD_SOURCE_READ && doc->edit.readonly, "source toggle preserves readonly");
  Key(doc, 'x');
  Check(StrsLen(&doc->edit.text) == size, "source readonly prevents mutation");
  WordAction(doc, WORD_EDITABLE);
  Check(view->mode == HTK_MD_SOURCE && !doc->edit.readonly, "editable toggle preserves source");
  WordAction(doc, WORD_SOURCE);
  Check(view->mode == HTK_MD_EDIT, "all four modes");
  view->line_numbers = TRUE; view->ruler_top = TRUE; view->ruler_left = TRUE;
  view->layout = HTK_MD_PAGES; view->page_lines = 5;
  a = MdFind(doc->edit.text.a, doc->edit.text.b, "world") - doc->edit.text.a;
  doc->edit.cursor = a;
  HtkMdRender(view);
  Check(view->gutter == 9 && view->inset == 1 && view->page_number > 1, "guides and automatic pagination");
  Check(HtkMdHit(view, view->caret_x, view->caret_y) == a, "guides retain source mapping");
  HtkMarkdownMode(doc->view, HTK_MD_SOURCE);
  doc->edit.cursor = MdFind(doc->edit.text.a, doc->edit.text.b, "one") - doc->edit.text.a;
  Check(MdEditTable(&doc->edit, MD_TABLE_ADD_COL), "add column");
  Check(MdTableAt(&doc->edit.text, doc->edit.cursor, &table) && table.columns == 3, "column count");
  Check(MdEditTable(&doc->edit, MD_TABLE_ADD_ROW), "add row");
  Check(MdEditTable(&doc->edit, MD_TABLE_BORDER, 1), "change table border");
  Check(MdFind(doc->edit.text.a, doc->edit.text.b, "<!-- table-border: round -->") != NULL, "persist border hint");
  Check(EditUndo(&doc->edit), "undo table change");
  Check(FileReplace("tests/out/word-save.md", &doc->edit.text), "atomic Markdown save");
  bytes = FileRead("tests/out/word-save.md", &size);
  Check(bytes && size == StrsLen(&doc->edit.text) && !MemCmp(bytes, doc->edit.text.a, size), "save exact bytes");
  Free(bytes);
  other = WordNew(&app);
  Check(other && other->view != doc->view && !StrsLen(&other->edit.text), "independent document windows");
  WordAction(doc, WORD_VIM);
  Check(htk_vim_mode && other->view->vim_mode && doc->vim->value && other->vim->value,
    "Vim toggle updates all document editors");
  WordAction(doc, WORD_VIM);
  StrsInitS(&slice, "```hc\nI64 n = 42; // comment\n```\n# Section\nbody\n<!-- pagebreak -->\nnext");
  EditInsert(&other->edit, &slice);
  HtkWindowLayout(other->window);
  CHtkMarkdown *codeview = other->view->data;
  HtkMdHit(codeview, 0, 0);
  Check(codeview->code_hit_a == 6 && codeview->code_hit_b == 29, "code header hit range");
  other->view->mouse_x = 1; other->view->mouse_y = 0;
  other->view->mouse_button = TERM_MOUSE_LEFT;
  other->view->mouse_pressed = TRUE;
  HtkMdMouse(other->view);
  HtkClipboardGet(&slice);
  Check(Equal(&slice, "I64 n = 42; // comment\n"), "one click copies code without fence");
  HtkClipboardSetStrs(&slice); HtkClipboardGet(&slice);
  Check(Equal(&slice, "I64 n = 42; // comment\n"), "clipboard self assignment");
  codeview->layout = HTK_MD_SECTION; codeview->section_at = 34;
  HtkMdRender(codeview);
  Check(codeview->range_a == 33, "section viewport starts at heading");
  StrBufPutS(&doc->path, "folder/document.md");
  StrsInitS(&slice, "images/cat%20photo.png");
  bytes = WordResolve(doc, &slice);
  Check(!StrCmp(bytes, "folder/images/cat photo.png"), "relative image resolution");
  Free(bytes);
  doc->window->closing = NULL;
  doc->window->submit = NULL;
  HtkWindowClose(doc->window);
  WordDispose(doc, 0);
  other->window->closing = NULL;
  other->window->submit = NULL;
  HtkWindowClose(other->window);
  WordDispose(other, 0);
  Free(term_back); Free(term_front);
}

U0 TestTableEditing()
{
  CWordApp app;
  CWordDoc *doc = WordNew(&app);
  CHtkMarkdown *view = doc->view->data;
  CStrs text, cells[2], row;
  CMdTable table;
  I64 a, b, x, y;
  U8 *p;

  // Clicking just past a cell's last character must reach its end boundary.
  StrsInitS(&text, "| abc | é😀 |\n| --- | ---: |\n| xyz | 123 |\n");
  EditInsert(&doc->edit, &text);
  HtkWindowLayout(doc->window);
  a = MdFind(doc->edit.text.a, doc->edit.text.b, "abc") - doc->edit.text.a;
  doc->edit.cursor = a + 2;
  HtkMdRender(view); x = view->caret_x + 1; y = view->caret_y;
  Check(HtkMdHit(view, x, y) == a + 3, "cell trailing padding maps after final ASCII character");
  doc->edit.cursor = HtkMdHit(view, x, y); doc->edit.anchor = -1;
  Key(doc, TERM_KEY_BACKSPACE);
  Check(MdFind(doc->edit.text.a, doc->edit.text.b, "| ab |") != NULL, "delete final cell character");
  Key(doc, 'q');
  Check(MdFind(doc->edit.text.a, doc->edit.text.b, "| abq |") != NULL, "type at cell end");
  a = MdFind(doc->edit.text.a, doc->edit.text.b, "😀") - doc->edit.text.a;
  doc->edit.cursor = a;
  HtkMdRender(view); x = view->caret_x + 2; y = view->caret_y;
  Check(HtkMdHit(view, x, y) == a + 4, "right aligned cell end maps after a wide UTF-8 character");
  doc->edit.cursor = HtkMdHit(view, x, y); doc->edit.anchor = -1;
  Key(doc, TERM_KEY_BACKSPACE);
  Check(MdFind(doc->edit.text.a, doc->edit.text.b, "| é |") != NULL, "delete final UTF-8 cell character");
  EditFini(&doc->edit); EditInit(&doc->edit);
  StrsInitS(&text, "| abcdefghi | xyz |\n| --- | --- |\n|  |  |\n");
  EditInsert(&doc->edit, &text);
  view->column_width = 15;
  a = MdFind(doc->edit.text.a, doc->edit.text.b, "abcdefghi") - doc->edit.text.a;
  doc->edit.cursor = a + 2;
  HtkMdRender(view); x = view->caret_x + 1; y = view->caret_y;
  Check(HtkMdHit(view, x, y) == a + 3, "wrapped cell segment end preserves its source boundary");
  doc->edit.cursor = a + 8;
  HtkMdRender(view); x = view->caret_x + 1; y = view->caret_y;
  Check(HtkMdHit(view, x, y) == a + 9, "wrapped cell final padding maps to cell end");
  EditFini(&doc->edit); EditInit(&doc->edit);
  Check(MdEditTable(&doc->edit, MD_TABLE_INSERT), "insert empty table");
  Check(MdTableAt(&doc->edit.text, doc->edit.cursor, &table), "empty table is valid Markdown");
  p = MdNextLine(&table.text, table.text.a, &row);
  Check(MdTableSplitRow(&row, cells, 2) == 2 && StrsEmpty(&cells[0]) && StrsEmpty(&cells[1]),
    "new header cells are empty");
  p = MdNextLine(&table.text, p, &row);
  MdNextLine(&table.text, p, &row);
  Check(MdTableSplitRow(&row, cells, 2) == 2 && StrsEmpty(&cells[0]) && StrsEmpty(&cells[1]),
    "new body cells are empty");
  Check(doc->edit.anchor < 0, "new table has an insertion caret");
  WordAction(doc, WORD_ALL);
  StrsInitS(&text, "one é😀\nthree"); EditInsert(&doc->edit, &text);
  WordRefresh(doc->view);
  Check(!StrCmp(doc->stats->text, "3 words 12 chars | Ln 2 Col 6 | EDIT *"), "UTF-8 source statistics");
  Key(doc, 'z', TERM_MOD_CTRL);
  Check(MemMem(doc->stats->text, StrLen(doc->stats->text), "words", 5) &&
    MemMem(doc->stats->text, StrLen(doc->stats->text), "chars", 5), "stats refresh after undo");
  WordAction(doc, WORD_ALL);
  StrsInitS(&text, "\n\n"); EditInsert(&doc->edit, &text);
  view->ruler_left = TRUE;
  HtkClipAll; HtkDrawCtl(doc->view);
  for (y = 0; y < doc->view->h - 1; y++) {
    x = doc->view->x + view->gutter - 1;
    Check(TermCellChar(term_back[(doc->view->y + y) * TermWidth + x]) == '|',
      "left ruler continues through empty document rows");
  }
  doc->window->closing = NULL; doc->window->submit = NULL;
  HtkWindowClose(doc->window); WordDispose(doc, 0);
}

U0 TestSearch()
{
  CWordApp app;
  CWordDoc *doc = WordNew(&app);
  CWordSearch search;
  HtkCtl *window = WordSearchDialog(doc, &search);
  CStrs text, query, replacement;
  U8 raw[7] = {'a', 0, 'b', ' ', 'a', 0, 'b'};

  StrsInitS(&text, "one two one"); EditInsert(&doc->edit, &text);
  HtkSetText(search.query, "one");
  WordSearchApply(search.run);
  Check(doc->edit.anchor == 0 && doc->edit.cursor == 3, "search wraps and selects a match");
  WordSearchApply(search.run);
  Check(doc->edit.anchor == 8 && doc->edit.cursor == 11, "search advances to next match");
  search.replace_toggle->value = TRUE; WordSearchMode(search.replace_toggle);
  Check(!search.replace_box->hidden && !StrCmp(search.run->text, "Replace"), "search exposes replacement options");
  HtkSetText(search.replacement, "é"); WordSearchApply(search.run);
  Check(Equal(&doc->edit.text, "one two é"), "replace the selected match");
  search.all->value = TRUE; WordSearchMode(search.all);
  HtkSetText(search.query, "o"); HtkSetText(search.replacement, "");
  WordSearchApply(search.run);
  Check(Equal(&doc->edit.text, "ne tw é"), "replace all permits empty replacement");
  Check(EditUndo(&doc->edit) && Equal(&doc->edit.text, "one two é"), "replace all is one undo step");
  doc->edit.readonly = TRUE; WordSearchApply(search.run);
  Check(Equal(&doc->edit.text, "one two é"), "readonly search blocks replacement");
  search.replace_toggle->value = FALSE; WordSearchMode(search.replace_toggle);
  Check(search.replace_box->hidden && !StrCmp(search.run->text, "Find next"), "replacement toggle restores search");
  doc->edit.readonly = FALSE;
  EditFini(&doc->edit); EditInit(&doc->edit);
  StrsInitN(&text, raw, sizeof(raw)); EditInsert(&doc->edit, &text);
  StrsInitN(&query, raw, 3); StrsInitS(&replacement, "é");
  Check(EditFind(&doc->edit, &query), "bounded search handles embedded NULs");
  Check(EditReplaceAll(&doc->edit, &query, &replacement) == 2 && Equal(&doc->edit.text, "é é"),
    "bounded replacement handles embedded NULs");
  StrsInitS(&query, "");
  Check(!EditFind(&doc->edit, &query) && !EditReplaceAll(&doc->edit, &query, &replacement),
    "empty query is rejected");
  HtkWindowClose(window); HtkDestroy(window);
  doc->window->closing = NULL; doc->window->submit = NULL;
  HtkWindowClose(doc->window); WordDispose(doc, 0);
}

U0 WordKeys(CWordDoc *doc, U8 *keys)
{
  I64 rune, n;

  while (*keys) {
    n = Utf8DecodeRune(keys, StrLen(keys), &rune);
    if (rune == 27) rune = TERM_KEY_ESCAPE;
    else if (rune == '\n') rune = TERM_KEY_ENTER;
    Key(doc, rune); keys += n;
  }
}

U0 TestMarkdownVim()
{
  CWordApp app;
  CWordDoc *doc = WordNew(&app);
  I64 mode;

  HtkVimMode(doc->view, TRUE);
  for (mode = HTK_MD_EDIT; mode <= HTK_MD_SOURCE; mode++) {
    HtkMarkdownMode(doc->view, mode);
    EditFini(&doc->edit); EditInit(&doc->edit);
    StrBufPutS(&doc->edit.text, "é\n  😀\nlast");
    doc->view->vim_insert = FALSE; doc->view->vim_at = 0;
    HtkWindowLayout(doc->window); HtkSetFocus(doc->view); HtkClipAll; HtkMdDraw(doc->view);
    Check(term_cursor_shape == TERM_CURSOR_BLOCK, "Word Normal cursor is block in both views");
    WordKeys(doc, "i"); HtkMdDraw(doc->view);
    Check(term_cursor_shape == TERM_CURSOR_BAR && doc->edit.cursor == 0,
      "Word Insert cursor changes to bar without moving the caret");
    Key(doc, TERM_KEY_ESCAPE); HtkMdDraw(doc->view);
    Check(term_cursor_shape == TERM_CURSOR_BLOCK, "Word Escape restores block cursor");
    WordKeys(doc, "J");
    Check(Equal(&doc->edit.text, "é 😀\nlast") && doc->edit.cursor == 2,
      "Markdown Vim J joins source lines in rendered and source views");
    Check(MemMem(doc->stats->text, StrLen(doc->stats->text), "NORMAL", 6) != NULL,
      "Vim status tracks normal mode after joining");
    WordKeys(doc, "u");
    Check(Equal(&doc->edit.text, "é\n  😀\nlast"), "Markdown Vim join undo");
    EditFini(&doc->edit); EditInit(&doc->edit);
    StrBufPutS(&doc->edit.text, "one two"); doc->view->vim_at = 0;
    WordKeys(doc, "cwnew word\x1b");
    Check(Equal(&doc->edit.text, "new word two") && !doc->view->vim_insert,
      "Markdown Vim cw preserves following spaces");
    WordKeys(doc, "u");
    Check(Equal(&doc->edit.text, "one two"), "Markdown Vim cw is a single undo step");
    WordKeys(doc, "i"); Key(doc, TERM_KEY_END); Key(doc, '!'); Key(doc, TERM_KEY_ESCAPE);
    Check(Equal(&doc->edit.text, "one two!"), "Markdown Insert End and typing agree in both views");
    doc->edit.cursor = 1; doc->edit.anchor = -1;
    WordKeys(doc, "V"); HtkMdRender(doc->view->data);
    HtkMdDraw(doc->view);
    Check(term_cursor_shape == TERM_CURSOR_BLOCK, "Word Visual cursor stays block");
    Check(doc->view->vim_visual == 2 && doc->edit.anchor == 0 && doc->edit.cursor == 8 &&
      MemMem(doc->stats->text, StrLen(doc->stats->text), "V-LINE", 6),
      "Markdown Visual line selection and status work in source and rendered modes");
    Key(doc, TERM_KEY_ESCAPE);
    Check(!doc->view->vim_visual && doc->edit.cursor == 1 && doc->edit.anchor == -1,
      "Markdown Visual Escape keeps logical source caret");
    WordKeys(doc, "vld");
    Check(Equal(&doc->edit.text, "o two!"), "Markdown Visual character deletion includes both endpoints");
    WordKeys(doc, "u"); Check(Equal(&doc->edit.text, "one two!"), "Markdown Visual delete undo");
  }
  doc->window->closing = NULL; doc->window->submit = NULL;
  HtkWindowClose(doc->window); WordDispose(doc, 0);
}

U0 TestTableNavigation()
{
  CWordApp app;
  CWordDoc *doc = WordNew(&app);
  CTermEvent e;
  CStrs cells[3], row;
  U8 *p;
  I64 positions[6], count = 0, i, mode, revision, source;

  StrBufPutS(&doc->edit.text, "| A | B | C |\n| --- | :---: | ---: |\n| é😀 |  | `a|b` |\n\nafter");
  p = MdNextLine(&doc->edit.text, doc->edit.text.a, &row);
  MdTableSplitRow(&row, cells, 3);
  for (i = 0; i < 3; i++) positions[count++] = cells[i].a - doc->edit.text.a;
  p = MdNextLine(&doc->edit.text, p, &row);
  MdNextLine(&doc->edit.text, p, &row); MdTableSplitRow(&row, cells, 3);
  for (i = 0; i < 3; i++) positions[count++] = cells[i].a - doc->edit.text.a;
  positions[4]--; // Between the two padding spaces in the empty body cell.
  e.key = TERM_KEY_TAB;
  revision = doc->edit.revision;
  for (mode = HTK_MD_EDIT; mode <= HTK_MD_SOURCE; mode++) {
    HtkMarkdownMode(doc->view, mode); HtkSetFocus(doc->view);
    doc->edit.cursor = positions[0]; doc->edit.anchor = -1;
    for (i = 1; i < 6; i++) {
      e.mods = 0; HtkKey(&e);
      Check(htk_focus == doc->view && doc->edit.cursor == positions[i] && doc->edit.anchor < 0,
        "Tab moves between cells and skips separator in both views");
    }
    HtkKey(&e); Check(doc->edit.cursor == positions[5], "Tab at last cell stays in table");
    for (i = 4; i >= 0; i--) {
      e.mods = TERM_MOD_SHIFT; HtkKey(&e);
      Check(htk_focus == doc->view && doc->edit.cursor == positions[i],
        "Shift-Tab moves back through table cells");
    }
    HtkKey(&e); Check(doc->edit.cursor == positions[0], "Shift-Tab at first cell stays in table");
  }
  Check(doc->edit.revision == revision && !doc->edit.undo, "cell navigation preserves document history");
  doc->edit.cursor = positions[4]; Key(doc, 'X');
  Check(MdFind(doc->edit.text.a, doc->edit.text.b, "| X |") != NULL,
    "typing after Tab inserts inside an empty cell");
  Key(doc, 'z', TERM_MOD_CTRL);
  HtkVimMode(doc->view, TRUE); doc->view->vim_insert = TRUE;
  doc->edit.cursor = positions[0]; e.mods = 0; HtkKey(&e);
  Check(doc->edit.cursor == positions[1] && doc->view->vim_insert && htk_focus == doc->view,
    "cell navigation preserves Vim Insert mode");
  HtkVimMode(doc->view, FALSE);
  doc->edit.cursor = StrsLen(&doc->edit.text); HtkKey(&e);
  Check(htk_focus != doc->view, "Tab outside a table moves focus normally");
  HtkSetFocus(doc->view); HtkMarkdownMode(doc->view, HTK_MD_READ);
  doc->edit.cursor = positions[0]; HtkKey(&e);
  Check(htk_focus != doc->view && doc->edit.cursor == positions[0], "readonly Tab moves focus normally");
  HtkMarkdownMode(doc->view, HTK_MD_EDIT); HtkSetFocus(doc->view);
  EditFini(&doc->edit); EditInit(&doc->edit); MdEditTable(&doc->edit, MD_TABLE_INSERT);
  source = doc->edit.cursor; HtkKey(&e);
  Check(doc->edit.cursor > source && htk_focus == doc->view, "Tab reaches another newly inserted empty cell");
  e.mods = TERM_MOD_SHIFT; HtkKey(&e);
  Check(doc->edit.cursor == source, "Shift-Tab returns to the new table's first cell");
  doc->window->closing = NULL; doc->window->submit = NULL;
  HtkWindowClose(doc->window); WordDispose(doc, 0);
}

U0 TestVimShortcuts()
{
  CWordApp app;
  CWordDoc *doc = WordNew(&app);
  CHtkMarkdown *view = doc->view->data;
  I64 i, step, y, top;

  HtkVimMode(doc->view, TRUE); HtkMarkdownMode(doc->view, HTK_MD_SOURCE);
  HtkWindowLayout(doc->window); HtkSetFocus(doc->view);
  doc->view->h = 8; view->ruler_top = TRUE; view->no_wrap = TRUE;
  for (i = 0; i < 40; i++) StrBufPutS(&doc->edit.text, "é😀x\n");
  doc->edit.cursor = 2; HtkMdDraw(doc->view);
  WindowKey('f', TERM_MOD_CTRL); HtkMdDraw(doc->view);
  Check(doc->edit.cursor == 34 && doc->view->top == 4 && htk_focus == doc->view &&
    !doc->edit.undo, "Word Ctrl-F pages using height excluding ruler and footer, without opening Search");
  WindowKey('b', TERM_MOD_CTRL); HtkMdDraw(doc->view);
  Check(doc->edit.cursor == 2 && doc->view->top == 0 && !doc->edit.undo,
    "Word Ctrl-B pages instead of applying Bold");
  WindowKey('V'); WindowKey('f', TERM_MOD_CTRL); HtkMdDraw(doc->view);
  Check(doc->view->vim_visual == 2 && doc->view->vim_head == 34 && doc->view->top == 4,
    "Word window shortcuts retain Visual page selection");
  WindowKey(TERM_KEY_ESCAPE); WindowKey('i'); WindowKey('b', TERM_MOD_CTRL);
  Check(doc->view->vim_insert && doc->edit.cursor == 2, "Word also pages in Insert mode");
  WindowKey('a', TERM_MOD_CTRL); WindowKey('e', TERM_MOD_CTRL);
  Check(doc->edit.cursor == 7 && doc->edit.anchor == -1, "Word Insert Ctrl-A/E move within the line");
  WindowKey('n', TERM_MOD_CTRL);
  Check(doc->edit.cursor == 15 && app.docs == doc && !doc->next,
    "Word Insert Ctrl-N moves down instead of creating a document");
  WindowKey('p', TERM_MOD_CTRL); WindowKey('w', TERM_MOD_CTRL);
  Check(app.docs == doc && doc->edit.cursor == 6 && htk_focus == doc->view,
    "Word Insert Ctrl-W cuts a word instead of closing its window");
  WindowKey('y', TERM_MOD_CTRL);
  Check(doc->edit.cursor == 7 && StrsLen(&doc->edit.text) == 320,
    "Word Insert Ctrl-Y pastes instead of redoing");
  WindowKey('u', TERM_MOD_CTRL);
  Check(doc->edit.cursor == 0 && doc->edit.text.a[0] == '\n',
    "Word Insert Ctrl-U cuts to line start instead of underlining");
  WindowKey('y', TERM_MOD_CTRL);

  // A wrapped source line pages in display rows, not entire source lines.
  EditFini(&doc->edit); EditInit(&doc->edit);
  for (i = 0; i < 10; i++) StrBufPutS(&doc->edit.text, "abcdefgh");
  doc->view->vim_insert = FALSE; doc->view->vim_at = 0; doc->view->top = 0;
  view->no_wrap = FALSE; view->column_width = 8;
  HtkMdDraw(doc->view); WindowKey('f', TERM_MOD_CTRL); HtkMdDraw(doc->view);
  Check(doc->edit.cursor == 32 && view->caret_y == 4 && doc->view->top == 4,
    "Word Ctrl-F advances four wrapped display rows");
  WindowKey('b', TERM_MOD_CTRL); HtkMdDraw(doc->view);
  Check(doc->edit.cursor == 0 && doc->view->top == 0, "wrapped source Ctrl-B returns to start");

  // Rendered code maps display rows back to source positions with syntax hidden.
  EditFini(&doc->edit); EditInit(&doc->edit); StrBufPutS(&doc->edit.text, "```\n");
  for (i = 0; i < 40; i++) StrBufPutS(&doc->edit.text, "é😀x\n");
  StrBufPutS(&doc->edit.text, "```\n"); doc->edit.cursor = 6; doc->view->vim_at = 6;
  view->column_width = 0; HtkMarkdownMode(doc->view, HTK_MD_EDIT);
  doc->view->top = 0; HtkMdDraw(doc->view);
  y = view->caret_y; top = doc->view->top; step = view->height - 2;
  WindowKey('f', TERM_MOD_CTRL); HtkMdDraw(doc->view);
  Check(view->caret_y == y + step && doc->view->top == top + step &&
    EditBoundary(&doc->edit, doc->edit.cursor) && !doc->edit.undo,
    "rendered Word paging moves the viewport and a valid source caret together");
  WindowKey('b', TERM_MOD_CTRL); HtkMdDraw(doc->view);
  Check(doc->edit.cursor == 6 && doc->view->top == 0, "rendered Ctrl-B returns to original Unicode caret");

  HtkVimMode(doc->view, FALSE); doc->edit.cursor = 4;
  WindowKey('a', TERM_MOD_CTRL);
  Check(doc->edit.anchor == 0 && doc->edit.cursor == StrsLen(&doc->edit.text),
    "disabling Vim restores Word's ordinary Select All shortcut");
  doc->window->closing = NULL; doc->window->submit = NULL;
  HtkWindowClose(doc->window); WordDispose(doc, 0);
}

U0 TestAlignment()
{
  CWordApp app;
  CWordDoc *doc = WordNew(&app);
  CEdit *edit = &doc->edit;
  CHtkMarkdown *view = doc->view->data;
  CMdAlignment aligned;
  CMarkdown md;
  CMdExport export;
  CStrBuf out, pdf;
  CStrs input, row;
  U8 *p;
  I64 a, b, old_cursor, revision, x, y;

  StrBufInit(&out); StrBufInit(&pdf); StrBufInit(&export.links);
  export.out = &out; export.format = MD_EXPORT_TEXT;
  StrBufPutS(&edit->text, "Hello **world** é.\n\nSecond paragraph.\n");
  edit->cursor = old_cursor = 7;
  WordAction(doc, WORD_ALIGN + MD_ALIGN_CENTER);
  Check(MdAlignAt(&edit->text, edit->cursor, &aligned) && aligned.align == MD_ALIGN_CENTER &&
    Equal(&aligned.body, "Hello **world** é.\n"), "center formats current paragraph without changing its text");
  Check(edit->cursor == old_cursor + StrLen(md_align_fences[MD_ALIGN_CENTER]) + 1 && edit->anchor < 0 &&
    doc->alignment[MD_ALIGN_CENTER]->value, "alignment preserves cursor and highlights toolbar state");
  MarkdownInit(&md, &MdExportText, NULL, &export); md.width = 20;
  MarkdownRenderStrs(&md, &aligned.source);
  Check(Equal(&out, "     Hello world é.\n"), "center measures styled Unicode text");
  StrBufClear(&out); WordAction(doc, WORD_ALIGN + MD_ALIGN_RIGHT);
  MdAlignAt(&edit->text, edit->cursor, &aligned); MarkdownRenderStrs(&md, &aligned.source);
  Check(Equal(&out, "        Hello world é.\n"), "right alignment fills available width");
  revision = edit->revision; WordAction(doc, WORD_ALIGN + MD_ALIGN_RIGHT);
  Check(edit->revision == revision, "reapplying alignment does not nest divs or create history");
  WordAction(doc, WORD_ALIGN + MD_ALIGN_LEFT);
  StrBufClear(&out); MdAlignAt(&edit->text, edit->cursor, &aligned); MarkdownRenderStrs(&md, &aligned.source);
  Check(Equal(&out, "  Hello world é.\n"), "left resets paragraph alignment");
  Check(EditUndo(edit) && MdAlignAt(&edit->text, edit->cursor, &aligned) && aligned.align == MD_ALIGN_RIGHT,
    "alignment is one undo step");
  StrBufClear(&out); MarkdownExport(&edit->text, &out, MD_EXPORT_HTML);
  Check(MdFind(out.a, out.b, "<div style=\"text-align:right\">") &&
    MdFind(out.a, out.b, "<strong>world</strong>") && !MdFind(out.a, out.b, "htk-align"),
    "HTML exports alignment with semantic inline formatting");
  StrBufClear(&out); MarkdownExport(&edit->text, &out, MD_EXPORT_TEXT);
  Check(StrsLen(&out) < 100 && MdFind(out.a, out.b, "Hello world é.") && !MdFind(out.a, out.b, ":::") ,
    "plain text exports omit div syntax and alignment padding");
  MdPdfInput(&edit->text, &pdf);
  Check(MdFind(pdf.a, pdf.b, "\\begin{flushright}") && MdFind(pdf.a, pdf.b, "\\end{flushright}") &&
    MdFind(pdf.a, pdf.b, "Hello **world** é."), "PDF input preserves Markdown inside alignment environments");

  EditFini(edit); EditInit(edit);
  StrBufPutS(&edit->text, "one two three four five six seven eight nine ten\n");
  WordAction(doc, WORD_ALIGN + MD_ALIGN_JUSTIFY);
  StrBufClear(&out); md.width = 12; MarkdownRenderStrs(&md, &edit->text);
  Check(MdStarts(out.a, out.b, "  one      two\n  three   four\n"), "wide alignment expands gaps in wrapped lines");
  p = out.a;
  while (p < out.b) {
    p = MdNextLine(&out, p, &row);
    Check(MdWidth(&row) <= 14, "justified paragraph stays inside its width");
  }
  Check(MdFind(out.a, out.b, "  nine ten\n"), "last paragraph line stays left aligned");
  HtkWindowLayout(doc->window); view->column_width = 15;
  a = MdFind(edit->text.a, edit->text.b, "two") - edit->text.a;
  edit->cursor = a + 2; HtkMdRender(view); x = view->caret_x; y = view->caret_y;
  Check(HtkMdHit(view, x, y) == a + 2 && EditBoundary(edit, HtkMdHit(view, x + 1, y)),
    "justified hit testing retains source positions");
  WordAction(doc, WORD_ALL); WordAction(doc, WORD_ALIGN + MD_ALIGN_CENTER);
  Check(MdAlignAt(&edit->text, edit->cursor, &aligned) && aligned.align == MD_ALIGN_CENTER,
    "formatting selection of an existing div changes its alignment");

  EditFini(edit); EditInit(edit);
  StrBufPutS(&edit->text, "first\n\nsecond\n\n```\nuntouched\n```\n\nlast\n");
  edit->anchor = 0; edit->cursor = StrsLen(&edit->text);
  Check(MdEditAlign(edit, MD_ALIGN_RIGHT), "align selected paragraphs as one operation");
  Check(MdFind(edit->text.a, edit->text.b, "```\nuntouched\n```\n") &&
    EditUndo(edit) && Equal(&edit->text, "first\n\nsecond\n\n```\nuntouched\n```\n\nlast\n"),
    "selected code remains untouched and alignment undoes together");
  a = MdFind(edit->text.a, edit->text.b, "untouched") - edit->text.a;
  edit->cursor = a; edit->anchor = -1;
  Check(!MdEditAlign(edit, MD_ALIGN_CENTER), "alignment does not edit fenced code");
  EditFini(edit); EditInit(edit);
  Check(MdEditAlign(edit, MD_ALIGN_CENTER) && MdAlignAt(&edit->text, edit->cursor, &aligned) &&
    Equal(&aligned.body, "\n"), "empty paragraph can be aligned before typing");
  edit->readonly = TRUE; revision = edit->revision;
  Check(!MdEditAlign(edit, MD_ALIGN_LEFT) && edit->revision == revision, "readonly protects paragraph formatting");
  StrBufClear(&pdf);
  StrsInitS(&input, "```\n::: {.htk-align-center style=\"text-align:center\"}\ntext\n:::\n```\n");
  MdPdfInput(&input, &pdf);
  Check(Equal(&pdf, input.a), "PDF does not interpret alignment inside code fences");
  StrBufFini(&out); StrBufFini(&pdf); StrBufFini(&export.links);
  doc->window->closing = NULL; doc->window->submit = NULL;
  HtkWindowClose(doc->window); WordDispose(doc, 0);
}

U0 TestPdf()
{
  CWordApp app;
  CWordDoc *doc = WordNew(&app);
  CWordPdfDialog dialog;
  CMdPdf options;
  HtkCtl *window = WordPdfDialog(doc, &dialog);
  CStrBuf command, error;
  CStrs text;
  U8 *bytes, *old_path;
  I64 size, i;
  Bool ok;

  Check(WordPdfRead(&dialog, &options) && options.paper == 0 && options.font_size == 11 &&
    options.margins[0] == 20, "PDF settings defaults");
  HtkSetText(dialog.margins[0], "12.5");
  Check(!WordPdfRead(&dialog, &options), "PDF margins require whole millimeters");
  HtkSetText(dialog.margins[0], "15"); dialog.paper->value = 1;
  HtkSetText(dialog.margins[1], "70"); HtkSetText(dialog.margins[3], "70");
  Check(!WordPdfRead(&dialog, &options), "PDF margins must leave printable area");
  HtkSetText(dialog.margins[1], "10"); HtkSetText(dialog.margins[3], "12");
  dialog.orientation->value = 1; dialog.font_size->value = 2; dialog.toc->value = TRUE;
  Check(WordPdfRead(&dialog, &options), "PDF accepts landscape with independent margins");
  StrBufInit(&command); StrBufInit(&error);
  Check(MdPdfCommand(&command, &options, "tests/out/layout.pdf", "folder with spaces") &&
    MdFind(command.a, command.b, "papersize=a5") && MdFind(command.a, command.b, "fontsize=12pt") &&
    MdFind(command.a, command.b, "top=15mm,right=10mm,bottom=20mm,left=12mm,landscape") &&
    MdFind(command.a, command.b, " --toc"), "PDF command applies page layout settings");
  HtkCtl *apply = window->link;
  WordPdfApply(apply);
  Check(dialog.applied && window->closed && doc->pdf.landscape && doc->pdf.paper == 1,
    "PDF settings apply to this document");
  HtkDestroy(window);
  #ifndef IS_WINDOWS
  old_path = StrNew(getenv("PATH"));
  StrsInitS(&text, "#!/bin/sh\nprintf '%s\n' \"$@\" > tests/out/pdf-args.txt\nwhile [ \"$#\" -gt 0 ]; do\n  if [ \"$1\" = '--output' ]; then shift; output=$1; fi\n  shift\ndone\n/bin/cat > tests/out/pdf-stdin.md\nprintf '%s\n' '%PDF-1.7 fixture' > \"$output\"\n");
  Check(FileReplace("tests/out/pandoc", &text) && !system("/bin/chmod +x tests/out/pandoc")(I32),
    "prepare PDF process fixture");
  setenv("PATH", "tests/out", 1);
  U8 raw[5] = {'a', 0, 'b', '\n', 'c'};
  StrsInitN(&text, raw, sizeof(raw));
  ok = MdPdfExport(&text, "tests/out/word 'quoted' $(not-a-command).pdf", "folder 'quoted'", &options, &error);
  setenv("PATH", old_path, 1);
  Check(ok && StrsEmpty(&error), "PDF export quotes paths and replaces destination after success");
  bytes = FileRead("tests/out/pdf-stdin.md", &size);
  Check(bytes && size == sizeof(raw) && !MemCmp(bytes, raw, size), "PDF receives bounded unsaved Markdown bytes");
  Free(bytes);
  bytes = FileRead("tests/out/pdf-args.txt", &size);
  Check(bytes && MemMem(bytes, size, "folder 'quoted'", 15), "PDF keeps resource path as one argument");
  Free(bytes);
  StrsInitS(&text, "keep original"); FileReplace("tests/out/word-pdf-failure.pdf", &text);
  setenv("PATH", "/nonexistent", 1);
  ok = MdPdfExport(&text, "tests/out/word-pdf-failure.pdf", ".", &options, &error);
  setenv("PATH", old_path, 1); Free(old_path);
  Check(!ok && MdFind(error.a, error.b, "pandoc"), "missing Pandoc reports captured diagnostics");
  bytes = FileRead("tests/out/word-pdf-failure.pdf", &size);
  Check(bytes && size == 13 && !MemCmp(bytes, "keep original", 13), "failed PDF export preserves existing file");
  Free(bytes);
  // Optional integration check; regular tests do not require Pandoc/TeX.
  if (getenv("WORD_TEST_PDF")) {
    MdPdfDefault(&options); options.paper = 1; options.landscape = TRUE;
    StrsInitS(&text, "# PDF export\n\nCurrent **unsaved** text with é.\n\n::: {.htk-align-center style=\"text-align:center\"}\nCentered paragraph.\n:::\n\n::: {.htk-align-right style=\"text-align:right\"}\nRight paragraph.\n:::\n\n::: {.htk-align-justify style=\"text-align:justify\"}\nJustified paragraph has enough text to fill a line and carry its remaining words over to the next line in this PDF.\n:::\n\n| A | B |\n| --- | --- |\n| one | two |\n");
    Check(MdPdfExport(&text, "tests/out/word-real.pdf", ".", &options, &error), "real Pandoc PDF export");
  }
  #endif
  StrBufFini(&command); StrBufFini(&error);
  doc->window->closing = NULL; doc->window->submit = NULL;
  HtkWindowClose(doc->window); WordDispose(doc, 0);
}

TestEdit;
TestMarkdown;
TestWindow;
// TestWindow releases the terminal buffers; allocate them for the new windows.
TermBuffersAlloc;
TestTableEditing;
TestSearch;
TestMarkdownVim;
TestTableNavigation;
TestVimShortcuts;
TestAlignment;
TestPdf;
Free(term_back); Free(term_front);
"ok word\n";
