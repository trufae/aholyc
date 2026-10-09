#ifndef AHOLYC_LIB_TEXT_MD_ALIGN_HC
#define AHOLYC_LIB_TEXT_MD_ALIGN_HC

// Pandoc fenced divs also retain alignment in HTML-aware Markdown readers.
U8 *md_align_names[4] = {"left", "right", "center", "justify"};
U8 *md_align_fences[4] = {
  "::: {.htk-align-left style=\"text-align:left\"}",
  "::: {.htk-align-right style=\"text-align:right\"}",
  "::: {.htk-align-center style=\"text-align:center\"}",
  "::: {.htk-align-justify style=\"text-align:justify\"}"
};
class CMdAlignment
{
  CStrs source, body;
  I64 align;
};

I64 MdAlignOpen(CStrs *line)
{
  CStrs trim = *line;
  I64 i, n;

  StrsTrim(&trim);
  for (i = 0; i < 4; i++) {
    n = StrLen(md_align_fences[i]);
    if (StrsLen(&trim) == n && !MemCmp(trim.a, md_align_fences[i], n)) return i + 1;
  }
  return 0;
}

Bool MdAlignClose(CStrs *line)
{
  CStrs trim = *line;

  StrsTrim(&trim);
  return StrsLen(&trim) == 3 && !MemCmp(trim.a, ":::" , 3);
}

Bool MdAlignBlock(CStrs *text, U8 *p, CMdAlignment *block)
{
  CStrs line;
  CMdFence fence;
  U8 *next = MdNextLine(text, p, &line), *at;
  I64 align = MdAlignOpen(&line), depth = 1;

  if (!align) return FALSE;
  block->source.a = p; block->body.a = next; block->align = align - 1;
  while (next < text->b) {
    at = next; next = MdNextLine(text, at, &line);
    if (MdFenceStep(&fence, &line) || fence.count) goto next_align_line;
    if (MdAlignOpen(&line)) { if (++depth > 16) return FALSE; }
    else if (MdAlignClose(&line) && !--depth) {
      block->body.b = at; block->source.b = next; return TRUE;
    }
next_align_line:
  }
  return FALSE; // an unclosed div remains visible source text
}

Bool MdAlignAt(CStrs *text, I64 cursor, CMdAlignment *block)
{
  U8 *p = text->a;
  CMdBlock code;
  CStrs line;

  while (p < text->b) {
    if (MdCodeAt(text, p, &code)) p = code.source.b;
    else if (MdAlignBlock(text, p, block)) {
      if (cursor >= p - text->a && cursor < block->source.b - text->a) return TRUE;
      p = block->source.b;
    } else p = MdNextLine(text, p, &line);
  }
  return FALSE;
}

class CMdAlignRow
{
  CMdAlignRow *next;
  I64 width, gaps;
  Bool final;
};
class CMdAlignLayout
{
  CMarkdown *parent;
  CMdAlignRow *rows;
  CMdAlignRow *row;
  CStrs body;
  I64 align, skip, pending, gap;
  Bool seen, started;
};

U0 MdAlignForward(CMarkdown *md, CMarkdown *parent)
{
  parent->source = md->source;
  parent->target = md->target; parent->link_start = md->link_start; parent->link_end = md->link_end;
  parent->fg = md->fg; parent->bg = md->bg;
  parent->code = md->code; parent->language = md->language;
}

Bool MdAlignIndent(CMdAlignLayout *layout, U8 *p, I64 rune)
{
  if (layout->skip && !layout->seen && rune == ' ' &&
    !(p >= layout->body.a && p < layout->body.b)) {
      layout->skip--; return TRUE;
    }
  return FALSE;
}

