// HolyC Markdown word processor. Build: aholyc examples/word.hc -o word
#define UI_HTK_VIMODE
#define TERM_CTRL_Z_KEY
#ifndef WORD_TEST
#define HTK_NATIVE_CLIPBOARD
#endif
#include "../lib/htk/markdown.hc"
#include "../lib/htk/history.hc"
#include "../lib/htk/filepick.hc"
#include "../lib/text/md_export.hc"
#include "../lib/text/md_pdf.hc"
#include "../lib/text/font.hc"
#include "../lib/io/replace.hc"
extern I64 system(U8 *command);
#ifdef IS_WINDOWS
extern U8 *LoadLibraryA(U8 *name);
extern U8 *GetProcAddress(U8 *module, U8 *name);
extern I32 FreeLibrary(U8 *module);
U8 *WordShellOpen(U8 *window, U8 *operation, U8 *file, U8 *params, U8 *dir, I32 show);
#endif

#define WORD_NEW 1
#define WORD_OPEN 2
#define WORD_SAVE 3
#define WORD_SAVE_AS 4
#define WORD_CLOSE 5
#define WORD_UNDO 6
#define WORD_REDO 7
#define WORD_CUT 8
#define WORD_COPY 9
#define WORD_PASTE 10
#define WORD_ALL 11
#define WORD_BOLD 12
#define WORD_ITALIC 13
#define WORD_UNDERLINE 14
#define WORD_FG 15
#define WORD_BG 16
#define WORD_FONT 17
#define WORD_EMOJI 18
#define WORD_LINK 19
#define WORD_IMAGE 20
#define WORD_HEADING 21
#define WORD_LIST 22
#define WORD_QUOTE 23
#define WORD_CODE 24
#define WORD_FIND 25
#define WORD_OUTLINE 26
#define WORD_FIT 27
#define WORD_HTML 28
#define WORD_GEM 29
#define WORD_TEXT 30
#define WORD_LINK_NEW 31
#define WORD_LINK_REPLACE 32
#define WORD_LINK_EDIT 33
#define WORD_LINK_SYSTEM 34
#define WORD_LINK_COPY 35
#define WORD_QUIT 36
#define WORD_SOURCE 37
#define WORD_EDITABLE 38
#define WORD_HISTORY 39
#define WORD_TABLE 40
#define WORD_BORDER 60
#define WORD_LINES 70
#define WORD_RULER_TOP 71
#define WORD_RULER_LEFT 72
#define WORD_WIDTH 73
#define WORD_PAGE_SIZE 74
#define WORD_CONTINUOUS 75
#define WORD_PAGES 76
#define WORD_SECTION 77
#define WORD_PREV_SECTION 78
#define WORD_NEXT_SECTION 79
#define WORD_RULE 80
#define WORD_PAGE_BREAK 81
#define WORD_CODE_BLOCK 82
#define WORD_VIM 83
#define WORD_PDF 84
#define WORD_PDF_SETTINGS 85
#define WORD_ALIGN 86 // + MD_ALIGN_LEFT/RIGHT/CENTER/JUSTIFY

class CWordApp;
class CWordDoc
{
  CWordDoc *next;
  CWordApp *app;
  CEdit edit;
  CMdPdf pdf;
  HtkCtl *window;
  HtkCtl *view;
  HtkCtl *outline;
  HtkCtl *source;
  HtkCtl *editable;
  HtkCtl *vim;
  HtkCtl *alignment[4];
  HtkCtl *status;
  HtkCtl *outline_button;
  HtkCtl *stats;
  HtkCtl *link_menu;
  CStrBuf path, target;
  I64 outline_revision, link_a, link_b;
  Bool outline_hidden;
};
class CWordApp
{
  CWordDoc *docs;
};

U0 WordAction(CWordDoc *doc, I64 action);
CWordDoc *WordNew(CWordApp *app, U8 *path=NULL);
Bool WordLoad(CWordDoc *doc, U8 *path);
Bool WordSave(CWordDoc *doc, Bool save_as=FALSE);

U0 WordStatus(CWordDoc *doc)
{
  CEdit *edit = &doc->edit;
  I64 at = 0, next, rune, words = 0, chars = 0, line = 1, column = 1;
  I64 caret = HtkVimCaret(doc->view, edit->cursor);
  Bool in_word = FALSE, space;
  U8 *mode = "EDIT", *dirty = "", *text;

  while (at < StrsLen(&edit->text)) {
    next = EditNext(edit, at, 1);
    rune = edit->text.a[at];
    Utf8DecodeRune(edit->text.a + at, next - at, &rune);
    space = EditSpace(rune);
    if (!space && !in_word) words++;
    in_word = !space;
    chars++;
    if (at < caret) {
      if (rune == '\n') { line++; column = 1; }
      else column++;
    }
    at = next;
  }
  if (doc->view->vim_mode) {
    mode = "NORMAL";
    if (doc->view->vim_insert) mode = "INSERT";
    else if (doc->view->vim_visual == 1) mode = "VISUAL";
    else if (doc->view->vim_visual == 2) mode = "V-LINE";
  }
  if (edit->readonly) mode = "READ";
  if (edit->revision != edit->saved) dirty = " *";
  text = MStrPrint("%d words %d chars | Ln %d Col %d | %s%s", words, chars,
    line, column, mode, dirty);
  HtkSetText(doc->stats, text);
  Free(text);
}

U0 WordOutlineHit(HtkCtl *tree)
{
  CWordDoc *doc = tree->user(CWordDoc *);
  CHtkMarkdown *view = doc->view->data;

  if (tree->link) {
    doc->edit.cursor = tree->link->data;
    doc->edit.anchor = -1;
    view->section_at = doc->edit.cursor;
    HtkMdRender(view);
    doc->view->top = view->caret_y;
    view->follow = FALSE;
    WordStatus(doc);
    HtkSetFocus(doc->view);
  }
}

