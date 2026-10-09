#ifndef AHOLYC_LIB_TEXT_MD_EXPORT_HC
#define AHOLYC_LIB_TEXT_MD_EXPORT_HC

#include "md_edit.hc"

#define MD_EXPORT_HTML 0
#define MD_EXPORT_GEM 1
#define MD_EXPORT_TEXT 2

class CMdExport
{
  CStrBuf *out;
  CStrBuf links;
  I64 format;
  Bool linked, image;
};

U0 MdHtmlEscape(CStrBuf *out, CStrs *text)
{
  U8 *p;

  for (p = text->a; p < text->b; p++) {
    if (*p == '&') StrBufPutS(out, "&amp;");
    else if (*p == '<') StrBufPutS(out, "&lt;");
    else if (*p == '>') StrBufPutS(out, "&gt;");
    else if (*p == '"') StrBufPutS(out, "&quot;");
    else if (*p == '\'') StrBufPutS(out, "&#39;");
    else if (*p == 0) StrBufPutS(out, "&#xfffd;");
    else StrBufPutC(out, *p);
  }
}

Bool MdTargetSafe(CStrs *target)
{
  U8 *p;
  CStrs scheme;
  U8 *allowed[5] = {"http", "https", "mailto", "gemini", "file"};
  I64 i, j, c;
  Bool equal;

  if (StrsEmpty(target)) return FALSE;
  for (p = target->a; p < target->b; p++)
    if (*p < ' ' || *p == 127) return FALSE;
  for (p = target->a; p < target->b && *p != '/' && *p != '#'; p++) {
    if (*p == ':') {
      StrsInit(&scheme, target->a, p);
      for (i = 0; i < 5; i++) {
        equal = StrsLen(&scheme) == StrLen(allowed[i]);
        for (j = 0; equal && j < StrsLen(&scheme); j++) {
          c = scheme.a[j];
          if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
          if (c != allowed[i][j]) equal = FALSE;
        }
        if (equal) return TRUE;
      }
      return FALSE;
    }
  }
  return TRUE;
}

U0 MdExportText(CMarkdown *md, CStrs *text)
{
  CMdExport *export = md->user(CMdExport *);

  if (export->format == MD_EXPORT_HTML) MdHtmlEscape(export->out, text);
  else StrBufPutStrs(export->out, text);
}

U0 MdExportStyle(CMarkdown *md, I64 style, I64 on)
{
  CMdExport *export = md->user(CMdExport *);
  U8 *tag = NULL;

  if (style == MD_STYLE_LINK || style == MD_STYLE_IMAGE) {
    export->image = style == MD_STYLE_IMAGE && on;
    if (on) {
      export->linked = MdTargetSafe(&md->target);
      if (!export->linked) return;
      if (export->format == MD_EXPORT_HTML) {
        if (style == MD_STYLE_IMAGE) StrBufPutS(export->out, "<img src=\"");
        else StrBufPutS(export->out, "<a href=\"");
        MdHtmlEscape(export->out, &md->target);
        if (style == MD_STYLE_IMAGE) StrBufPutS(export->out, "\" alt=\"");
        else StrBufPutS(export->out, "\">");
      } else if (export->format == MD_EXPORT_GEM) {
        StrBufPutS(&export->links, "=> ");
        StrBufPutStrs(&export->links, &md->target);
        StrBufPutC(&export->links, '\n');
      }
    } else if (export->linked && export->format == MD_EXPORT_HTML) {
      if (style == MD_STYLE_IMAGE) StrBufPutS(export->out, "\">");
      else StrBufPutS(export->out, "</a>");
    }
    return;
  }
  if (export->format != MD_EXPORT_HTML) return;
  if (style == MD_STYLE_FG || style == MD_STYLE_BG) {
    // CSS events are state changes; the inline parser balances nested spans.
    // Emit a separate span only for a non-default color, tracked below.
    return;
  }
  if (style == MD_STYLE_BOLD) tag = "strong";
  if (style == MD_STYLE_ITALIC) tag = "em";
  if (style == MD_STYLE_UNDERLINE) tag = "u";
  if (style == MD_STYLE_STRIKE) tag = "s";
  if (style == MD_STYLE_CODE) tag = "code";
  if (tag) {
    if (on) StrBufPrintf(export->out, "<%s>", tag);
    else StrBufPrintf(export->out, "</%s>", tag);
  }
}

// Paint colors per text span: no raw HTML or CSS from the file is copied.
U0 MdExportColorText(CMarkdown *md, CStrs *text)
{
  CMdExport *export = md->user(CMdExport *);
  Bool color = export->format == MD_EXPORT_HTML && !export->image && (md->fg || md->bg);

  if (color) {
    StrBufPutS(export->out, "<span style=\"");
    if (md->fg) StrBufPrintf(export->out, "color:#%06X;", md->fg - 1);
    if (md->bg) StrBufPrintf(export->out, "background-color:#%06X;", md->bg - 1);
    StrBufPutS(export->out, "\">");
  }
  MdExportText(md, text);
  if (color) StrBufPutS(export->out, "</span>");
}

