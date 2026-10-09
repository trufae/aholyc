// HolyC Markdown word processor. Build: aholyc examples/word.hc -o word
#define TERM_CTRL_Z_KEY
#ifndef WORD_TEST
#define HTK_NATIVE_CLIPBOARD
#endif
#include "../lib/htk/markdown.hc"
#include "../lib/htk/history.hc"
#include "../lib/htk/filepick.hc"
#include "../lib/text/md_export.hc"
#include "../lib/text/font.hc"
#include "../lib/io/replace.hc"
extern I64 system(U8 *command);
#ifdef IS_WINDOWS
extern U8 *LoadLibraryA(U8 *name);
extern U8 *GetProcAddress(U8 *module, U8 *name);
extern I64 FreeLibrary(U8 *module);
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

class CWordApp;
class CWordDoc
{
  CWordDoc *next;
  CWordApp *app;
  CEdit edit;
  HtkCtl *window;
  HtkCtl *view;
  HtkCtl *outline;
  HtkCtl *source;
  HtkCtl *editable;
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
  I64 (*open)(U0 *window, U8 *operation, U8 *file, U8 *params, U8 *dir, I64 show);
  if (module) open = GetProcAddress(module, "ShellExecuteA");
  if (!open || open(NULL, "open", path, NULL, NULL, 1) <= 32)
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

U0 WordExport(CWordDoc *doc, I64 format)
{
  U8 *path;
  CStrBuf output;
  Bool ok;

  path = HtkPromptFor(doc->window, "Export", "Destination (.html, .gem or .txt):", "");
  if (!path || !*path) { Free(path); return; }
  if (FileSamePath(path, doc->path.a)) {
    HtkMsgBoxFor(doc->window, "Export", "Choose a different path from the Markdown source.");
    Free(path); return;
  }
  if (FileExists(path) && !HtkConfirmFor(doc->window, "Replace export", "Replace the existing file?")) {
    Free(path); return;
  }
  StrBufInit(&output);
  MarkdownExport(&doc->edit.text, &output, format);
  ok = FileReplace(path, &output);
  if (ok) HtkNotify("Export saved", 2000);
  else HtkMsgBoxFor(doc->window, "Export failed", "Check the destination and permissions.");
  StrBufFini(&output);
  Free(path);
}

U0 WordAction(CWordDoc *doc, I64 action)
{
  U8 *text = NULL, *prefix, *found, *names[FONT_STYLE_COUNT];
  CStrs slice;
  I64 i, a, b, size, rgb;
  CEdit *edit = &doc->edit;
  CHtkMarkdown *view = doc->view->data(CHtkMarkdown *);

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
  if (action == WORD_SOURCE || action == WORD_EDITABLE) {
    i = HTK_MD_SOURCE;
    if (action == WORD_EDITABLE) i = HTK_MD_READ;
    HtkMarkdownMode(doc->view, view->mode ^ i);
  } else if (action == WORD_LINES) view->line_numbers = !view->line_numbers;
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
    text = HtkPromptFor(doc->window, "Find", "Text (wraps at end):");
    if (text && *text) {
      size = StrLen(text);
      found = MemMem(edit->text.a + edit->cursor, StrsLen(&edit->text) - edit->cursor, text, size);
      if (!found) found = MemMem(edit->text.a, StrsLen(&edit->text), text, size);
      if (found) { edit->anchor = found - edit->text.a; edit->cursor = edit->anchor + size; }
      else HtkNotify("Text not found", 2000);
    }
    Free(text);
  } else if (edit->readonly) {
    HtkNotify("Enable Editable to change the document", 2000);
    return;
  } else if (action == WORD_HISTORY) HtkHistoryFor(doc->window, edit);
  else if (action == WORD_UNDO || action == WORD_REDO) EditUndo(edit, action == WORD_REDO);
  else if (action == WORD_CUT) HtkMdCopy(doc->view, TRUE);
  else if (action == WORD_PASTE) { HtkClipboardGet(&slice); EditInsert(edit, &slice); }
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
  HtkMdChanged(doc->view);
  HtkSetFocus(doc->view);
}