U0 WordRefresh(HtkCtl *view)
{
  CWordDoc *doc = view->user(CWordDoc *);
  HtkCtl *node, *parent, *levels[6], *kid, *next;
  CStrs line, prefix, suffix;
  U8 *p, *label, *title;
  I64 level, i;
  CMdFence fence;

  title = StrNew(doc->path.a);
  if (!StrsLen(&doc->path)) { Free(title); title = StrNew("Untitled.md"); }
  if (doc->edit.revision != doc->edit.saved) {
    U8 *dirty = MStrPrint("* %s", title);
    Free(title);
    title = dirty;
  }
  CHtkMarkdown *mdview = doc->view->data;
  doc->source->value = (mdview->mode & HTK_MD_SOURCE) != 0;
  doc->editable->value = !doc->edit.readonly;
  if (doc->source->value) HtkSetText(doc->source, "Source");
  else HtkSetText(doc->source, "Render");
  if (doc->editable->value) HtkSetText(doc->editable, "Edit");
  else HtkSetText(doc->editable, "View");
  doc->vim->value = doc->view->vim_mode;
  doc->outline_button->value = !doc->outline_hidden;
  CMdAlignment aligned;
  level = MD_ALIGN_LEFT;
  if (MdAlignAt(&doc->edit.text, doc->edit.cursor, &aligned)) level = aligned.align;
  for (i = 0; i < 4; i++) doc->alignment[i]->value = i == level;
  WordStatus(doc);
  HtkSetText(doc->window, title);
  Free(title);
  kid = HtkWindowContent(doc->window)->kids->kids;
  while (kid) {
    if (kid->data >= WORD_BOLD && kid->data <= WORD_UNDERLINE) {
      p = "**";
      if (kid->data == WORD_ITALIC) p = "*";
      if (kid->data == WORD_UNDERLINE) p = "<u>";
      StrsInitS(&prefix, p);
      if (kid->data == WORD_UNDERLINE) p = "</u>";
      StrsInitS(&suffix, p);
      kid->value = EditWrapped(&doc->edit, &prefix, &suffix);
    }
    kid = kid->sib;
  }
  if (doc->outline_revision == doc->edit.revision) return;
  doc->outline_revision = doc->edit.revision;
  kid = doc->outline->kids;
  while (kid) { next = kid->sib; HtkDestroy(kid); kid = next; }
  doc->outline->kids = NULL;
  doc->outline->link = NULL;
  p = doc->edit.text.a;
  while (p < doc->edit.text.b) {
    p = MdNextLine(&doc->edit.text, p, &line);
    MdFenceStep(&fence, &line);
    level = MdTitleLevel(&line);
    if (!fence.count && level) {
      parent = NULL;
      for (i = level - 2; i >= 0; i--)
        if (levels[i]) { parent = levels[i]; break; }
      label = MAlloc(StrsLen(&line) + 1);
      MemCpy(label, line.a + level, StrsLen(&line) - level);
      label[StrsLen(&line) - level] = 0;
      node = HtkTreeAdd(doc->outline, parent, label);
      Free(label);
      node->data = line.a - doc->edit.text.a;
      levels[level - 1] = node;
      for (i = level; i < 6; i++) levels[i] = NULL;
    }
  }
  // A click on even the first heading should navigate, not just select it.
  doc->outline->link = NULL;
}

U0 WordClick(HtkCtl *button)
{
  WordAction(button->user(CWordDoc *), button->data);
}

HtkCtl *WordItem(CWordDoc *doc, HtkCtl *parent, U8 *label, I64 action)
{
  HtkCtl *item;

  if (parent->kind == HTK_MENU) item = HtkMenuItem(parent, label);
  else { item = HtkToolButtonNew(label); HtkAdd(parent, item); }
  item->data = action;
  item->user = doc;
  item->changed = &WordClick;
  return item;
}

U0 WordWrap(CWordDoc *doc, U8 *prefix, U8 *suffix)
{
  CStrs a, b;

  StrsInitS(&a, prefix);
  StrsInitS(&b, suffix);
  if (StrsFindC(&a, '\n')) EditWrap(&doc->edit, &a, &b);
  else MdEditWrap(&doc->edit, &a, &b);
}

Bool WordCheckSave(CWordDoc *doc)
{
  U8 *choices[3] = {"Save", "Discard", "Cancel"};
  I64 result;

  if (doc->edit.revision == doc->edit.saved) return TRUE;
  result = HtkChoiceFor(doc->window, "Unsaved changes", choices, 3, 3);
  if (result == 0) return WordSave(doc);
  return result == 1;
}

Bool WordClosing(HtkCtl *window)
{
  return WordCheckSave(window->user(CWordDoc *));
}

U0 WordDispose(I64 data, I64 unused)
{
  CWordDoc *doc = data(CWordDoc *);
  CWordDoc **at = &doc->app->docs;

  while (*at && *at != doc) at = &(*at)->next;
  if (*at) *at = doc->next;
  HtkDestroy(doc->link_menu);
  HtkDestroy(doc->window);
  EditFini(&doc->edit);
  StrBufFini(&doc->path);
  StrBufFini(&doc->target);
  Free(doc);
}

U0 WordClosed(HtkCtl *window)
{
  HtkHookAdd(0, 0, &WordDispose, window->user, 0);
}

Bool WordSave(CWordDoc *doc, Bool save_as=FALSE)
{
  U8 *path = NULL;
  Bool ok;

  if (save_as || !StrsLen(&doc->path)) {
    path = HtkPromptFor(doc->window, "Save Markdown", "File path:", doc->path.a);
    if (!path || !*path) { Free(path); return FALSE; }
    if (StrCmp(path, doc->path.a) && FileExists(path) &&
      !HtkConfirmFor(doc->window, "Replace file", "Replace the existing file?")) {
        Free(path);
        return FALSE;
      }
  }
  if (!path) path = StrNew(doc->path.a);
  ok = FileReplace(path, &doc->edit.text);
  if (ok) {
    StrBufClear(&doc->path);
    StrBufPutS(&doc->path, path);
    doc->edit.saved = doc->edit.revision;
    WordRefresh(doc->view);
    HtkNotify("Markdown saved", 2000);
  } else HtkMsgBoxFor(doc->window, "Save failed", "The original file was kept. Check the path and permissions.");
  Free(path);
  return ok;
}

Bool WordLoad(CWordDoc *doc, U8 *path)
{
  I64 size;
  U8 *bytes = FileRead(path, &size);

  if (!bytes) { HtkMsgBoxFor(doc->window, "Open failed", "Cannot read this Markdown file."); return FALSE; }
  if (!Utf8Valid(bytes, size)) {
    Free(bytes);
    HtkMsgBoxFor(doc->window, "Open failed", "The document must contain valid UTF-8.");
    return FALSE;
  }
  if (!WordCheckSave(doc)) { Free(bytes); return FALSE; }
  EditFini(&doc->edit);
  EditInit(&doc->edit);
  StrBufPutN(&doc->edit.text, bytes, size);
  Free(bytes);
  StrBufClear(&doc->path);
  StrBufPutS(&doc->path, path);
  doc->outline_revision = -1;
  CHtkMarkdown *view = doc->view->data;
  HtkMarkdownMode(doc->view, view->mode);
  view->section_at = 0;
  doc->view->top = 0;
  WordRefresh(doc->view);
  return TRUE;
}

