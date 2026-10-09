// A small Vim-style source editor built from HTK. See doc/vim.md.
#define UI_HTK_VIMODE
#define TERM_CTRL_Z_KEY
#ifndef VIM_TEST
#define HTK_NATIVE_CLIPBOARD
#endif
#include "../lib/htk/markdown.hc"
#include "../lib/io/replace.hc"

#ifdef IS_WINDOWS
extern U32 GetFileAttributesA(U8 *path);
#else
extern I32 access(U8 *path, I32 mode);
#endif

class CVimApp;
class CVimBuffer
{
  CVimBuffer *next;
  CVimApp *app;
  CEdit edit;
  CStrBuf path;
  I64 id;
};
class CVimPane
{
  CVimPane *next;
  CVimApp *app;
  CVimBuffer *buffer;
  HtkCtl *ctl;
  I64 cursor, anchor;
};
class CVimApp
{
  CVimBuffer *buffers;
  CVimPane *panes;
  CVimPane *active;
  HtkCtl *window;
  HtkCtl *body;
  HtkCtl *workspace;
  HtkCtl *status;
  HtkCtl *command;
  HtkCtl *commandbar;
  HtkCtl *prompt_label;
  CStrBuf search, message;
  I64 serial, prefix, prompt;
  Bool force_close, search_back;
};

Bool VimCommand(CVimApp *app, U8 *source);
U0 VimPrompt(CVimApp *app, I64 prompt=':', U8 *initial="");
U0 VimActivate(CVimPane *pane);
U0 VimPaneChanged(HtkCtl *c);
Bool VimPaneKey(HtkCtl *c, CTermEvent *e);
U0 VimPaneMouse(HtkCtl *c);

U0 VimStatus(CVimApp *app)
{
  CVimPane *pane = app->active;
  CEdit *edit;
  I64 line = 1, column = 0, at, caret;
  U8 *mode = "NORMAL", *name, *dirty = "", *text;

  if (!pane) { HtkSetText(app->status, app->message.a); return; }
  edit = &pane->buffer->edit; name = pane->buffer->path.a;
  caret = HtkVimCaret(pane->ctl, edit->cursor);
  for (at = 0; at < caret; at++) if (edit->text.a[at] == '\n') line++;
  for (at = HtkVimLine(edit, caret); at < caret; at = EditNext(edit, at, 1))
    column = HtkVimColumn(edit, at, column);
  if (!*name) name = "[No Name]";
  if (edit->revision != edit->saved) dirty = " [+]";
  if (!pane->ctl->vim_mode) mode = "EDIT";
  else if (pane->ctl->vim_insert) mode = "INSERT";
  else if (pane->ctl->vim_visual == 1) mode = "VISUAL";
  else if (pane->ctl->vim_visual == 2) mode = "V-LINE";
  if (edit->readonly) mode = "READ";
  text = MStrPrint("%s | %d:%d | %s%s | %s", mode, line, column + 1, name, dirty, app->message.a);
  HtkSetText(app->status, text); Free(text);
}

U0 VimMessage(CVimApp *app, U8 *message)
{
  StrBufClear(&app->message); StrBufPutS(&app->message, message); VimStatus(app);
}

I64 VimBound(CEdit *edit, I64 at)
{
  at = MaxI64(0, MinI64(StrsLen(&edit->text), at));
  while (!EditBoundary(edit, at)) at--;
  return at;
}

I64 VimMark(I64 at, I64 a, I64 b, I64 size)
{
  if (at < 0 || at <= a) return at;
  if (at >= b) return at + size - (b - a);
  return a;
}

// Shared history/text, independent view positions. No document copies.
U0 VimSpliced(CEdit *edit, I64 a, I64 b, I64 size)
{
  CVimBuffer *buffer = edit->user;
  CVimPane *pane = buffer->app->panes;

  while (pane) {
    if (pane->buffer == buffer && pane != pane->app->active) {
      pane->cursor = VimMark(pane->cursor, a, b, size);
      pane->anchor = VimMark(pane->anchor, a, b, size);
      if (pane->ctl->vim_visual) {
        pane->ctl->vim_start = VimMark(pane->ctl->vim_start, a, b, size);
        pane->ctl->vim_head = VimMark(pane->ctl->vim_head, a, b, size);
      }
    }
    pane = pane->next;
  }
}

I64 VimReferences(CVimApp *app, CVimBuffer *buffer)
{
  CVimPane *pane = app->panes;
  I64 count = 0;

  while (pane) { if (pane->buffer == buffer) count++; pane = pane->next; }
  return count;
}

Bool VimModified(CVimBuffer *buffer)
{
  return buffer->edit.revision != buffer->edit.saved;
}

