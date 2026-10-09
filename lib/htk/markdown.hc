#ifndef AHOLYC_LIB_HTK_MARKDOWN_HC
#define AHOLYC_LIB_HTK_MARKDOWN_HC

#include "htk.hc"
#include "../text/md_edit.hc"

// Orthogonal flags: source/rendered and readonly/editable.
#define HTK_MD_EDIT 0
#define HTK_MD_SOURCE 1
#define HTK_MD_READ 2
#define HTK_MD_SOURCE_READ 3
#define HTK_MD_CONTINUOUS 0
#define HTK_MD_PAGES 1
#define HTK_MD_SECTION 2

// Caller owns edit. Layout streams directly into the viewport: no per-byte
// glyph array or duplicate document. Query passes use the same source map.
class CHtkMarkdown
{
  HtkCtl *ctl;
  CEdit *edit;
  I64 mode, left, x, y, width, rows, columns;
  I64 caret_x, caret_y, distance;
  I64 gutter, inset, height, viewport, column_width, page_lines, layout;
  I64 page_row, page_number, section_at, range_a, range_b;
  I64 guide_y, line_at, line_number, code_a, code_b, code_hit_a, code_hit_b, tab_width;
  Bool line_numbers, ruler_top, ruler_left, no_wrap, hide_status;
  I64 query_x, query_y, hit, hit_distance, link_a, link_b;
  I64 attr, fg, bg, link_start, link_end, press_at;
  CStrs target, hit_target;
  Bool paint, query, follow, fit, dragging;
  U0 (*linkfn)(HtkCtl *c, I64 a, I64 b, CStrs *target);
};

U0 HtkMdPage(CHtkMarkdown *view)
{
  HtkCtl *c = view->ctl;
  I64 y = view->y - c->top + view->inset;
  U8 *label;

  view->page_number++;
  if (view->paint && y >= view->inset && y < c->h - !view->hide_status) {
    HtkRect(c->x + view->gutter, c->y + y, view->viewport, 1, 0x2500, HTK_C_DIM, HTK_C_BG);
    label = MStrPrint(" Page %d ", view->page_number);
    HtkStr(c->x + view->gutter + 2, c->y + y, label, HTK_C_DIM, HTK_C_BG);
    Free(label);
  }
  view->y++;
  view->page_row = 0;
}

U0 HtkMdNewline(CHtkMarkdown *view)
{
  view->columns = MaxI64(view->columns, view->x);
  view->x = 0;
  view->y++;
  view->page_row++;
  if (view->layout == HTK_MD_PAGES && view->page_row >= view->page_lines) HtkMdPage(view);
}

U0 HtkMdGuide(CHtkMarkdown *view, I64 at)
{
  HtkCtl *c = view->ctl;
  I64 y = view->y - c->top + view->inset;
  U8 *label;

  if (view->guide_y == view->y) return;
  view->guide_y = view->y;
  while (view->line_at < at) {
    if (view->edit->text.a[view->line_at++] == '\n') view->line_number++;
  }
  while (view->line_at > at) {
    if (view->edit->text.a[--view->line_at] == '\n') view->line_number--;
  }
  if (!view->paint || y < view->inset || y >= c->h - !view->hide_status) return;
  if (view->line_numbers) {
    label = MStrPrint("%4d ", view->line_number);
    HtkStr(c->x, c->y + y, label, HTK_C_DIM, HTK_C_BG);
    Free(label);
  }
  if (view->ruler_left) {
    label = StrNew("  | ");
    if (!(view->page_row % 5)) { Free(label); label = MStrPrint("%2d|", view->page_row % 100); }
    HtkStr(c->x + view->gutter - 3, c->y + y, label, HTK_C_DIM, HTK_C_BG);
    Free(label);
  }
}