U0 WordLinkMenu(HtkCtl *view, I64 a, I64 b, CStrs *target)
{
  CWordDoc *doc = view->user(CWordDoc *);

  doc->link_a = a;
  doc->link_b = b;
  StrBufClear(&doc->target);
  StrBufPutStrs(&doc->target, target);
  HtkMenuOpenAt(doc->link_menu, view->x + view->mouse_x, view->y + view->mouse_y + 1);
}

U0 WordAnchor(CWordDoc *doc, CStrs *anchor)
{
  CHtkMarkdown *view = doc->view->data;
  CStrs line;
  CStrBuf slug;
  U8 *p = doc->edit.text.a;
  I64 level, at;
  CMdFence fence;

  StrBufInit(&slug);
  while (p < doc->edit.text.b) {
    at = p - doc->edit.text.a;
    p = MdNextLine(&doc->edit.text, p, &line);
    MdFenceStep(&fence, &line);
    level = MdTitleLevel(&line);
    if (level && !fence.count) {
      line.a += level;
      StrsTrim(&line);
      StrBufClear(&slug);
      MdSlug(&slug, &line);
      if (StrsLen(&slug) == StrsLen(anchor) && !MemCmp(slug.a, anchor->a, StrsLen(anchor))) {
        doc->edit.cursor = at;
        doc->edit.anchor = -1;
        view->section_at = at;
        HtkMdRender(view);
        doc->view->top = view->caret_y;
        view->follow = FALSE;
        break;
      }
    }
  }
  StrBufFini(&slug);
}

U8 *WordResolve(CWordDoc *doc, CStrs *target)
{
  CStrBuf out;
  U8 *p, *slash = NULL;
  I64 a, b;
  Bool absolute = StrsLen(target) && target->a[0] == '/';

  StrBufInit(&out);
  if (!absolute && !MdFind(target->a, target->b, ":")) {
    for (p = doc->path.a; p < doc->path.b; p++) if (*p == '/') slash = p;
    if (slash) StrBufPutN(&out, doc->path.a, slash + 1 - doc->path.a);
    else StrBufPutS(&out, "./");
  }
  for (p = target->a; p < target->b; p++) {
    a = -1; b = -1;
    if (*p == '%' && p + 2 < target->b) { a = MdHex(p[1]); b = MdHex(p[2]); }
    if (a >= 0 && b >= 0 && (a || b)) { StrBufPutC(&out, a * 16 + b); p += 2; }
    else StrBufPutC(&out, *p);
  }
  return StrBufTake(&out);
}

U0 WordFollow(CWordDoc *doc, Bool replace)
{
  CStrs target = *(&doc->target)(CStrs *), anchor;
  U8 *hash, *path;
  CWordDoc *opened = doc;

  if (!MdTargetSafe(&target) || MdFind(target.a, target.b, ":")) {
    HtkMsgBoxFor(doc->window, "Link", "Use Open with system handler for external links.");
    return;
  }
  hash = StrsFindC(&target, '#');
  StrsInitN(&anchor, "", 0);
  if (hash) { StrsInit(&anchor, hash + 1, target.b); target.b = hash; }
  if (!StrsEmpty(&target)) {
    path = WordResolve(doc, &target);
    if (replace) { if (!WordLoad(doc, path)) opened = NULL; }
    else opened = WordNew(doc->app, path);
    Free(path);
  }
  if (opened && !StrsEmpty(&anchor)) WordAnchor(opened, &anchor);
}

U0 WordSystem(CWordDoc *doc)
{
  CStrs target = *(&doc->target)(CStrs *);
  U8 *path, *p;
  #ifdef IS_WINDOWS
  if (!MdTargetSafe(&target)) { HtkNotify("Unsupported link target", 2000); return; }
  if (MdFind(target.a, target.b, ":")) path = StrNew(doc->target.a);
  else path = WordResolve(doc, &target);
  U8 *module = LoadLibraryA("shell32.dll");
  WordShellOpen *open = NULL;
  if (module) open = GetProcAddress(module, "ShellExecuteA")(WordShellOpen *);
  if (!open || open(NULL, "open", path, NULL, NULL, 1)(I64) <= 32)
    HtkNotify("System handler could not open the link", 3000);
  if (module) FreeLibrary(module);
  Free(path);
  #else
  CStrBuf command;
  I64 result;

  if (!MdTargetSafe(&target)) { HtkNotify("Unsupported link target", 2000); return; }
  if (MdFind(target.a, target.b, ":")) path = StrNew(doc->target.a);
  else path = WordResolve(doc, &target);
  StrBufInit(&command);
  #ifdef IS_MACOS
  StrBufPutS(&command, "open '");
  #else
  StrBufPutS(&command, "xdg-open '");
  #endif
  for (p = path; *p; p++) {
    if (*p == '\'') StrBufPutS(&command, "'\\''");
    else StrBufPutC(&command, *p);
  }
  StrBufPutS(&command, "' >/dev/null 2>&1");
  result = system(command.a)(I32);
  if (result) HtkNotify("System handler could not open the link", 3000);
  StrBufFini(&command);
  Free(path);
  #endif
}

U0 WordLinkEdit(CWordDoc *doc, Bool existing, Bool image=FALSE)
{
  CStrBuf out;
  CStrs label, target, text;
  U8 *url, *p, *after;
  I64 a, b;

  EditSelection(&doc->edit, &a, &b);
  StrsInit(&label, doc->edit.text.a + a, doc->edit.text.a + b);
  if (existing) {
    a = doc->link_a; b = doc->link_b;
    image = doc->edit.text.a[a] == '!' || MdStarts(doc->edit.text.a + a, doc->edit.text.a + b, "<img ");
    if (!MdLink(doc->edit.text.a + a, doc->edit.text.a + b, &label, &target, &after)) {
      p = MemChr(doc->edit.text.a + a, '>', b - a);
      if (!image && p) {
        after = MdFind(p + 1, doc->edit.text.a + b, "</a>");
        if (after) StrsInit(&label, p + 1, after);
      } else StrsInitS(&label, "image");
    }
  }
  if (existing) url = HtkPromptFor(doc->window, "Edit link", "Relative file, URL or #heading:", doc->target.a);
  else url = HtkPromptFor(doc->window, "Link target", "Relative file, URL or #heading:", "");
  if (!url || !*url) { Free(url); return; }
  StrBufInit(&out);
  if (image) StrBufPutC(&out, '!');
  StrBufPutC(&out, '[');
  if (StrsEmpty(&label)) StrBufPutS(&out, "link");
  else StrBufPutStrs(&out, &label);
  StrBufPutS(&out, "](");
  for (p = url; *p; p++) {
    if (*p <= ' ' || *p == '(' || *p == ')' || *p == '<' || *p == '>' || *p == '\\')
      StrBufPrintf(&out, "%%%02X", *p);
    else StrBufPutC(&out, *p);
  }
  StrBufPutC(&out, ')');
  EditReplace(&doc->edit, a, b, &out);
  StrBufFini(&out);
  Free(url);
}