Bool VimAnyModified(CVimApp *app)
{
  CVimBuffer *buffer = app->buffers;

  while (buffer) { if (VimModified(buffer)) return TRUE; buffer = buffer->next; }
  return FALSE;
}

U0 VimForget(CVimApp *app, CVimBuffer *buffer)
{
  CVimBuffer **at = &app->buffers;

  while (*at && *at != buffer) at = &(*at)->next;
  if (*at) *at = buffer->next;
  EditFini(&buffer->edit); StrBufFini(&buffer->path); Free(buffer);
}

Bool VimPathExists(U8 *path)
{
  #ifdef IS_WINDOWS
  return GetFileAttributesA(path) != 0xFFFFFFFF;
  #else
  return !access(path, 0);
  #endif
}

CVimBuffer *VimBufferOpen(CVimApp *app, U8 *path=NULL)
{
  CVimBuffer *buffer = app->buffers;
  U8 *text = NULL;
  I64 size = 0;

  if (path && *path) {
    while (buffer) {
      if (FileSamePath(buffer->path.a, path)) return buffer;
      buffer = buffer->next;
    }
    text = FileRead(path, &size);
    if (!text && VimPathExists(path)) { VimMessage(app, "Cannot read file"); return NULL; }
  }
  buffer = CAlloc(sizeof(CVimBuffer));
  buffer->app = app; buffer->id = ++app->serial;
  EditInit(&buffer->edit); StrBufInit(&buffer->path);
  if (path) StrBufPutS(&buffer->path, path);
  if (text) StrBufPutN(&buffer->edit.text, text, size);
  Free(text);
  buffer->edit.user = buffer; buffer->edit.spliced = &VimSpliced;
  buffer->next = app->buffers; app->buffers = buffer;
  return buffer;
}

U0 VimActivate(CVimPane *pane)
{
  CVimApp *app = pane->app;
  CEdit *edit;

  if (app->active == pane) return;
  if (app->active) {
    edit = &app->active->buffer->edit;
    app->active->cursor = edit->cursor; app->active->anchor = edit->anchor;
    edit->typing = FALSE;
  }
  app->active = pane; app->prefix = 0;
  edit = &pane->buffer->edit;
  edit->cursor = VimBound(edit, pane->cursor);
  edit->anchor = -1;
  if (pane->anchor >= 0) edit->anchor = VimBound(edit, pane->anchor);
  edit->typing = FALSE;
  pane->ctl->vim_at = HtkVimCaret(pane->ctl, edit->cursor);
  VimStatus(app);
  htk_dirty = TRUE;
}

U0 VimFocus(CVimPane *pane)
{
  VimActivate(pane); HtkSetFocus(pane->ctl);
}

U0 VimPaneChanged(HtkCtl *c)
{
  CVimPane *pane = c->user;
  CEdit *edit = &pane->buffer->edit;

  pane->cursor = edit->cursor; pane->anchor = edit->anchor;
  VimStatus(pane->app);
  htk_dirty = TRUE;
}

U0 VimPaneDraw(HtkCtl *c)
{
  CVimPane *pane = c->user;
  CEdit *edit = &pane->buffer->edit;
  I64 cursor = edit->cursor, anchor = edit->anchor;

  if (HtkFocused(c)) VimActivate(pane);
  cursor = edit->cursor; anchor = edit->anchor;
  if (pane != pane->app->active) {
    edit->cursor = VimBound(edit, pane->cursor);
    edit->anchor = -1;
    if (pane->anchor >= 0) edit->anchor = VimBound(edit, pane->anchor);
  }
  HtkMdDraw(c);
  edit->cursor = cursor; edit->anchor = anchor;
}

CVimPane *VimPaneNew(CVimApp *app, CVimBuffer *buffer)
{
  CVimPane *pane = CAlloc(sizeof(CVimPane));
  CHtkMarkdown *view;

  pane->app = app; pane->buffer = buffer; pane->anchor = -1;
  pane->ctl = HtkMarkdownNew(&buffer->edit);
  pane->ctl->user = pane; pane->ctl->fn = &VimPaneDraw;
  pane->ctl->keyfn = &VimPaneKey; pane->ctl->changed = &VimPaneMouse;
  pane->ctl->submit = &VimPaneChanged;
  view = pane->ctl->data;
  view->mode = HTK_MD_SOURCE; view->no_wrap = TRUE; view->tab_width = 8; view->hide_status = TRUE;
  view->task_interactive = FALSE; // Source-file readonly mode stays strict.
  if (buffer->edit.readonly) view->mode |= HTK_MD_READ;
  pane->ctl->vim_mode = TRUE;
  pane->next = app->panes; app->panes = pane;
  return pane;
}