U0 HtkMdStyle(CMarkdown *md, I64 style, I64 on)
{
  CHtkMarkdown *view = md->user(CHtkMarkdown *);
  I64 bit = 0, y;
  HtkCtl *c = view->ctl;
  U8 *label;

  if (style == MD_STYLE_PAGE_BREAK && on) { HtkMdPage(view); return; }
  if (style == MD_STYLE_CODE_FENCE && on) {
    view->code_a = md->code.a - view->edit->text.a;
    view->code_b = md->code.b - view->edit->text.a;
    if (view->query && view->query_y == view->y && view->query_x - view->left >= 0 && view->query_x - view->left < 6) {
      view->code_hit_a = view->code_a;
      view->code_hit_b = view->code_b;
    }
    y = view->y - c->top + view->inset;
    if (view->paint && y >= view->inset && y < c->h - !view->hide_status) {
      HtkStr(c->x + view->gutter, c->y + y, "[Copy]", HTK_C_SEL_FG, HTK_C_SEL_BG);
      label = MAlloc(StrsLen(&md->language) + 1);
      MemCpy(label, md->language.a, StrsLen(&md->language));
      label[StrsLen(&md->language)] = 0;
      HtkStr(c->x + view->gutter + 7, c->y + y, label, HTK_C_DIM, HTK_C_FIELD_BG);
      Free(label);
    }
    HtkMdNewline(view);
    return;
  }
  if (style == MD_STYLE_CODE_BLOCK) {
    view->bg = 0;
    if (on) view->bg = 0x202838 + 1;
  }
  if (style == MD_STYLE_CODE_TOKEN) {
    view->fg = 0;
    if (on == 1) view->fg = 0xB39DDB + 1;
    if (on == 2) view->fg = 0xA5D6A7 + 1;
    if (on == 3) view->fg = 0x90A4AE + 1;
    if (on == 4) view->fg = 0xFFCC80 + 1;
  }

  if (style == MD_STYLE_BOLD || style == MD_STYLE_TITLE) bit = TERM_BOLD;
  if (style == MD_STYLE_ITALIC) bit = TERM_ITALIC;
  if (style == MD_STYLE_UNDERLINE) bit = TERM_UNDERLINE;
  if (style == MD_STYLE_STRIKE) bit = TERM_STRIKE;
  if (on) view->attr |= bit;
  else view->attr &= ~bit;
  if (style == MD_STYLE_FG) view->fg = on;
  if (style == MD_STYLE_BG) view->bg = on;
  if (style == MD_STYLE_LINK || style == MD_STYLE_IMAGE) {
    view->link_start = -1;
    if (on) {
      view->target = md->target;
      view->link_start = md->link_start - view->edit->text.a;
      view->link_end = md->link_end - view->edit->text.a;
    }
  }
}

U0 HtkMdText(CMarkdown *md, CStrs *text)
{
  CHtkMarkdown *view = md->user(CHtkMarkdown *);
  CEdit *edit = view->edit;
  HtkCtl *c = view->ctl;
  U8 *p = text->a;
  I64 rune, n, at, distance, a, b, fg, bg, attr, x, y, cells, j;
  I64 caret = edit->cursor;
  Bool source;

  #ifdef UI_HTK_VIMODE
  caret = HtkVimCaret(c, caret);
  #endif
  EditSelection(edit, &a, &b);
  while (p < text->b) {
    n = MaxI64(1, Utf8DecodeRune(p, text->b - p, &rune));
    if (n == 1 && *p >= 128) rune = 0xFFFD;
    at = md->source - edit->text.a;
    source = p >= edit->text.a && p < edit->text.b;
    if (source) at = p - edit->text.a;
    at = MaxI64(0, MinI64(StrsLen(&edit->text), at));
    cells = Utf8CellWidth(rune);
    if (rune == '\t') cells = view->tab_width - view->x % view->tab_width;
    if ((view->mode & HTK_MD_SOURCE) && !view->no_wrap && view->x + cells > view->width && rune != '\n') {
      HtkMdNewline(view);
    }
    HtkMdGuide(view, at);
    distance = AbsI64(at - caret);
    if (distance < view->distance || source && distance == view->distance) {
      view->distance = distance;
      view->caret_x = view->x;
      view->caret_y = view->y;
    }
    if (view->query) {
      distance = AbsI64(view->y - view->query_y) * 1000000 +
        AbsI64(view->x - view->query_x);
      if (distance < view->hit_distance) {
        view->hit_distance = distance;
        view->hit = at;
        view->link_a = -1;
        if (view->query_y == view->y && view->query_x >= view->x && view->query_x < view->x + cells)
          view->link_a = view->link_start;
        view->link_b = view->link_end;
        view->hit_target = view->target;
      }
    }
    if (rune == '\t') {
      n = 1;
      rune = ' ';
    }
    if (rune == '\n') {
      #ifdef UI_HTK_VIMODE
      if (view->paint && c->vim_visual && at >= a && at < b) {
        x = MaxI64(0, view->x - view->left);
        y = view->y - c->top + view->inset;
        if (x < view->viewport && y >= view->inset && y < c->h - !view->hide_status)
          HtkRect(c->x + view->gutter + x, c->y + y,
            1 + (view->viewport - x - 1) * (c->vim_visual == 2), 1,
            ' ', HTK_C_SEL_FG, HTK_C_SEL_BG);
      }
      #endif
      HtkMdNewline(view);
    } else {
      x = view->x - view->left;
      y = view->y - c->top + view->inset;
      if (view->paint && x >= 0 && x < view->viewport && y >= view->inset && y < c->h - !view->hide_status) {
        fg = HTK_C_FIELD_FG;
        bg = HTK_C_FIELD_BG;
        attr = view->attr;
        if (view->fg) fg = TermColorRgb((view->fg - 1) >> 16 & 255,
          (view->fg - 1) >> 8 & 255, (view->fg - 1) & 255);
        if (view->bg) bg = TermColorRgb((view->bg - 1) >> 16 & 255,
          (view->bg - 1) >> 8 & 255, (view->bg - 1) & 255);
        if (view->link_start >= 0) attr |= TERM_UNDERLINE;
        if (at >= a && at < b) { fg = HTK_C_SEL_FG; bg = HTK_C_SEL_BG; }
        if (rune == '\t') rune = ' ';
        if (rune < ' ' || rune == 127) rune = 0xFFFD;
        HtkChr(c->x + view->gutter + x, c->y + y, rune, fg, bg, attr);
        if (*p == '\t')
          for (j = 1; j < cells && x + j < view->viewport; j++)
            HtkChr(c->x + view->gutter + x + j, c->y + y, ' ', fg, bg, attr);
      }
      view->x += cells;
    }
    p += n;
  }
}