class CWordPdfDialog
{
  CWordDoc *doc;
  HtkCtl *window;
  HtkCtl *paper;
  HtkCtl *orientation;
  HtkCtl *engine;
  HtkCtl *font_size;
  HtkCtl *margins[4];
  HtkCtl *toc;
  HtkCtl *message;
  Bool applied;
};

HtkCtl *WordPdfField(HtkCtl *grid, U8 *label, HtkCtl *field, I64 row)
{
  HtkCtl *text = HtkNew(HTK_LABEL);

  HtkSetText(text, label); text->row = row;
  HtkAdd(grid, text);
  field->col = 1; field->row = row; field->expand = TRUE;
  HtkAdd(grid, field);
  return field;
}

Bool WordPdfRead(CWordPdfDialog *dialog, CMdPdf *options)
{
  I64 i, value;
  U8 *p;

  MdPdfDefault(options);
  options->paper = dialog->paper->value;
  options->engine = dialog->engine->value;
  options->font_size = dialog->font_size->value + 10;
  options->landscape = dialog->orientation->value == 1;
  options->toc = dialog->toc->value != 0;
  for (i = 0; i < 4; i++) {
    p = dialog->margins[i]->text; value = 0;
    if (!*p) return FALSE;
    while (*p) {
      if (*p < '0' || *p > '9') return FALSE;
      value = value * 10 + *p++ - '0';
      if (value > 100) return FALSE;
    }
    options->margins[i] = value;
  }
  return MdPdfValid(options);
}

U0 WordPdfApply(HtkCtl *button)
{
  CWordPdfDialog *dialog = button->user;
  CMdPdf options;

  if (!WordPdfRead(dialog, &options)) {
    HtkSetText(dialog->message, "Use margins from 0 to 100 mm; leave room for text.");
    return;
  }
  MemCpy(&dialog->doc->pdf, &options, sizeof(CMdPdf));
  dialog->applied = TRUE;
  HtkWindowClose(dialog->window);
}

HtkCtl *WordPdfDialog(CWordDoc *doc, CWordPdfDialog *dialog)
{
  HtkCtl *box = HtkNew(HTK_BOX), *grid = HtkNew(HTK_GRID), *row = HtkButtonBarNew, *apply;
  U8 *papers[4] = {"A4", "A5", "Letter", "Legal"};
  U8 *engines[3] = {"XeLaTeX", "PDFLaTeX", "LuaLaTeX"};
  U8 *margins[4] = {"Top margin (mm)", "Right margin (mm)", "Bottom margin (mm)", "Left margin (mm)"};
  U8 *value;
  I64 i;

  MemSet(dialog, 0, sizeof(CWordPdfDialog)); dialog->doc = doc;
  box->vertical = TRUE;
  dialog->paper = WordPdfField(grid, "Page size", HtkComboNew, 0);
  for (i = 0; i < 4; i++) HtkComboAdd(dialog->paper, papers[i]);
  dialog->paper->value = doc->pdf.paper;
  dialog->orientation = WordPdfField(grid, "Orientation", HtkComboNew, 1);
  HtkComboAdd(dialog->orientation, "Portrait"); HtkComboAdd(dialog->orientation, "Landscape");
  dialog->orientation->value = doc->pdf.landscape;
  for (i = 0; i < 4; i++) {
    value = MStrPrint("%d", doc->pdf.margins[i]);
    dialog->margins[i] = WordPdfField(grid, margins[i], HtkEntryNew(value, 3), i + 2);
    Free(value);
  }
  dialog->font_size = WordPdfField(grid, "Body font size", HtkComboNew, 6);
  HtkComboAdd(dialog->font_size, "10 pt"); HtkComboAdd(dialog->font_size, "11 pt");
  HtkComboAdd(dialog->font_size, "12 pt"); dialog->font_size->value = doc->pdf.font_size - 10;
  dialog->engine = WordPdfField(grid, "PDF engine", HtkComboNew, 7);
  for (i = 0; i < 3; i++) HtkComboAdd(dialog->engine, engines[i]);
  dialog->engine->value = doc->pdf.engine;
  HtkAdd(box, grid);
  dialog->toc = HtkCheckboxNew("Table of contents", doc->pdf.toc);
  HtkAdd(box, dialog->toc);
  dialog->message = HtkNew(HTK_LABEL);
  HtkSetText(dialog->message, "Requires Pandoc and the selected LaTeX engine.");
  HtkAdd(box, dialog->message);
  apply = HtkButtonNew("Apply"); apply->user = dialog; apply->changed = &WordPdfApply;
  HtkAdd(row, apply); HtkAdd(row, HtkDialogButton("Cancel", FALSE)); HtkAdd(box, row);
  dialog->window = HtkDialogNew("PDF settings", box); dialog->window->link = apply;
  return dialog->window;
}

Bool WordPdfSettings(CWordDoc *doc)
{
  CWordPdfDialog dialog;
  HtkCtl *window = WordPdfDialog(doc, &dialog);

  HtkSetFocus(dialog.paper); HtkModalFor(window, doc->window); HtkDestroy(window);
  return dialog.applied;
}

U0 WordExport(CWordDoc *doc, I64 format)
{
  U8 *path, *resources;
  CStrBuf output;
  CStrs directory;
  Bool ok;

  if (format == 3 && !WordPdfSettings(doc)) return;
  if (format == 3) path = HtkPromptFor(doc->window, "Export PDF", "Destination (.pdf):", "");
  else path = HtkPromptFor(doc->window, "Export", "Destination (.html, .gem or .txt):", "");
  if (!path || !*path) { Free(path); return; }
  if (FileSamePath(path, doc->path.a)) {
    HtkMsgBoxFor(doc->window, "Export", "Choose a different path from the Markdown source.");
    Free(path); return;
  }
  if (FileExists(path) && !HtkConfirmFor(doc->window, "Replace export", "Replace the existing file?")) {
    Free(path); return;
  }
  StrBufInit(&output);
  if (format == 3) {
    StrsInitS(&directory, "."); resources = WordResolve(doc, &directory);
    ok = MdPdfExport(&doc->edit.text, path, resources, &doc->pdf, &output);
    Free(resources);
  } else {
    MarkdownExport(&doc->edit.text, &output, format);
    ok = FileReplace(path, &output);
  }
  if (ok) HtkNotify("Export saved", 2000);
  else if (format == 3) HtkMsgBoxFor(doc->window, "PDF export failed", output.a);
  else HtkMsgBoxFor(doc->window, "Export failed", "Check the destination and permissions.");
  StrBufFini(&output);
  Free(path);
}

