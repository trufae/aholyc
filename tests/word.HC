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
  Check(HtkKidCount(bar) == 8 && doc->status->h == 1 &&
    doc->status->y == doc->window->y + doc->window->h - 2, "compact toolbar and docked statusbar");
  Check(doc->source->parent == doc->status && doc->editable->parent == doc->status &&
    doc->editable->x + doc->editable->w == doc->status->x + doc->status->w,
    "view modes dock at the statusbar bottom right");
  while (button) {
    Check(button->data != WORD_NEW && button->data != WORD_OPEN && button->data != WORD_SAVE,
      "file actions only in menus");
    button = button->sib;
  }
  doc->window->w = doc->window->min_w;
  HtkWindowLayout(doc->window);
  Check(doc->vim->x + doc->vim->w <= bar->x + bar->w && bar->h == 1,
    "toolbar fits the minimum window width");
  doc->window->w = 100;
  HtkWindowLayout(doc->window);
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

TestEdit;
TestMarkdown;
TestWindow;
// TestWindow releases the terminal buffers; allocate them for the new windows.
TermBuffersAlloc;
TestTableEditing;
TestSearch;
Free(term_back); Free(term_front);
"ok word\n";