U0 VimReplaceCtl(HtkCtl *old, HtkCtl *replacement)
{
  HtkCtl **at = &old->parent->kids;

  while (*at && *at != old) at = &(*at)->sib;
  replacement->parent = old->parent; replacement->sib = old->sib;
  *at = replacement; old->parent = NULL; old->sib = NULL;
}

Bool VimSplit(CVimApp *app, Bool vertical=FALSE, U8 *path=NULL, Bool fresh=FALSE)
{
  CVimPane *old = app->active, *pane;
  CVimBuffer *buffer = old->buffer;
  HtkCtl *split;
  CHtkMarkdown *view, *prior = old->ctl->data;

  if (path && *path || fresh) buffer = VimBufferOpen(app, path);
  if (!buffer) return FALSE;
  pane = VimPaneNew(app, buffer); view = pane->ctl->data;
  view->line_numbers = prior->line_numbers; view->no_wrap = prior->no_wrap;
  if (buffer == old->buffer) {
    pane->cursor = buffer->edit.cursor; pane->ctl->top = old->ctl->top;
    view->left = prior->left;
  }
  split = HtkNew(HTK_SPLIT);
  split->vertical = !vertical; split->value = 500; split->expand = TRUE;
  VimReplaceCtl(old->ctl, split);
  HtkAdd(split, old->ctl); HtkAdd(split, pane->ctl);
  VimFocus(pane); VimMessage(app, "Ctrl-W w cycles panes; :q closes this pane");
  return TRUE;
}

U0 VimNextPane(CVimApp *app, I64 key='w')
{
  CVimPane *pane = app->panes, *last = NULL, *previous = NULL, *best = NULL;
  HtkCtl *from = app->active->ctl, *to;
  I64 dx, dy, distance, score = I64_MAX;
  Bool aligned;

  while (pane) {
    if (pane == app->active) previous = last;
    to = pane->ctl;
    dx = to->x + to->w / 2 - (from->x + from->w / 2);
    dy = to->y + to->h / 2 - (from->y + from->h / 2);
    if (pane != app->active && (key == 'h' && dx < 0 || key == 'l' && dx > 0 ||
        key == 'j' && dy > 0 || key == 'k' && dy < 0)) {
          distance = AbsI64(dx) + AbsI64(dy) * 2;
          aligned = to->x < from->x + from->w && to->x + to->w > from->x;
          if (key == 'h' || key == 'l') aligned = to->y < from->y + from->h && to->y + to->h > from->y;
          if (!aligned) distance += 1000000;
          if (distance < score) { score = distance; best = pane; }
        }
    last = pane; pane = pane->next;
  }
  if (key == 'w') {
    best = app->active->next;
    if (!best) best = app->panes;
  } else if (key == 'W') { best = previous; if (!best) best = last; }
  if (best) VimFocus(best);
}

Bool VimClosePane(CVimApp *app, CVimPane *pane, Bool force=FALSE)
{
  CVimPane **at = &app->panes, *next;
  CVimBuffer *buffer = pane->buffer;
  HtkCtl *split = pane->ctl->parent, *other;

  if (!force && VimModified(buffer) && VimReferences(app, buffer) == 1) {
    VimMessage(app, "Unsaved changes; use :w or :q!"); return FALSE;
  }
  if (split == app->workspace) {
    if (!force && VimAnyModified(app)) {
      VimMessage(app, "Unsaved buffers; use :ls, :w or :qa!"); return FALSE;
    }
    app->force_close = TRUE; HtkWindowClose(app->window); return TRUE;
  }
  other = split->kids;
  if (other == pane->ctl) other = other->sib;
  split->kids = NULL;
  VimReplaceCtl(split, other); HtkDestroy(split);
  while (*at && *at != pane) at = &(*at)->next;
  *at = pane->next;
  next = app->panes;
  if (app->active != pane) next = app->active;
  else { buffer->edit.typing = FALSE; app->active = NULL; }
  if (htk_focus == pane->ctl) htk_focus = NULL;
  HtkDestroy(pane->ctl); Free(pane);
  VimFocus(next);
  if (force && !VimReferences(app, buffer) && VimModified(buffer)) VimForget(app, buffer);
  return TRUE;
}