class CWordSearch
{
  CWordDoc *doc;
  HtkCtl *window;
  HtkCtl *query;
  HtkCtl *replacement;
  HtkCtl *replace_toggle;
  HtkCtl *all;
  HtkCtl *replace_box;
  HtkCtl *run;
  HtkCtl *message;
};

U0 WordSearchApply(HtkCtl *button)
{
  CWordSearch *search = button->user(CWordSearch *);
  CEdit *edit = &search->doc->edit;
  CStrs query, replacement;
  I64 a, b, count = 0;
  U8 *message;

  StrsInitS(&query, search->query->text);
  StrsInitS(&replacement, search->replacement->text);
  if (StrsEmpty(&query)) { HtkSetText(search->message, "Enter text to find."); return; }
  if (!search->replace_toggle->value) {
    if (EditFind(edit, &query)) HtkSetText(search->message, "Match selected.");
    else HtkSetText(search->message, "Text not found.");
  } else {
    if (edit->readonly) { HtkSetText(search->message, "Enable Editable to replace text."); return; }
    if (search->all->value) count = EditReplaceAll(edit, &query, &replacement);
    else {
      EditSelection(edit, &a, &b);
      if (b - a != StrsLen(&query) || MemCmp(edit->text.a + a, query.a, b - a)) {
        if (EditFind(edit, &query)) EditSelection(edit, &a, &b);
        else b = a;
      }
      if (b > a && EditReplace(edit, a, b, &replacement)) count = 1;
    }
    message = MStrPrint("Replaced %d matches.", count);
    HtkSetText(search->message, message); Free(message);
  }
  HtkMdChanged(search->doc->view);
}

U0 WordSearchMode(HtkCtl *toggle)
{
  CWordSearch *search = toggle->user(CWordSearch *);
  HtkCtl *content = HtkWindowContent(search->window);
  U8 *label = "Find next";

  search->replace_box->hidden = !search->replace_toggle->value;
  if (search->replace_toggle->value) {
    label = "Replace";
    if (search->all->value) label = "Replace all";
  }
  HtkSetText(search->run, label);
  HtkMeasureCtl(content);
  search->window->h = content->ph + 2;
  HtkWindowLayout(search->window);
  htk_dirty = TRUE;
}

HtkCtl *WordSearchDialog(CWordDoc *doc, CWordSearch *search)
{
  HtkCtl *box = HtkDialogBody("Find text (literal, case sensitive; wraps):");
  HtkCtl *row = HtkButtonBarNew;

  search->doc = doc;
  search->query = HtkEntryNew(""); search->query->low = 40;
  search->query->user = search; search->query->submit = &WordSearchApply;
  HtkAdd(box, search->query);
  search->replace_toggle = HtkCheckboxNew("Replace", FALSE);
  search->replace_toggle->user = search; search->replace_toggle->changed = &WordSearchMode;
  HtkAdd(box, search->replace_toggle);
  search->replace_box = HtkDialogBody("Replace with (empty deletes matches):");
  search->replace_box->hidden = TRUE;
  search->replacement = HtkEntryNew("");
  search->replacement->user = search; search->replacement->submit = &WordSearchApply;
  HtkAdd(search->replace_box, search->replacement);
  search->all = HtkCheckboxNew("Replace all matches", FALSE);
  search->all->user = search; search->all->changed = &WordSearchMode;
  HtkAdd(search->replace_box, search->all);
  HtkAdd(box, search->replace_box);
  search->message = HtkNew(HTK_LABEL); HtkSetText(search->message, " ");
  HtkAdd(box, search->message);
  search->run = HtkButtonNew("Find next");
  search->run->user = search; search->run->changed = &WordSearchApply;
  HtkAdd(row, search->run);
  HtkAdd(row, HtkDialogButton("Close", FALSE));
  HtkAdd(box, row);
  search->window = HtkDialogNew("Find / replace", box);
  search->window->link = search->run;
  return search->window;
}

U0 WordSearch(CWordDoc *doc)
{
  CWordSearch search;
  HtkCtl *window = WordSearchDialog(doc, &search);

  HtkSetFocus(search.query);
  HtkModalFor(window, doc->window);
  HtkDestroy(window);
}