// HTML uses semantic headings/tables. Gemtext uses fenced tables and => links.
U0 MarkdownExport(CStrs *source, CStrBuf *out, I64 format)
{
  CMdExport export;
  CMarkdown md;
  CMdTable table;
  CStrs line, cells[MD_TABLE_MAX_COLS];
  CStrBuf slug;
  U8 *p = source->a, *next, *row, *tag;
  I64 level, n, i, number, aligns[MD_TABLE_MAX_COLS];
  U8 *align_names[3] = {"left", "right", "center"};
  CMdFence fence;
  I64 transition;
  Bool html = format == MD_EXPORT_HTML;

  export.out = out;
  export.format = format;
  StrBufInit(&export.links);
  StrBufInit(&slug);
  MarkdownInit(&md, &MdExportColorText, &MdExportStyle, &export);
  if (format == MD_EXPORT_TEXT) {
    md.width = 1000000;
    md.code_pad = FALSE;
    MarkdownRenderStrs(&md, source);
    StrBufFini(&export.links);
    StrBufFini(&slug);
    return;
  }
  if (html) StrBufPutS(out, "<!doctype html>\n<html><head><meta charset=\"utf-8\"><title>Document</title><style>body{max-width:80ch;margin:2em auto;font-family:system-ui}table{border-collapse:collapse;display:block;overflow:auto}td,th{border:1px solid;padding:.3em}.border-3 td,.border-3 th{border:0}.border-1{border-radius:.5em}img{max-width:100%}pre{overflow:auto}</style></head><body>\n");
  while (p < source->b) {
    next = MdNextLine(source, p, &line);
    transition = MdFenceStep(&fence, &line);
    if (transition) {
      if (html) {
        if (fence.count) StrBufPutS(out, "<pre><code>");
        else StrBufPutS(out, "</code></pre>\n");
      } else StrBufPutS(out, "```\n");
    } else if (fence.count) {
      MdExportText(&md, &line);
      StrBufPutC(out, '\n');
    } else if (StrsLen(&line) == 3 && !MemCmp(line.a, "---", 3)) {
      if (html) StrBufPutS(out, "<hr>\n");
      else StrBufPutS(out, "---\n");
    } else if (MdPageBreak(&line)) {
      if (html) StrBufPutS(out, "<hr style=\"break-after:page\">\n");
      else StrBufPutS(out, "---\n");
    } else if (MdTableProbe(source, p, &table)) {
      if (html) {
        StrBufPrintf(out, "<table class=\"border-%d\">\n", md.table_border);
        row = MdNextLine(source, p, &line);
        MdNextLine(source, row, &line);
        MdTableSplitRow(&line, cells, MD_TABLE_MAX_COLS);
        for (i = 0; i < table.columns; i++) aligns[i] = MdTableColAlign(&cells[i]);
        row = p;
        number = 0;
        while (row < table.text.b) {
          row = MdNextLine(source, row, &line);
          if (number != 1) {
            tag = "td";
            if (!number) tag = "th";
            StrBufPutS(out, "<tr>");
            n = MdTableSplitRow(&line, cells, MD_TABLE_MAX_COLS);
            for (i = 0; i < n && i < MD_TABLE_MAX_COLS; i++) {
              if (aligns[i] != MD_ALIGN_LEFT)
                StrBufPrintf(out, "<%s style=\"text-align:%s\">", tag, align_names[aligns[i]]);
              else StrBufPrintf(out, "<%s>", tag);
              MdInline(&md, &cells[i]);
              StrBufPrintf(out, "</%s>", tag);
            }
            StrBufPutS(out, "</tr>\n");
          }
          number++;
        }
        StrBufPutS(out, "</table>\n");
      } else {
        StrBufPutS(out, "```\n");
        md.end = source->b;
        MdRenderTable(&md, p);
        StrBufPutS(out, "```\n");
      }
      next = table.text.b;
    } else {
      level = MdTitleLevel(&line);
      if (level) {
        line.a += level;
        StrsTrim(&line);
        if (html) {
          StrBufClear(&slug);
          MdSlug(&slug, &line);
          StrBufPrintf(out, "<h%d id=\"", level);
          MdHtmlEscape(out, &slug);
          StrBufPutS(out, "\">");
        }
        else {
          for (i = 0; i < MinI64(3, level); i++) StrBufPutC(out, '#');
          StrBufPutC(out, ' ');
        }
      } else if (html) StrBufPutS(out, "<p>");
      MdInline(&md, &line);
      if (html) {
        if (level) StrBufPrintf(out, "</h%d>", level);
        else StrBufPutS(out, "</p>");
      }
      StrBufPutC(out, '\n');
    }
    StrBufPutStrs(out, &export.links);
    StrBufClear(&export.links);
    p = next;
  }
  if (fence.count) {
    if (html) StrBufPutS(out, "</code></pre>\n");
    else StrBufPutS(out, "```\n");
  }
  if (html) StrBufPutS(out, "</body></html>\n");
  StrBufFini(&export.links);
  StrBufFini(&slug);
}

#endif