Bool VimWrite(CVimApp *app, U8 *path, Bool force)
{
  CVimBuffer *buffer = app->active->buffer, *other = app->buffers;
  CEdit *edit = &buffer->edit;
  U8 *message;

  if (!*path) path = buffer->path.a;
  if (!*path) { VimMessage(app, "No filename; use :w path"); return FALSE; }
  if (edit->readonly && !force) { VimMessage(app, "Read only; use :w! to write"); return FALSE; }
  while (other) {
    if (other != buffer && FileSamePath(other->path.a, path)) {
      VimMessage(app, "That file is open in another buffer"); return FALSE;
    }
    other = other->next;
  }
  if (!force && !FileSamePath(buffer->path.a, path) && VimPathExists(path)) {
    VimMessage(app, "File exists; use :w! path to overwrite"); return FALSE;
  }
  if (!FileReplace(path, &edit->text)) { VimMessage(app, "Cannot write file"); return FALSE; }
  // path can alias buffer->path.
  message = MStrPrint("Wrote %s (%d bytes)", path, StrsLen(&edit->text));
  if (path != buffer->path.a) { StrBufClear(&buffer->path); StrBufPutS(&buffer->path, path); }
  edit->saved = edit->revision; edit->typing = FALSE;
  VimMessage(app, message); Free(message);
  return TRUE;
}

U0 VimUseBuffer(CVimApp *app, CVimBuffer *buffer, Bool force)
{
  CVimPane *pane = app->active;
  CVimBuffer *old = pane->buffer;
  CHtkMarkdown *view = pane->ctl->data;

  old->edit.typing = FALSE;
  pane->buffer = buffer; view->edit = &buffer->edit;
  view->mode = HTK_MD_SOURCE;
  if (buffer->edit.readonly) view->mode |= HTK_MD_READ;
  pane->cursor = buffer->edit.cursor = 0; pane->anchor = buffer->edit.anchor = -1;
  pane->ctl->top = 0; view->left = 0; view->follow = TRUE;
  pane->ctl->vim_insert = FALSE; pane->ctl->vim_pending = 0; pane->ctl->vim_at = 0;
  pane->ctl->vim_visual = 0; pane->ctl->vim_vertical = FALSE;
  if (force && old != buffer && !VimReferences(app, old) && VimModified(old)) VimForget(app, old);
  VimStatus(app);
  htk_dirty = TRUE;
}

Bool VimCanLeave(CVimApp *app, Bool force)
{
  CVimBuffer *buffer = app->active->buffer;

  if (!force && VimModified(buffer) && VimReferences(app, buffer) == 1) {
    VimMessage(app, "Unsaved changes; use :w or add ! to discard"); return FALSE;
  }
  return TRUE;
}

Bool VimEdit(CVimApp *app, U8 *path, Bool force)
{
  CVimBuffer *buffer = app->active->buffer, *opened;
  CVimPane *pane;
  U8 *text;
  I64 size;
  Bool readonly;

  if (!*path || FileSamePath(buffer->path.a, path)) {
    if (VimModified(buffer) && !force) { VimMessage(app, "Unsaved changes; use :e! to reload"); return FALSE; }
    if (!*buffer->path.a) { VimMessage(app, "No filename"); return FALSE; }
    text = FileRead(buffer->path.a, &size);
    if (!text) { VimMessage(app, "Cannot reload file"); return FALSE; }
    readonly = buffer->edit.readonly;
    EditFini(&buffer->edit); EditInit(&buffer->edit);
    StrBufPutN(&buffer->edit.text, text, size); Free(text);
    buffer->edit.readonly = readonly;
    buffer->edit.spliced = &VimSpliced; buffer->edit.user = buffer;
    pane = app->panes;
    while (pane) {
      if (pane->buffer == buffer) {
        pane->cursor = 0; pane->anchor = -1; pane->ctl->top = 0;
        pane->ctl->vim_insert = FALSE; pane->ctl->vim_pending = 0;
        pane->ctl->vim_visual = 0; pane->ctl->vim_vertical = FALSE;
        pane->ctl->data(CHtkMarkdown *)->follow = TRUE;
      }
      pane = pane->next;
    }
  } else {
    if (!VimCanLeave(app, force)) return FALSE;
    opened = VimBufferOpen(app, path);
    if (!opened) return FALSE;
    VimUseBuffer(app, opened, force);
  }
  VimMessage(app, "File opened"); htk_dirty = TRUE; return TRUE;
}