U0 WordAction(CWordDoc *doc, I64 action)
{
  U8 *text = NULL, *prefix, *found, *names[FONT_STYLE_COUNT];
  CStrs slice;
  I64 i, a, b, size, rgb;
  CEdit *edit = &doc->edit;
  CHtkMarkdown *view = doc->view->data(CHtkMarkdown *);
  I64 revision = edit->revision, cursor = edit->cursor, anchor = edit->anchor;

  edit->typing = FALSE;
  if (action == WORD_QUIT) { HtkQuit; return; }
  if (action == WORD_NEW) { WordNew(doc->app); return; }
  if (action == WORD_OPEN) {
    text = HtkFilePickFor(doc->window);
    if (text) WordNew(doc->app, text);
    Free(text); return;
  }
  if (action == WORD_SAVE) { WordSave(doc); return; }
  if (action == WORD_SAVE_AS) { WordSave(doc, TRUE); return; }
  if (action == WORD_CLOSE) { HtkWindowClose(doc->window); return; }
  if (action >= WORD_HTML && action <= WORD_TEXT) { WordExport(doc, action - WORD_HTML); return; }
  if (action == WORD_PDF) { WordExport(doc, 3); return; }
  if (action == WORD_PDF_SETTINGS) { WordPdfSettings(doc); return; }
  if (action == WORD_SOURCE || action == WORD_EDITABLE) {
    i = HTK_MD_SOURCE;
    if (action == WORD_EDITABLE) i = HTK_MD_READ;
    HtkMarkdownMode(doc->view, view->mode ^ i);
  } else if (action == WORD_VIM) HtkVimSet(!doc->view->vim_mode);
  else if (action == WORD_LINES) view->line_numbers = !view->line_numbers;
  else if (action == WORD_RULER_TOP) view->ruler_top = !view->ruler_top;
  else if (action == WORD_RULER_LEFT) view->ruler_left = !view->ruler_left;
  else if (action == WORD_WIDTH || action == WORD_PAGE_SIZE) {
    prefix = "Column width (0 = window width):";
    i = view->column_width;
    if (action == WORD_PAGE_SIZE) { prefix = "Lines per page (5-200):"; i = view->page_lines; }
    text = MStrPrint("%d", i);
    found = HtkPromptFor(doc->window, "Document layout", prefix, text);
    Free(text);
    if (found) {
      i = 0;
      for (a = 0; found[a] >= '0' && found[a] <= '9'; a++)
        i = MinI64(1001, i * 10 + found[a] - '0');
      if (action == WORD_WIDTH) view->column_width = MaxI64(0, MinI64(1000, i));
      else view->page_lines = MaxI64(5, MinI64(200, i));
      Free(found);
    }
  } else if (action >= WORD_CONTINUOUS && action <= WORD_SECTION) {
    view->layout = action - WORD_CONTINUOUS;
    view->section_at = edit->cursor;
    doc->view->top = 0;
  } else if (action == WORD_PREV_SECTION || action == WORD_NEXT_SECTION) {
    CStrs section;
    MdSection(&edit->text, view->section_at, &section);
    i = MaxI64(0, section.a - edit->text.a - 1);
    if (action == WORD_NEXT_SECTION) i = section.b - edit->text.a;
    if (i < StrsLen(&edit->text)) {
      view->section_at = i;
      MdSection(&edit->text, i, &section);
      edit->cursor = section.a - edit->text.a;
      edit->anchor = -1;
    }
  } else if (action == WORD_COPY) HtkMdCopy(doc->view);
  else if (action == WORD_ALL) { edit->anchor = 0; edit->cursor = StrsLen(&edit->text); }
  else if (action == WORD_OUTLINE) {
    doc->outline_hidden = !doc->outline_hidden;
    doc->outline->hidden = doc->outline_hidden;
  } else if (action == WORD_FIT) { view->fit = !view->fit; view->left = 0; }
  else if (action == WORD_LINK_NEW || action == WORD_LINK_REPLACE) {
    WordFollow(doc, action == WORD_LINK_REPLACE); return;
  } else if (action == WORD_LINK_SYSTEM) WordSystem(doc);
  else if (action == WORD_LINK_COPY) HtkClipboardSetStrs(&doc->target);
  else if (action == WORD_FIND) {
    WordSearch(doc);
  } else if (edit->readonly) {
    HtkNotify("Enable Editable to change the document", 2000);
    return;
  } else if (action == WORD_HISTORY) HtkHistoryFor(doc->window, edit);
  else if (action == WORD_UNDO || action == WORD_REDO) EditUndo(edit, action == WORD_REDO);
  else if (action == WORD_CUT) HtkMdCopy(doc->view, TRUE);
  else if (action == WORD_PASTE) { HtkClipboardGet(&slice); EditInsert(edit, &slice); }
  else if (action >= WORD_ALIGN && action < WORD_ALIGN + 4) MdEditAlign(edit, action - WORD_ALIGN);
  else if (action == WORD_BOLD) WordWrap(doc, "**", "**");
  else if (action == WORD_ITALIC) WordWrap(doc, "*", "*");
  else if (action == WORD_UNDERLINE) WordWrap(doc, "<u>", "</u>");
  else if (action == WORD_CODE) WordWrap(doc, "`", "`");
  else if (action == WORD_CODE_BLOCK) WordWrap(doc, "\n```\n", "\n```\n");
  else if (action == WORD_RULE || action == WORD_PAGE_BREAK) {
    prefix = "\n\n---\n\n";
    if (action == WORD_PAGE_BREAK) prefix = "\n\n<!-- pagebreak -->\n\n";
    StrsInitS(&slice, prefix);
    EditInsert(edit, &slice);
  }
  else if (action == WORD_HEADING || action == WORD_LIST || action == WORD_QUOTE) {
    a = edit->cursor;
    while (a > 0 && edit->text.a[a - 1] != '\n') a--;
    prefix = "# ";
    if (action == WORD_LIST) prefix = "- ";
    if (action == WORD_QUOTE) prefix = "> ";
    StrsInitS(&slice, prefix);
    EditReplace(edit, a, a, &slice);
  } else if (action == WORD_FG || action == WORD_BG) {
    rgb = HtkColorPick("Text color", 0x80C0FF);
    if (rgb >= 0) {
      prefix = "color";
      if (action == WORD_BG) prefix = "background-color";
      text = MStrPrint("<span style=\"%s:#%06X\">", prefix, rgb);
      WordWrap(doc, text, "</span>");
      Free(text);
    }
  } else if (action == WORD_FONT) {
    for (i = 0; i < FONT_STYLE_COUNT; i++) names[i] = FontStyleName(i);
    i = HtkChoiceFor(doc->window, "Unicode text style", names, FONT_STYLE_COUNT, 2);
    EditSelection(edit, &a, &b);
    if (i == FONT_STYLE_UNDERLINE) WordWrap(doc, "<u>", "</u>");
    else if (i == FONT_STYLE_STRIKETHROUGH) WordWrap(doc, "~~", "~~");
    else if (i >= 0 && a != b) {
      StrsInit(&slice, edit->text.a + a, edit->text.a + b);
      size = FontConvert(&slice, i, NULL, 0);
      if (size >= 0) {
        text = MAlloc(size);
        FontConvert(&slice, i, text, size);
        StrsInitN(&slice, text, size);
        EditInsert(edit, &slice);
        Free(text);
      }
    }
  } else if (action == WORD_EMOJI) {
    text = HtkEmojiPick(doc->window);
    if (text) { StrsInitS(&slice, text); EditInsert(edit, &slice); Free(text); }
  } else if (action == WORD_LINK || action == WORD_IMAGE || action == WORD_LINK_EDIT)
    WordLinkEdit(doc, action == WORD_LINK_EDIT, action == WORD_IMAGE);
  else if (action >= WORD_TABLE && action <= WORD_TABLE + MD_TABLE_RIGHT) {
    if (!MdEditTable(edit, action - WORD_TABLE)) HtkNotify("This table action is unavailable at the cursor", 2500);
  } else if (action >= WORD_BORDER && action < WORD_BORDER + 4)
    MdEditTable(edit, MD_TABLE_BORDER, action - WORD_BORDER);
  if (doc->view->vim_visual && (edit->revision != revision ||
    edit->cursor != cursor || edit->anchor != anchor)) {
    doc->view->vim_visual = 0; doc->view->vim_pending = 0;
  }
  HtkMdChanged(doc->view);
  HtkSetFocus(doc->view);
}