U0 MdAlignMeasure(CMarkdown *md, CStrs *text)
{
  CMdAlignLayout *layout = md->user;
  U8 *p = text->a, *next;
  I64 n, rune;

  while (p < text->b) {
    n = MaxI64(1, Utf8DecodeRune(p, text->b - p, &rune));
    if (rune == '\n') {
      next = md->source;
      layout->row->final = next >= layout->body.b;
      if (next >= layout->body.a && next < layout->body.b && *next == '\n') {
        next++;
        layout->row->final = next == layout->body.b || *next == '\n' || *next == '\r';
      }
      layout->row->next = CAlloc(sizeof(CMdAlignRow));
      layout->row = layout->row->next; layout->row->final = TRUE;
      layout->seen = FALSE; layout->pending = 0; layout->skip = 2;
    } else if (!MdAlignIndent(layout, p, rune)) {
      layout->row->width += Utf8CellWidth(rune);
      if (rune == ' ') { if (layout->seen) layout->pending++; }
      else {
        if (layout->pending) layout->row->gaps++;
        layout->pending = 0; layout->seen = TRUE;
      }
    }
    p += n;
  }
}

U0 MdAlignStyle(CMarkdown *md, I64 style, I64 on)
{
  CMdAlignLayout *layout = md->user;

  MdAlignForward(md, layout->parent); MdStyle(layout->parent, style, on);
}

U0 MdAlignText(CMarkdown *md, CStrs *text)
{
  CMdAlignLayout *layout = md->user;
  CMarkdown *parent = layout->parent;
  CMdAlignRow *row = layout->row;
  U8 *p = text->a;
  I64 n, rune, pad, extra;

  while (p < text->b && row) {
    n = MaxI64(1, Utf8DecodeRune(p, text->b - p, &rune));
    MdAlignForward(md, parent);
    // Rich inline slices may contain several source runes.
    if (p >= layout->body.a && p < layout->body.b) parent->source = p;
    if (rune == '\n') {
      MdText(parent, p, p + n);
      layout->row = row = row->next;
      layout->seen = layout->started = FALSE;
      layout->pending = layout->gap = 0; layout->skip = 2;
    } else if (!MdAlignIndent(layout, p, rune)) {
      pad = MaxI64(0, parent->width - row->width);
      if (!layout->started) {
        extra = 0;
        if (layout->align == MD_ALIGN_RIGHT) extra = pad;
        if (layout->align == MD_ALIGN_CENTER) extra = pad / 2;
        MdRepeat(parent, " ", 2 + extra); layout->started = TRUE;
      }
      if (rune == ' ') { if (layout->seen) layout->pending++; }
      else {
        if (layout->pending) {
          if (layout->align == MD_ALIGN_JUSTIFY && !row->final && row->gaps) {
            extra = pad / row->gaps;
            if (layout->gap < pad % row->gaps) extra++;
            MdRepeat(parent, " ", extra);
          }
          layout->gap++;
        }
        layout->pending = 0; layout->seen = TRUE;
      }
      MdText(parent, p, p + n);
    }
    p += n;
  }
}

// Two streaming passes; store only row widths/gap counts, never glyphs or text.
U0 MdAlignRender(CMarkdown *md, CMdAlignment *block)
{
  CMdAlignLayout layout;
  CMarkdown child = *md;
  CMdAlignRow *row, *next;

  child.align_depth++;
  if (md->alignment_ignore) { MarkdownRenderStrs(&child, &block->body); return; }
  child.word_wrap = TRUE;
  layout.parent = md; layout.body = block->body; layout.align = block->align;
  layout.skip = 2;
  layout.rows = layout.row = CAlloc(sizeof(CMdAlignRow)); layout.row->final = TRUE;
  child.text = &MdAlignMeasure; child.style = NULL; child.user = (&layout)(U8 *);
  MarkdownRenderStrs(&child, &block->body);
  layout.row = layout.rows; layout.skip = 2; layout.pending = layout.gap = 0;
  layout.seen = layout.started = FALSE;
  child = *md; child.align_depth++; child.word_wrap = TRUE;
  child.text = &MdAlignText; child.style = &MdAlignStyle; child.user = (&layout)(U8 *);
  MarkdownRenderStrs(&child, &block->body);
  row = layout.rows;
  while (row) { next = row->next; Free(row); row = next; }
}

#endif