Bool WordKey(HtkCtl *window, CTermEvent *e)
{
  CWordDoc *doc = window->user(CWordDoc *);
  I64 action = 0;

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
  U8 *labels[19] = {"New", "Open", "Save", "Undo", "Redo", "Cut", "Copy", "Paste",
    "B", "I", "U", "FG", "BG", "Font", "Emoji", "Link", "Table", "Find", "TOC"};
  I64 actions[19] = {WORD_NEW, WORD_OPEN, WORD_SAVE, WORD_UNDO, WORD_REDO,
    WORD_CUT, WORD_COPY, WORD_PASTE, WORD_BOLD, WORD_ITALIC, WORD_UNDERLINE,
    WORD_FG, WORD_BG, WORD_FONT, WORD_EMOJI, WORD_LINK, WORD_TABLE, WORD_FIND, WORD_OUTLINE};
  U8 *tables[8] = {"Insert table", "Add row", "Add column", "Delete row",
    "Delete column", "Align left", "Align center", "Align right"};
  U8 *borders[4] = {"Single", "Round", "ASCII", "None"};

  doc->app = app;
  EditInit(&doc->edit);
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
  WordItem(doc, menu, "Save          Ctrl-S", WORD_SAVE);
  WordItem(doc, menu, "Save as...    Ctrl-Shift-S", WORD_SAVE_AS);
  sub = HtkSubMenu(menu, "Export");
  WordItem(doc, sub, "HTML...", WORD_HTML);
  WordItem(doc, sub, "Gemtext (.gem)...", WORD_GEM);
  WordItem(doc, sub, "Plain text...", WORD_TEXT);
  WordItem(doc, menu, "Close         Ctrl-W", WORD_CLOSE);
  WordItem(doc, menu, "Quit          Ctrl-Q", WORD_QUIT);
  menu = HtkMenuNew(doc->window, "Edit");
  for (i = 3; i < 8; i++) WordItem(doc, menu, labels[i], actions[i]);
  WordItem(doc, menu, "History...", WORD_HISTORY);
  WordItem(doc, menu, "Select all    Ctrl-A", WORD_ALL);
  WordItem(doc, menu, "Find...       Ctrl-F", WORD_FIND);
  menu = HtkMenuNew(doc->window, "Format");
  for (i = 8; i < 16; i++) WordItem(doc, menu, labels[i], actions[i]);
  WordItem(doc, menu, "Image...", WORD_IMAGE);
  WordItem(doc, menu, "Heading", WORD_HEADING);
  WordItem(doc, menu, "Bullet list", WORD_LIST);
  WordItem(doc, menu, "Quote", WORD_QUOTE);
  WordItem(doc, menu, "Inline code", WORD_CODE);
  WordItem(doc, menu, "Code block", WORD_CODE_BLOCK);
  WordItem(doc, menu, "Line separator", WORD_RULE);
  WordItem(doc, menu, "Page break", WORD_PAGE_BREAK);
  menu = HtkMenuNew(doc->window, "Table");
  for (i = 0; i < 8; i++) WordItem(doc, menu, tables[i], WORD_TABLE + i);
  sub = HtkSubMenu(menu, "Border style");
  for (i = 0; i < 4; i++) WordItem(doc, sub, borders[i], WORD_BORDER + i);
  WordItem(doc, menu, "Toggle fit / horizontal scroll", WORD_FIT);
  menu = HtkMenuNew(doc->window, "View");
  WordItem(doc, menu, "Toggle outline", WORD_OUTLINE);
  WordItem(doc, menu, "Toggle table fit", WORD_FIT);
  WordItem(doc, menu, "Source / rendered", WORD_SOURCE);
  WordItem(doc, menu, "Editable / read only", WORD_EDITABLE);
  WordItem(doc, menu, "Line numbers", WORD_LINES);
  WordItem(doc, menu, "Top ruler", WORD_RULER_TOP);
  WordItem(doc, menu, "Left ruler", WORD_RULER_LEFT);
  WordItem(doc, menu, "Column width...", WORD_WIDTH);
  WordItem(doc, menu, "Lines per page...", WORD_PAGE_SIZE);
  WordItem(doc, menu, "Continuous", WORD_CONTINUOUS);
  WordItem(doc, menu, "Pages", WORD_PAGES);
  WordItem(doc, menu, "Current section", WORD_SECTION);
  WordItem(doc, menu, "Previous section", WORD_PREV_SECTION);
  WordItem(doc, menu, "Next section", WORD_NEXT_SECTION);
  box = HtkNew(HTK_BOX);
  box->vertical = TRUE;
  bar = HtkNew(HTK_FLOW);
  doc->source = WordItem(doc, bar, "Source", WORD_SOURCE);
  doc->editable = WordItem(doc, bar, "Editable", WORD_EDITABLE);
  for (i = 0; i < 19; i++) WordItem(doc, bar, labels[i], actions[i]);
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
  HtkAdd(doc->window, box);
  doc->link_menu = HtkContextMenuNew;
  doc->link_menu->parent = doc->window;
  WordItem(doc, doc->link_menu, "Open in new window", WORD_LINK_NEW);
  WordItem(doc, doc->link_menu, "Replace this window", WORD_LINK_REPLACE);
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