Bool WordKey(HtkCtl *window, CTermEvent *e)
{
  CWordDoc *doc = window->user(CWordDoc *);
  I64 action = 0;

  if (htk_focus == doc->view && HtkVimControl(doc->view, e))
    return HtkMdKey(doc->view, e);
  if (e->mods & TERM_MOD_CTRL) {
    if (e->key == 'n') action = WORD_NEW;
    if (e->key == 'o') action = WORD_OPEN;
    if (e->key == 's') {
      action = WORD_SAVE;
      if (e->mods & TERM_MOD_SHIFT) action = WORD_SAVE_AS;
    }
    if (e->key == 'w') action = WORD_CLOSE;
    if (e->key == 'q') action = WORD_QUIT;
    if (e->key == 'f') action = WORD_FIND;
    if (e->key == 'b') action = WORD_BOLD;
    if (e->key == 'i') action = WORD_ITALIC;
    if (e->key == 'u') action = WORD_UNDERLINE;
    if (e->key == 'c') action = WORD_COPY;
    if (e->key == 'x') action = WORD_CUT;
    if (e->key == 'v') action = WORD_PASTE;
    if (e->key == 'a') action = WORD_ALL;
    if (e->key == 'z') action = WORD_UNDO;
    if (e->key == 'y' || e->key == 'z' && e->mods & TERM_MOD_SHIFT) action = WORD_REDO;
  }
  if (!action) return FALSE;
  WordAction(doc, action);
  return TRUE;
}