Bool VimSet(CVimApp *app, U8 *options)
{
  U8 *copy = StrNew(options), *at, *name;
  I64 pass;
  CHtkMarkdown *view = app->active->ctl->data;
  CVimPane *pane;
  Bool on;

  // Validate the whole list before applying any setting.
  for (pass = 0; pass < 2; pass++) {
    StrCpy(copy, options); at = copy;
    while (*at) {
      while (*at == ' ' || *at == '\t') at++;
      if (!*at) break;
      name = at;
      while (*at && *at != ' ' && *at != '\t') at++;
      if (*at) *at++ = 0;
      on = TRUE;
      if (name[0] == 'n' && name[1] == 'o') { on = FALSE; name += 2; }
      if (StrCmp(name, "number") && StrCmp(name, "nu") && StrCmp(name, "wrap") &&
        StrCmp(name, "readonly") && StrCmp(name, "ro") && StrCmp(name, "vim")) {
          Free(copy); VimMessage(app, "Unknown option; use number, wrap, readonly or vim"); return FALSE;
        }
      if (!pass) goto next_option;
      if (!StrCmp(name, "number") || !StrCmp(name, "nu")) view->line_numbers = on;
      else if (!StrCmp(name, "wrap")) { view->no_wrap = !on; view->left = 0; }
      else if (!StrCmp(name, "vim")) HtkVimMode(app->active->ctl, on);
      else {
        app->active->buffer->edit.readonly = on;
        pane = app->panes;
        while (pane) {
          if (pane->buffer == app->active->buffer) {
            pane->ctl->data(CHtkMarkdown *)->mode = HTK_MD_SOURCE | (HTK_MD_READ * on);
          }
          pane = pane->next;
        }
      }
next_option:
    }
  }
  Free(copy); view->follow = TRUE; htk_dirty = TRUE;
  VimMessage(app, "Options updated"); return TRUE;
}

Bool VimNumber(U8 *text, I64 *number)
{
  I64 n = 0;

  if (!*text) return FALSE;
  while (*text) {
    if (*text < '0' || *text > '9' || n > (I64_MAX - (*text - '0')) / 10) return FALSE;
    n = n * 10 + *text++ - '0';
  }
  *number = n; return n > 0;
}

Bool VimSearch(CVimApp *app, Bool back=FALSE)
{
  CEdit *edit = &app->active->buffer->edit;
  I64 at = edit->cursor, n = StrsLen(&app->search), limit, hit = -1, pass;
  U8 *found;

  if (!n) { VimMessage(app, "No search pattern; use /text"); return FALSE; }
  for (pass = 0; pass < 2 && hit < 0; pass++) {
    if (back) {
      limit = at;
      if (pass) limit = StrsLen(&edit->text) + 1;
      for (at = 0; at < limit && at + n <= StrsLen(&edit->text); at = EditNext(edit, at, 1))
        if (!MemCmp(edit->text.a + at, app->search.a, n)) hit = at;
    } else {
      if (!pass) at = EditNext(edit, at, 1);
      else at = 0;
      found = MemMem(edit->text.a + at, StrsLen(&edit->text) - at, app->search.a, n);
      if (found) hit = found - edit->text.a;
    }
  }
  if (hit < 0) { VimMessage(app, "Pattern not found"); return FALSE; }
  edit->cursor = hit; edit->anchor = -1; edit->typing = FALSE;
  HtkMdChanged(app->active->ctl); VimMessage(app, "Match found"); return TRUE;
}