U0 HtkMdRender(CHtkMarkdown *view, Bool paint=FALSE)
{
  CMarkdown md;
  CEdit *edit = view->edit;
  I64 distance;
  I64 caret = edit->cursor;
  CStrs source = edit->text;

  #ifdef UI_HTK_VIMODE
  caret = HtkVimCaret(view->ctl, caret);
  #endif
  view->paint = paint;
  view->x = 0;
  view->y = 0;
  view->columns = 0;
  view->gutter = 6 * view->line_numbers + 3 * view->ruler_left;
  view->inset = view->ruler_top;
  view->height = MaxI64(1, view->ctl->h - view->inset - !view->hide_status);
  view->viewport = MaxI64(1, view->ctl->w - view->gutter);
  view->width = view->viewport;
  if (view->column_width) view->width = MaxI64(8, MinI64(view->width, view->column_width));
  view->page_row = 0; view->page_number = 0;
  view->guide_y = -1; view->line_at = 0; view->line_number = 1;
  view->code_hit_a = -1;
  if (view->layout == HTK_MD_SECTION) MdSection(&edit->text, view->section_at, &source);
  view->range_a = source.a - edit->text.a;
  view->range_b = source.b - edit->text.a;
  if (view->layout == HTK_MD_PAGES) HtkMdPage(view);
  view->attr = 0;
  view->fg = 0;
  view->bg = 0;
  view->distance = I64_MAX;
  view->hit_distance = I64_MAX;
  view->link_start = -1;
  view->link_a = -1;
  view->hit = 0;
  MarkdownInit(&md, &HtkMdText, &HtkMdStyle, view);
  md.width = MaxI64(8, view->width - 3);
  md.utf8 = TRUE;
  md.table_fit = view->fit;
  md.source = source.a;
  view->target.a = NULL; view->target.b = NULL;
  if (view->mode & HTK_MD_SOURCE) HtkMdText(&md, &source);
  else MarkdownRenderStrs(&md, &source);
  if (caret == view->range_b) {
    view->caret_x = view->x;
    view->caret_y = view->y;
  }
  if (view->query) {
    distance = AbsI64(view->y - view->query_y) * 1000000 + AbsI64(view->x - view->query_x);
    if (distance < view->hit_distance) {
      view->hit = view->range_b;
      view->link_a = -1;
    }
  }
  view->rows = view->y + 1;
  view->columns = MaxI64(view->columns, view->x);
}

I64 HtkMdHit(CHtkMarkdown *view, I64 x, I64 y)
{
  view->query_x = MaxI64(0, x);
  view->query_y = MaxI64(0, y);
  view->query = TRUE;
  HtkMdRender(view);
  view->query = FALSE;
  return view->hit;
}