CWordDoc *WordNew(CWordApp *app, U8 *path=NULL)
{
  CWordDoc *doc = CAlloc(sizeof(CWordDoc));
  HtkCtl *box, *bar, *split, *menu, *sub;
  CHtkMarkdown *view;
  I64 i;
  U8 *edit_labels[5] = {"Undo", "Redo", "Cut", "Copy", "Paste"};
  I64 edit_actions[5] = {WORD_UNDO, WORD_REDO, WORD_CUT, WORD_COPY, WORD_PASTE};
  U8 *format_labels[8] = {"Bold", "Italic", "Underline", "Text color...",
    "Background color...", "Font...", "Emoji...", "Link..."};
  I64 format_actions[8] = {WORD_BOLD, WORD_ITALIC, WORD_UNDERLINE, WORD_FG,
    WORD_BG, WORD_FONT, WORD_EMOJI, WORD_LINK};
  U8 *tools[6] = {"B", "I", "U", "☺", "↗", "⌕"};
  I64 tool_actions[6] = {WORD_BOLD, WORD_ITALIC, WORD_UNDERLINE, WORD_EMOJI,
    WORD_LINK, WORD_FIND};
  U8 *tables[8] = {"Insert table", "Add row", "Add column", "Delete row",
    "Delete column", "Align left", "Align center", "Align right"};
  U8 *borders[4] = {"Single", "Round", "ASCII", "None"};

  doc->app = app;
  EditInit(&doc->edit);
  MdPdfDefault(&doc->pdf);
  StrBufInit(&doc->path);
  StrBufInit(&doc->target);
  doc->outline_revision = -1;
  doc->window = HtkWindowNew("Untitled.md", MinI64(100, TermWidth), TermHeight - 2);
  HtkWindowSetSizeLimits(doc->window, 48, 12);
  doc->window->y = MaxI64(0, MinI64(doc->window->y, TermHeight - 1 - doc->window->h));
  doc->window->user = doc;
  doc->window->keyfn = &WordKey;
  doc->window->closing = &WordClosing;
  doc->window->submit = &WordClosed;
  menu = HtkMenuNew(doc->window, "File");
  WordItem(doc, menu, "New           Ctrl-N", WORD_NEW);
  WordItem(doc, menu, "Open...       Ctrl-O", WORD_OPEN);
  HtkMenuSeparator(menu);
  WordItem(doc, menu, "Save          Ctrl-S", WORD_SAVE);
  WordItem(doc, menu, "Save as...    Ctrl-Shift-S", WORD_SAVE_AS);
  sub = HtkSubMenu(menu, "Export");
  WordItem(doc, sub, "HTML...", WORD_HTML);
  WordItem(doc, sub, "Gemtext (.gem)...", WORD_GEM);
  WordItem(doc, sub, "Plain text...", WORD_TEXT);
  WordItem(doc, sub, "PDF...", WORD_PDF);
  HtkMenuSeparator(sub);
  WordItem(doc, sub, "PDF settings...", WORD_PDF_SETTINGS);
  HtkMenuSeparator(menu);
  WordItem(doc, menu, "Close         Ctrl-W", WORD_CLOSE);
  WordItem(doc, menu, "Quit          Ctrl-Q", WORD_QUIT);
  menu = HtkMenuNew(doc->window, "Edit");
  for (i = 0; i < 2; i++) WordItem(doc, menu, edit_labels[i], edit_actions[i]);
  WordItem(doc, menu, "History...", WORD_HISTORY);
  HtkMenuSeparator(menu);
  for (i = 2; i < 5; i++) WordItem(doc, menu, edit_labels[i], edit_actions[i]);
  WordItem(doc, menu, "Select all    Ctrl-A", WORD_ALL);
  HtkMenuSeparator(menu);
  WordItem(doc, menu, "Find / replace... Ctrl-F", WORD_FIND);
  HtkMenuSeparator(menu);
  WordItem(doc, menu, "Toggle Vim mode", WORD_VIM);
  menu = HtkMenuNew(doc->window, "Format");
  for (i = 0; i < 8; i++) WordItem(doc, menu, format_labels[i], format_actions[i]);
  HtkMenuSeparator(menu);
  sub = HtkSubMenu(menu, "Paragraph alignment");
  WordItem(doc, sub, "Left", WORD_ALIGN + MD_ALIGN_LEFT);
  WordItem(doc, sub, "Center", WORD_ALIGN + MD_ALIGN_CENTER);
  WordItem(doc, sub, "Right", WORD_ALIGN + MD_ALIGN_RIGHT);
  WordItem(doc, sub, "Justify (wide)", WORD_ALIGN + MD_ALIGN_JUSTIFY);
  HtkMenuSeparator(menu);
  WordItem(doc, menu, "Image...", WORD_IMAGE);
  WordItem(doc, menu, "Heading", WORD_HEADING);
  WordItem(doc, menu, "Bullet list", WORD_LIST);
  WordItem(doc, menu, "Quote", WORD_QUOTE);
  WordItem(doc, menu, "Inline code", WORD_CODE);
  WordItem(doc, menu, "Code block", WORD_CODE_BLOCK);
  WordItem(doc, menu, "Line separator", WORD_RULE);
  WordItem(doc, menu, "Page break", WORD_PAGE_BREAK);
  menu = HtkMenuNew(doc->window, "Table");
  for (i = 0; i < 8; i++) {
    if (i == 5) HtkMenuSeparator(menu);
    WordItem(doc, menu, tables[i], WORD_TABLE + i);
  }
  HtkMenuSeparator(menu);
  sub = HtkSubMenu(menu, "Border style");
  for (i = 0; i < 4; i++) WordItem(doc, sub, borders[i], WORD_BORDER + i);
  WordItem(doc, menu, "Toggle fit / horizontal scroll", WORD_FIT);
  menu = HtkMenuNew(doc->window, "View");
  WordItem(doc, menu, "Toggle outline", WORD_OUTLINE);
  WordItem(doc, menu, "Toggle table fit", WORD_FIT);
  WordItem(doc, menu, "Source / rendered", WORD_SOURCE);
  WordItem(doc, menu, "Editable / read only", WORD_EDITABLE);
  HtkMenuSeparator(menu);
  WordItem(doc, menu, "Line numbers", WORD_LINES);
  WordItem(doc, menu, "Top ruler", WORD_RULER_TOP);
  WordItem(doc, menu, "Left ruler", WORD_RULER_LEFT);
  HtkMenuSeparator(menu);
  WordItem(doc, menu, "Column width...", WORD_WIDTH);
  WordItem(doc, menu, "Lines per page...", WORD_PAGE_SIZE);
  WordItem(doc, menu, "Continuous", WORD_CONTINUOUS);
  WordItem(doc, menu, "Pages", WORD_PAGES);
  WordItem(doc, menu, "Current section", WORD_SECTION);
  HtkMenuSeparator(menu);
  WordItem(doc, menu, "Previous section", WORD_PREV_SECTION);
  WordItem(doc, menu, "Next section", WORD_NEXT_SECTION);
  box = HtkNew(HTK_BOX);
  box->vertical = TRUE;
  bar = HtkToolbarNew;
  for (i = 0; i < 6; i++) WordItem(doc, bar, tools[i], tool_actions[i]);
  doc->vim = WordItem(doc, bar, "V", WORD_VIM);
  doc->alignment[MD_ALIGN_LEFT] = WordItem(doc, bar, "L", WORD_ALIGN + MD_ALIGN_LEFT);
  doc->alignment[MD_ALIGN_CENTER] = WordItem(doc, bar, "C", WORD_ALIGN + MD_ALIGN_CENTER);
  doc->alignment[MD_ALIGN_RIGHT] = WordItem(doc, bar, "R", WORD_ALIGN + MD_ALIGN_RIGHT);
  doc->alignment[MD_ALIGN_JUSTIFY] = WordItem(doc, bar, "J", WORD_ALIGN + MD_ALIGN_JUSTIFY);
  HtkAdd(box, bar);
  split = HtkNew(HTK_SPLIT);
  split->expand = TRUE;
  doc->outline = HtkTreeNew;
  doc->outline->user = doc;
  doc->outline->changed = &WordOutlineHit;
  doc->view = HtkMarkdownNew(&doc->edit);
  doc->view->user = doc;
  doc->view->submit = &WordRefresh;
  view = doc->view->data;
  view->linkfn = &WordLinkMenu;
  HtkAdd(split, doc->outline);
  HtkAdd(split, doc->view);
  HtkAdd(box, split);
  doc->status = HtkStatusbarNew("");
  doc->status->bottom = TRUE;
  doc->stats = HtkNew(HTK_LABEL);
  doc->stats->expand = TRUE;
  HtkAdd(doc->status, doc->stats);
  doc->outline_button = WordItem(doc, doc->status, "Outline", WORD_OUTLINE);
  doc->source = WordItem(doc, doc->status, "Render", WORD_SOURCE);
  doc->editable = WordItem(doc, doc->status, "Edit", WORD_EDITABLE);
  HtkAdd(box, doc->status);
  HtkAdd(doc->window, box);
  doc->link_menu = HtkContextMenuNew;
  doc->link_menu->parent = doc->window;
  WordItem(doc, doc->link_menu, "Open in new window", WORD_LINK_NEW);
  WordItem(doc, doc->link_menu, "Replace this window", WORD_LINK_REPLACE);
  HtkMenuSeparator(doc->link_menu);
  WordItem(doc, doc->link_menu, "Edit link...", WORD_LINK_EDIT);
  WordItem(doc, doc->link_menu, "Open with system handler", WORD_LINK_SYSTEM);
  WordItem(doc, doc->link_menu, "Copy target", WORD_LINK_COPY);
  doc->next = app->docs;
  app->docs = doc;
  if (path && !WordLoad(doc, path)) { HtkWindowClose(doc->window); return NULL; }
  WordRefresh(doc->view);
  HtkSetFocus(doc->view);
  return doc;
}

U0 WordAppNew(I64 data)
{
  WordNew(data(CWordApp *));
}

U0 WordAppOpen(I64 data)
{
  U8 *path = HtkFilePickFor(HtkTop);

  if (path) WordNew(data(CWordApp *), path);
  Free(path);
}

U0 WordCopy(I64 data)
{
  CWordApp *app = data;
  CWordDoc *doc = app->docs;

  while (doc) {
    if (HtkTop == doc->window) { HtkMdCopy(doc->view); return; }
    doc = doc->next;
  }
  HtkCopySelection(htk_focus);
}

U0 Main(I64 argc, I64 *argv)
{
  CWordApp app;
  CWordDoc *doc;
  I64 i;

  if (!HtkInit) { "word needs an interactive terminal\n"; return; }
  HtkCtrlCHandler(&WordCopy, &app);
  HtkCtrlCSet(HTK_CTRLC_CALLBACK);
  HtkAppRegister("New Markdown", &WordAppNew, &app);
  HtkAppRegister("Open Markdown...", &WordAppOpen, &app);
  for (i = 0; i < argc; i++) WordNew(&app, argv[i](U8 *));
  if (!argc) WordNew(&app);
  HtkMain;
  HtkFini;
  while (app.docs) {
    doc = app.docs;
    HtkListUnlink(&htk_windows, doc->window);
    WordDispose(doc, 0);
  }
}

#ifndef WORD_TEST
Main(argc, argv);
#endif