Bool VimCommand(CVimApp *app, U8 *source)
{
  U8 *copy = StrNew(source), *cmd = copy, *arg, *end;
  CVimPane *pane, *next;
  CVimBuffer *buffer;
  CEdit *edit;
  CStrBuf list;
  I64 n, at;
  Bool force = FALSE, ok = TRUE;

  while (*cmd == ':' || *cmd == ' ' || *cmd == '\t') cmd++;
  arg = cmd;
  while (*arg && *arg != ' ' && *arg != '\t') arg++;
  end = arg;
  if (*arg) *arg++ = 0;
  if (end > cmd && end[-1] == '!') { force = TRUE; end[-1] = 0; }
  while (*arg == ' ' || *arg == '\t') arg++;
  end = arg + StrLen(arg);
  while (end > arg && (end[-1] == ' ' || end[-1] == '\t')) *--end = 0;
  if (end - arg >= 2 && (*arg == '"' || *arg == '\'') && end[-1] == *arg) { arg++; end[-1] = 0; }
  app->active->buffer->edit.typing = FALSE;
  if (!*cmd) {}
  else if (!StrCmp(cmd, "sp") || !StrCmp(cmd, "split")) ok = VimSplit(app, FALSE, arg);
  else if (!StrCmp(cmd, "vs") || !StrCmp(cmd, "vsplit")) ok = VimSplit(app, TRUE, arg);
  else if (!StrCmp(cmd, "new") || !StrCmp(cmd, "vnew")) ok = VimSplit(app, !StrCmp(cmd, "vnew"), arg, TRUE);
  else if (!StrCmp(cmd, "w") || !StrCmp(cmd, "write")) ok = VimWrite(app, arg, force);
  else if (!StrCmp(cmd, "wq") || !StrCmp(cmd, "x")) {
    ok = VimWrite(app, arg, force);
    if (ok) ok = VimClosePane(app, app->active, force);
  } else if (!StrCmp(cmd, "q") || !StrCmp(cmd, "quit")) ok = VimClosePane(app, app->active, force);
  else if (!StrCmp(cmd, "qa") || !StrCmp(cmd, "qall")) {
    if (!force && VimAnyModified(app)) { VimMessage(app, "Unsaved buffers; use :w or :qa!"); ok = FALSE; }
    else { app->force_close = TRUE; HtkWindowClose(app->window); }
  } else if (!StrCmp(cmd, "e") || !StrCmp(cmd, "edit") ||
    !StrCmp(cmd, "o") || !StrCmp(cmd, "open")) ok = VimEdit(app, arg, force);
  else if (!StrCmp(cmd, "only")) {
    pane = app->panes;
    while (pane) {
      if (!force && pane != app->active && pane->buffer != app->active->buffer && VimModified(pane->buffer)) ok = FALSE;
      pane = pane->next;
    }
    if (!ok) VimMessage(app, "Unsaved panes; use :w or :only!");
    else {
      pane = app->panes;
      while (pane) { next = pane->next; if (pane != app->active) VimClosePane(app, pane, force); pane = next; }
    }
  } else if (!StrCmp(cmd, "set")) ok = VimSet(app, arg);
  else if (!StrCmp(cmd, "bn") || !StrCmp(cmd, "bnext") || !StrCmp(cmd, "bp") || !StrCmp(cmd, "bprevious") || !StrCmp(cmd, "b") || !StrCmp(cmd, "buffer")) {
    buffer = NULL;
    if (!StrCmp(cmd, "b") || !StrCmp(cmd, "buffer")) {
      if (VimNumber(arg, &n)) {
        buffer = app->buffers;
        while (buffer && buffer->id != n) buffer = buffer->next;
      }
    } else if (!StrCmp(cmd, "bn") || !StrCmp(cmd, "bnext")) {
      buffer = app->active->buffer->next;
      if (!buffer) buffer = app->buffers;
    } else {
      buffer = app->buffers;
      while (buffer->next && buffer->next != app->active->buffer) buffer = buffer->next;
    }
    if (!buffer) { VimMessage(app, "No such buffer; use :ls"); ok = FALSE; }
    else if ((ok = VimCanLeave(app, force))) VimUseBuffer(app, buffer, force);
  } else if (!StrCmp(cmd, "ls") || !StrCmp(cmd, "buffers")) {
    StrBufInit(&list); buffer = app->buffers;
    while (buffer) {
      StrBufPrintf(&list, "%d ", buffer->id);
      if (VimModified(buffer)) StrBufPutS(&list, "+ ");
      if (StrsLen(&buffer->path)) StrBufPutStrs(&list, &buffer->path);
      else StrBufPutS(&list, "[No Name]");
      StrBufPutS(&list, " | "); buffer = buffer->next;
    }
    VimMessage(app, list.a); StrBufFini(&list);
  } else if (!StrCmp(cmd, "help")) {
    HtkMsgBoxFor(app->window, "HTK Vim", ":split / :vsplit [path]   :new / :vnew\nCtrl-W w/W cycle, h/j/k/l move, s/v split, c/o close/only\n:o[!] / :e[!] path   :w[!] [path]   :q[!]   :wq   :qa[!]\n:only[!]   :ls   :b id   :bn / :bp\n:set [no]number [no]wrap [no]readonly [no]vim\n/ or ? literal search, n/N next/previous; :number jumps\nShared HTK Vim motions, editing, clipboard and undo\nF10 window menus; Alt-A App/settings; Esc cancels");
    VimFocus(app->active);
  } else if (VimNumber(cmd, &n) && !*arg) {
    edit = &app->active->buffer->edit; at = 0;
    while (--n && at < StrsLen(&edit->text)) {
      at = HtkVimLine(edit, at, TRUE);
      if (at < StrsLen(&edit->text)) at++;
    }
    edit->cursor = HtkVimFirst(edit, at); edit->anchor = -1;
    HtkMdChanged(app->active->ctl);
  } else { VimMessage(app, "Unknown command; use :help"); ok = FALSE; }
  Free(copy); htk_dirty = TRUE; return ok;
}

U0 VimPromptEnd(CVimApp *app)
{
  app->commandbar->hidden = TRUE; app->status->hidden = FALSE; app->prompt = 0;
  VimFocus(app->active); htk_dirty = TRUE;
}