U0 HtkMdDraw(HtkCtl *c)
{
  CHtkMarkdown *view = c->data(CHtkMarkdown *);
  I64 x, y, col, row;
  U8 *status;

  HtkMdRender(view);
  if (view->follow) {
    HtkScrollIntoView(c, view->caret_y, view->height);
    if (view->caret_x < view->left) view->left = view->caret_x;
    if (view->caret_x >= view->left + view->viewport) view->left = view->caret_x - view->viewport + 1;
    view->follow = FALSE;
  }
  c->top = MaxI64(0, MinI64(c->top, view->rows - 1));
  view->left = MaxI64(0, MinI64(view->left, MaxI64(0, view->columns - view->viewport + 1)));
  HtkRect(c->x, c->y, c->w, c->h, ' ', HTK_C_FIELD_FG, HTK_C_FIELD_BG);
  // Guides must extend through empty rows, including a trailing empty line.
  if (view->ruler_left) {
    for (y = view->inset; y < c->h - !view->hide_status; y++) {
      row = c->top + y - view->inset;
      status = StrNew("  | ");
      if (!(row % 5)) { Free(status); status = MStrPrint("%2d|", row % 100); }
      HtkStr(c->x + view->gutter - 3, c->y + y, status, HTK_C_DIM, HTK_C_BG);
      Free(status);
    }
  }
  HtkMdRender(view, TRUE);
  #ifdef UI_HTK_VIMODE
  if (c->vim_visual == 2 && view->edit->anchor == view->edit->cursor) {
    x = view->caret_x - view->left; y = view->caret_y - c->top + view->inset;
    if (x >= 0 && x < view->viewport && y >= view->inset && y < c->h - !view->hide_status)
      HtkChr(c->x + view->gutter + x, c->y + y, ' ', HTK_C_SEL_FG, HTK_C_SEL_BG);
  }
  #endif
  HtkMdGuide(view, view->range_b);
  if (view->ruler_top) {
    for (x = 0; x < view->viewport; x++) {
      col = x + view->left + 1;
      y = '.';
      if (!(col % 5)) y = '|';
      if (!(col % 10)) y = '0' + col / 10 % 10;
      if (col == view->width) y = 0x2524;
      HtkChr(c->x + view->gutter + x, c->y, y, HTK_C_DIM, HTK_C_BG);
    }
  }
  if (!view->hide_status) {
    status = MStrPrint("< >  %d/%d  byte %d/%d", c->top + 1, view->rows,
      view->edit->cursor, StrsLen(&view->edit->text));
    HtkStr(c->x, c->y + c->h - 1, status, HTK_C_DIM, HTK_C_BG);
    Free(status);
  }
  x = view->caret_x - view->left;
  y = view->caret_y - c->top + view->inset;
  if (HtkFocused(c) && !view->edit->readonly && x >= 0 && x < view->viewport && y >= view->inset && y < c->h - !view->hide_status) {
    HtkShowCursor(c, c->x + view->gutter + x, c->y + y);
  }
}

U0 HtkMdChanged(HtkCtl *c)
{
  CHtkMarkdown *view = c->data(CHtkMarkdown *);

  view->follow = TRUE;
  htk_dirty = TRUE;
  if (c->submit) c->submit(c);
}

U0 HtkMdCopy(HtkCtl *c, Bool cut=FALSE)
{
  CHtkMarkdown *view = c->data(CHtkMarkdown *);
  I64 a, b;
  CStrs slice;

  EditSelection(view->edit, &a, &b);
  if (a == b) return;
  StrsInit(&slice, view->edit->text.a + a, view->edit->text.a + b);
  HtkClipboardSetStrs(&slice);
  if (cut) {
    StrsInitN(&slice, "", 0);
    if (EditInsert(view->edit, &slice)) HtkMdChanged(c);
  }
}