U0 VimPromptSubmit(HtkCtl *c)
{
  CVimApp *app = c->user;
  I64 prompt = app->prompt;
  U8 *text = StrNew(c->text);

  VimPromptEnd(app);
  if (prompt == ':') VimCommand(app, text);
  else {
    if (*text) { StrBufClear(&app->search); StrBufPutS(&app->search, text); }
    app->search_back = prompt == '?'; VimSearch(app, app->search_back);
  }
  Free(text);
}

U0 VimPrompt(CVimApp *app, I64 prompt=':', U8 *initial="")
{
  U8 label[2];

  label[0] = prompt; label[1] = 0;
  HtkSetText(app->prompt_label, label);
  app->prompt = prompt; app->prefix = 0;
  app->active->buffer->edit.typing = FALSE; app->active->ctl->vim_pending = 0;
  app->status->hidden = TRUE; app->commandbar->hidden = FALSE;
  HtkSetText(app->command, initial); app->command->cursor = StrLen(initial);
  app->command->anchor = -1;
  HtkSetFocus(app->command); htk_dirty = TRUE;
}

Bool VimWindowKey(HtkCtl *c, CTermEvent *e)
{
  CVimApp *app = c->user;

  if (app->prompt && e->key == TERM_KEY_ESCAPE) { VimPromptEnd(app); return TRUE; }
  if (app->prompt && e->key == TERM_KEY_TAB && !(e->mods & TERM_MOD_CTRL)) return TRUE;
  if (e->mods == TERM_MOD_CTRL && e->key == 's') { VimCommand(app, "w"); return TRUE; }
  return FALSE;
}

Bool VimPaneKey(HtkCtl *c, CTermEvent *e)
{
  CVimPane *pane = c->user;
  CVimApp *app = pane->app;
  CEdit *edit;
  CStrs tab;
  I64 key = e->key, prefix = app->prefix;

  VimActivate(pane); edit = &pane->buffer->edit; app->prefix = 0;
  if (e->mods == TERM_MOD_CTRL && key == 'w' && !(c->vim_mode && c->vim_insert)) {
    if (prefix == 'w') VimNextPane(app);
    else app->prefix = 'w';
    return TRUE;
  }
  if (prefix == 'w') {
    if (key == 's') VimCommand(app, "split");
    else if (key == 'v') VimCommand(app, "vsplit");
    else if (key == 'c' || key == 'q') VimCommand(app, "q");
    else if (key == 'o') VimCommand(app, "only");
    else VimNextPane(app, key);
    return TRUE;
  }
  if (c->vim_mode && !c->vim_insert && !c->vim_visual && !(e->mods & (TERM_MOD_CTRL | TERM_MOD_ALT))) {
    if (key == ':' || key == '/' || key == '?') { VimPrompt(app, key); return TRUE; }
    if (key == 'n' || key == 'N') {
      VimSearch(app, app->search_back != (key == 'N')); return TRUE;
    }
  }
  // Source files use literal tabs, including when their text resembles a table.
  if (key == TERM_KEY_TAB) {
    if (c->vim_visual) return TRUE;
    if (e->mods || c->vim_mode && !c->vim_insert) return FALSE;
    StrsInitS(&tab, "\t");
    edit->typing = EditType(edit, &tab); c->vim_at = edit->cursor; c->vim_kill = FALSE;
    HtkMdChanged(c); return TRUE;
  }
  if (HtkMdKey(c, e)) { VimPaneChanged(c); return TRUE; }
  return FALSE;
}

U0 VimPaneMouse(HtkCtl *c)
{
  CVimPane *pane = c->user;

  if (pane->app->prompt) VimPromptEnd(pane->app);
  VimActivate(pane); HtkSetFocus(c); HtkMdMouse(c); VimPaneChanged(c);
}

Bool VimClosing(HtkCtl *c)
{
  CVimApp *app = c->user;

  if (app->force_close || !VimAnyModified(app)) return TRUE;
  return HtkConfirmFor(c, "Unsaved buffers", "Discard all unsaved changes?");
}

U0 VimMenu(HtkCtl *c)
{
  CVimApp *app = c->user;
  U8 *cmd = c->value;

  if (!StrCmp(cmd, "e ") || !StrCmp(cmd, "w ")) VimPrompt(app, ':', cmd);
  else { VimCommand(app, cmd); if (!app->window->closed) VimFocus(app->active); }
}

U0 VimItem(CVimApp *app, HtkCtl *menu, U8 *label, U8 *cmd)
{
  HtkCtl *item = HtkMenuItem(menu, label);

  item->user = app; item->value = cmd; item->changed = &VimMenu;
}