Bool HtkMdKey(HtkCtl *c, CTermEvent *e)
{
  CHtkMarkdown *view = c->data(CHtkMarkdown *);
  CEdit *edit = view->edit;
  I64 key = e->key, cursor = edit->cursor, a, b, n;
  Bool ctrl = e->mods & TERM_MOD_CTRL, move = FALSE, changed = FALSE;
  CStrs text;
  U8 bytes[4];

  if (key == TERM_KEY_TAB && !(e->mods & (TERM_MOD_CTRL | TERM_MOD_ALT))) {
    #ifdef UI_HTK_VIMODE
    if (c->vim_visual) return TRUE;
    #endif
    if (edit->readonly || !MdTableMove(edit, e->mods & TERM_MOD_SHIFT)) return FALSE;
    #ifdef UI_HTK_VIMODE
    c->vim_pending = 0; c->vim_vertical = FALSE;
    #endif
    HtkMdChanged(c); return TRUE;
  }
  #ifdef UI_HTK_VIMODE
  if (HtkVimKey(c, edit, e)) { HtkMdChanged(c); return TRUE; }
  #endif
  HtkMdRender(view);
  if (ctrl && key == 'a') { edit->anchor = 0; edit->cursor = StrsLen(&edit->text); }
  else if (ctrl && key == 'c') HtkMdCopy(c);
  else if (ctrl && key == 'x') HtkMdCopy(c, TRUE);
  else if (ctrl && key == 'v') { HtkClipboardGet(&text); changed = EditInsert(edit, &text); }
  else if (ctrl && (key == 'z' || key == 'y'))
    changed = EditUndo(edit, key == 'y' || e->mods & TERM_MOD_SHIFT);
  else if (e->mods & TERM_MOD_ALT && (key == TERM_KEY_LEFT || key == TERM_KEY_RIGHT)) {
    if (key == TERM_KEY_LEFT) view->left = MaxI64(0, view->left - 4);
    else view->left += 4;
  } else if (key == TERM_KEY_LEFT || key == TERM_KEY_RIGHT) {
    if (view->mode & HTK_MD_SOURCE)
      cursor = EditNext(edit, cursor, 1 - 2 * (key == TERM_KEY_LEFT));
    else {
      n = 1 - 2 * (key == TERM_KEY_LEFT);
      cursor = HtkMdHit(view, view->caret_x + n, view->caret_y);
      if (cursor == edit->cursor) cursor = EditNext(edit, cursor, n);
    }
    move = TRUE;
  } else if (key == TERM_KEY_UP || key == TERM_KEY_DOWN || key == TERM_KEY_PGUP || key == TERM_KEY_PGDN) {
    n = 1;
    if (key == TERM_KEY_PGUP || key == TERM_KEY_PGDN) n = MaxI64(1, c->h - 2);
    if (key == TERM_KEY_UP || key == TERM_KEY_PGUP) n = -n;
    cursor = HtkMdHit(view, view->caret_x, view->caret_y + n);
    move = TRUE;
  } else if (key == TERM_KEY_HOME || key == TERM_KEY_END) {
    if (ctrl) {
      cursor = 0;
      if (key == TERM_KEY_END) cursor = StrsLen(&edit->text);
    } else {
      n = 0;
      if (key == TERM_KEY_END) n = view->columns + 1;
      cursor = HtkMdHit(view, n, view->caret_y);
    }
    move = TRUE;
  } else if (key == TERM_KEY_DELETE || key == TERM_KEY_BACKSPACE) {
    EditSelection(edit, &a, &b);
    if (a == b) {
      if (key == TERM_KEY_DELETE) b = EditNext(edit, b, 1);
      else a = EditNext(edit, a, -1);
    }
    StrsInitN(&text, "", 0);
    changed = EditReplace(edit, a, b, &text);
  } else if (key == TERM_KEY_ENTER || (key >= ' ' && key < 0x110000 && !ctrl && !(e->mods & TERM_MOD_ALT))) {
    if (key == TERM_KEY_ENTER) key = '\n';
    n = Utf8EncodeRune(key, bytes);
    StrsInitN(&text, bytes, n);
    changed = EditType(edit, &text);
  } else return FALSE;
  if (move) {
    edit->typing = FALSE;
    if (e->mods & TERM_MOD_SHIFT) {
      if (edit->anchor < 0) edit->anchor = edit->cursor;
    } else edit->anchor = -1;
    edit->cursor = cursor;
    view->follow = TRUE;
  }
  if (changed) HtkMdChanged(c);
  else if (c->submit) c->submit(c);
  htk_dirty = TRUE;
  return TRUE;
}

U0 HtkMdMouse(HtkCtl *c)
{
  CHtkMarkdown *view = c->data(CHtkMarkdown *);
  CEdit *edit = view->edit;
  I64 at;

  if (c->mouse_button == TERM_MOUSE_WHEEL_UP || c->mouse_button == TERM_MOUSE_WHEEL_DOWN) {
    at = 3;
    if (c->mouse_button == TERM_MOUSE_WHEEL_UP) at = -3;
    c->top = MaxI64(0, c->top + at);
    return;
  }
  if (c->mouse_button != TERM_MOUSE_LEFT) return;
  edit->typing = FALSE;
  if (!view->hide_status && c->mouse_y == c->h - 1) {
    if (c->mouse_pressed && !c->mouse_motion) {
      at = 4;
      if (c->mouse_x < 2) at = -4;
      view->left = MaxI64(0, view->left + at);
    }
    return;
  }
  if (c->mouse_y < view->inset) {
    if (c->mouse_pressed) view->column_width = MaxI64(8, c->mouse_x - view->gutter + view->left + 1);
    return;
  }
  at = HtkMdHit(view, c->mouse_x - view->gutter + view->left, c->mouse_y - view->inset + c->top);
  if (view->code_hit_a >= 0) {
    if (c->mouse_pressed && !c->mouse_motion) {
      CStrs code;
      StrsInit(&code, edit->text.a + view->code_hit_a, edit->text.a + view->code_hit_b);
      HtkClipboardSetStrs(&code);
      HtkNotify("Code copied", 1200);
    }
    return;
  }
  if (c->mouse_pressed && !c->mouse_motion) {
    #ifdef UI_HTK_VIMODE
    if (c->vim_visual) HtkVimCancel(c, edit);
    #endif
    view->press_at = at;
    view->dragging = FALSE;
    if (!(c->mouse_mods & TERM_MOD_SHIFT) || edit->anchor < 0) edit->anchor = at;
  }
  if (c->mouse_motion) view->dragging = TRUE;
  edit->cursor = at;
  if (c->submit) c->submit(c);
  if (!c->mouse_pressed && !c->mouse_motion && !view->dragging && at == view->press_at) {
    if (view->link_a >= 0 && view->linkfn)
      view->linkfn(c, view->link_a, view->link_b, &view->hit_target);
  }
}

U0 HtkMdDestroy(HtkCtl *c)
{
  Free(c->data);
}

#ifdef UI_HTK_VIMODE
U0 HtkMdVimPage(HtkCtl *c, CEdit *edit, I64 direction)
{
  CHtkMarkdown *view = c->data(CHtkMarkdown *);
  I64 step, x, y, top = c->top;

  HtkMdRender(view);
  step = MaxI64(1, view->height - 2);
  x = view->caret_x; y = view->caret_y;
  edit->cursor = HtkMdHit(view, x, y + direction * step);
  c->top = MaxI64(0, MinI64(MaxI64(0, view->rows - view->height), top + direction * step));
  c->vim_vertical = FALSE;
}

U0 HtkMdVimChanged(HtkCtl *c)
{
  if (c->vim_visual) HtkVimCancel(c, c->data(CHtkMarkdown *)->edit);
  HtkMdChanged(c);
}
#endif

HtkCtl *HtkMarkdownNew(CEdit *edit)
{
  CHtkMarkdown *view = CAlloc(sizeof(CHtkMarkdown));
  HtkCtl *c = HtkCanvasNew(24, 8, &HtkMdDraw, view);

  view->ctl = c;
  view->edit = edit;
  view->fit = TRUE;
  view->follow = TRUE;
  view->mode = HTK_MD_EDIT;
  view->page_lines = 60;
  view->tab_width = 4;
  c->expand = TRUE;
  c->focusable = TRUE;
  c->cursor_shape = TERM_CURSOR_BAR;
  c->keyfn = &HtkMdKey;
  c->changed = &HtkMdMouse;
  c->destroy = &HtkMdDestroy;
  #ifdef UI_HTK_VIMODE
  c->vim_editor = TRUE;
  c->vim_mode = htk_vim_mode;
  c->vim_changed = &HtkMdVimChanged;
  c->vim_page = &HtkMdVimPage;
  #endif
  return c;
}

U0 HtkMarkdownMode(HtkCtl *c, I64 mode)
{
  CHtkMarkdown *view = c->data(CHtkMarkdown *);

  view->mode = MaxI64(0, MinI64(3, mode));
  view->edit->readonly = (view->mode & HTK_MD_READ) != 0;
  view->left = 0;
  view->follow = TRUE;
  htk_dirty = TRUE;
}

#endif