CVimApp *VimNew(U8 *path=NULL)
{
  CVimApp *app = CAlloc(sizeof(CVimApp));
  CVimBuffer *buffer;
  CVimPane *pane;
  HtkCtl *menu;

  StrBufInit(&app->search); StrBufInit(&app->message);
  app->window = HtkWindowNew("HTK Vim", MinI64(110, TermWidth), TermHeight - 2);
  HtkWindowSetSizeLimits(app->window, 32, 10);
  app->window->user = app; app->window->keyfn = &VimWindowKey; app->window->closing = &VimClosing;
  menu = HtkMenuNew(app->window, "File");
  VimItem(app, menu, "Open...", "e "); VimItem(app, menu, "Write       Ctrl-S", "w");
  VimItem(app, menu, "Write as...", "w "); HtkMenuSeparator(menu);
  VimItem(app, menu, "Close pane  :q", "q");
  VimItem(app, menu, "Quit        :qa", "qa");
  menu = HtkMenuNew(app->window, "Window");
  VimItem(app, menu, "Split       Ctrl-W s", "split"); VimItem(app, menu, "Vertical split Ctrl-W v", "vsplit");
  VimItem(app, menu, "New split", "new"); HtkMenuSeparator(menu);
  VimItem(app, menu, "Only this pane Ctrl-W o", "only");
  menu = HtkMenuNew(app->window, "View");
  VimItem(app, menu, "Line numbers", "set number"); VimItem(app, menu, "Hide line numbers", "set nonumber");
  HtkMenuSeparator(menu);
  VimItem(app, menu, "Wrap lines", "set wrap"); VimItem(app, menu, "No wrapping", "set nowrap");
  HtkMenuSeparator(menu);
  VimItem(app, menu, "Help", "help");
  app->body = HtkNew(HTK_BOX); app->body->vertical = TRUE;
  app->workspace = HtkNew(HTK_BOX); app->workspace->vertical = TRUE; app->workspace->expand = TRUE;
  HtkAdd(app->body, app->workspace);
  app->status = HtkStatusbarNew("i inserts | :help commands | Ctrl-W s/v splits | F10 menus");
  app->status->bottom = TRUE; HtkAdd(app->body, app->status);
  app->commandbar = HtkNew(HTK_BOX); app->commandbar->hidden = TRUE; app->commandbar->bottom = TRUE;
  app->prompt_label = HtkNew(HTK_LABEL); HtkSetText(app->prompt_label, ":");
  HtkAdd(app->commandbar, app->prompt_label);
  app->command = HtkEntryNew(""); app->command->expand = TRUE;
  app->command->user = app; app->command->submit = &VimPromptSubmit;
  HtkAdd(app->commandbar, app->command); HtkAdd(app->body, app->commandbar);
  HtkAdd(app->window, app->body);
  buffer = VimBufferOpen(app, path);
  if (!buffer) buffer = VimBufferOpen(app);
  pane = VimPaneNew(app, buffer); HtkAdd(app->workspace, pane->ctl); VimFocus(pane);
  if (StrsEmpty(&app->message)) VimMessage(app, "i inserts; :help commands; Ctrl-W s/v splits");
  return app;
}

U0 VimFree(CVimApp *app)
{
  CVimPane *pane;

  app->force_close = TRUE; HtkWindowClose(app->window); HtkDestroy(app->window);
  while (app->panes) { pane = app->panes; app->panes = pane->next; Free(pane); }
  while (app->buffers) VimForget(app, app->buffers);
  StrBufFini(&app->search); StrBufFini(&app->message); Free(app);
}

U0 VimCopy(I64 data)
{
  CVimApp *app = data;

  if (app->prompt) VimPromptEnd(app);
  else {
    HtkMdCopy(app->active->ctl);
    HtkVimCancel(app->active->ctl, &app->active->buffer->edit);
    app->active->ctl->vim_insert = FALSE; app->active->ctl->vim_pending = 0;
    app->active->buffer->edit.typing = FALSE;
    VimPaneChanged(app->active->ctl);
    htk_dirty = TRUE;
  }
}

#ifndef VIM_TEST
U0 Main(I64 argc, I64 *argv)
{
  CVimApp *app;
  I64 i;

  if (!HtkInit) { "vim needs an interactive terminal\n"; return; }
  if (argc) app = VimNew(argv[0](U8 *));
  else app = VimNew;
  for (i = 1; i < argc; i++) VimSplit(app, TRUE, argv[i](U8 *));
  HtkCtrlCHandler(&VimCopy, app); HtkCtrlCSet(HTK_CTRLC_CALLBACK);
  HtkMain; HtkFini; VimFree(app);
}
Main(argc, argv);
#endif
