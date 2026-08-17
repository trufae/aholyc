#ifndef AHOLYC_LIB_TEXT_MARKDOWN_HC
#define AHOLYC_LIB_TEXT_MARKDOWN_HC

// Markdown layout engine, ported from radare2's r_str_md2txt. It parses
// titles, horizontal rules, pipe tables, fenced and tab-indented code blocks,
// `code spans`, **bold**, *italic* and ~~strike~~, wraps long lines at
// md->width columns and streams the result as events: laid out text slices
// and MD_STYLE_* on/off notifications. It never allocates and never emits
// escape codes; the caller passes the callbacks of an output backend such as
// lib/text/md_ansi.hc.
//
//   #include "lib/text/markdown.hc"
//   #include "lib/text/md_ansi.hc"
//
//   CMdAnsi ansi;
//   CMarkdown md;
//   MdAnsiInit(&ansi, TRUE);                    // TRUE: colors
//   MarkdownInit(&md, &MdAnsiText, &MdAnsiStyle, &ansi);
//   md.utf8 = TRUE;                             // box drawing rules/tables
//   MarkdownRender(&md, "# Title\n\nHello **world**\n");
//   PutS(ansi.out.a);
//   MdAnsiFini(&ansi);
//
// Everything prefixed with Md is internal.

#include "strs.hc"

// Style events. `on` is 0 when the style ends; for MD_STYLE_TITLE,
// MD_STYLE_TITLE_MARK and MD_STYLE_BANNER it carries the heading level.
#define MD_STYLE_BOLD 1
#define MD_STYLE_ITALIC 2
#define MD_STYLE_STRIKE 3
#define MD_STYLE_CODE 4       // inline `code`
#define MD_STYLE_CODE_BLOCK 5 // one line of a code block
#define MD_STYLE_TITLE 6      // heading text
#define MD_STYLE_TITLE_MARK 7 // the leading '#' characters
#define MD_STYLE_BANNER 8     // slide title band (also its filler lines)
#define MD_STYLE_HR 9         // horizontal rule
#define MD_STYLE_TABLE 10     // table borders
#define MD_STYLE_COUNT 11

#define MD_ALIGN_LEFT 0
#define MD_ALIGN_RIGHT 1
#define MD_ALIGN_CENTER 2
#define MD_TABLE_MAX_COLS 32

class CMarkdown
{
  U8 *user;                                    // for the callbacks
  U0 (*text)(CMarkdown *md, CStrs *text);
  U0 (*style)(CMarkdown *md, I64 style, I64 on);
  Bool utf8;         // unicode rules and table borders
  Bool utf8_curvy;   // rounded table corners (needs utf8)
  Bool slide_titles; // render titles as full width bands
  I64 width;         // wrap column, 75 by default
  // render state
  U8 *end;
  I64 col;
  Bool codeblock;
  Bool codeblockline;
  Bool bold;
  Bool italic;
  Bool strike;
};

U0 MarkdownInit(CMarkdown *md, U0 (*text)(CMarkdown *md, CStrs *text),
  U0 (*style)(CMarkdown *md, I64 style, I64 on), U8 *user=NULL)
{
  MemSet(md, 0, sizeof(CMarkdown));
  md->text = text;
  md->style = style;
  md->user = user;
  md->width = 75;
}

// --- output ----------------------------------------------------------------

U0 MdText(CMarkdown *md, U8 *a, U8 *b)
{
  CStrs slice;

  if (b > a && md->text) {
    StrsInit(&slice, a, b);
    md->text(md, &slice);
  }
}

U0 MdTextS(CMarkdown *md, U8 *text)
{
  MdText(md, text, text + StrLen(text));
}

U0 MdRepeat(CMarkdown *md, U8 *text, I64 count)
{
  while (count-- > 0)
    MdTextS(md, text);
}

U0 MdStyle(CMarkdown *md, I64 style, I64 on)
{
  if (md->style)
    md->style(md, style, on);
}

// Display width in runes.
I64 MdWidth(CStrs *text)
{
  U8 *p = text->a;
  I64 width = 0;

  while (p < text->b) {
    if ((*p & 0xC0) != 0x80)
      width++;
    p++;
  }
  return width;
}

// The current line as a slice, without its newline.
U0 MdLine(CMarkdown *md, U8 *b, CStrs *line)
{
  StrsInit(line, b, md->end);
  b = StrsFindC(line, '\n');
  if (b)
    line->b = b;
}

// --- inline: emphasis, strike, code spans ----------------------------------

I64 MdEmphasis(CMarkdown *md, U8 *b, Bool *bold, Bool *italic)
{
  I64 m = *b;
  U8 *end = md->end;
  U8 *p;

  if (m != '*' && m != '_')
    return 0;
  if (b + 1 < end && b[1] == m) {
    if (*bold) {
      MdStyle(md, MD_STYLE_BOLD, 0);
      *bold = FALSE;
      return 2;
    }
    p = b + 2;
    while (p + 1 < end && *p != '\n') {
      if (p[0] == m && p[1] == m) {
        MdStyle(md, MD_STYLE_BOLD, 1);
        *bold = TRUE;
        return 2;
      }
      p++;
    }
    return 0;
  }
  if (*italic) {
    MdStyle(md, MD_STYLE_ITALIC, 0);
    *italic = FALSE;
    return 1;
  }
  p = b + 1;
  while (p < end && *p != '\n') {
    if (p + 1 < end && p[0] == m && p[1] == m) {
      p += 2;
    } else if (p[0] == m) {
      MdStyle(md, MD_STYLE_ITALIC, 1);
      *italic = TRUE;
      return 1;
    } else {
      p++;
    }
  }
  return 0;
}

I64 MdStrikethrough(CMarkdown *md, U8 *b, Bool *strike)
{
  U8 *end = md->end;
  U8 *p;

  if (b + 1 >= end || b[0] != '~' || b[1] != '~')
    return 0;
  if (*strike) {
    MdStyle(md, MD_STYLE_STRIKE, 0);
    *strike = FALSE;
    return 2;
  }
  p = b + 2;
  while (p + 1 < end && *p != '\n') {
    if (p[0] == '~' && p[1] == '~') {
      MdStyle(md, MD_STYLE_STRIKE, 1);
      *strike = TRUE;
      return 2;
    }
    p++;
  }
  return 0;
}

I64 MdBacktickRun(U8 *b, U8 *end)
{
  I64 n = 0;

  while (b + n < end && b[n] == '`')
    n++;
  return n;
}

// Emit a `code span`; *cols receives its display width.
I64 MdCodeSpan(CMarkdown *md, U8 *b, I64 *cols)
{
  U8 *end = md->end;
  I64 ticks = MdBacktickRun(b, end);
  CStrs code;
  U8 *p;
  I64 n;

  if (ticks < 1)
    return 0;
  p = b + ticks;
  code.a = p;
  while (p < end && *p != '\n') {
    if (*p == '`') {
      n = MdBacktickRun(p, end);
      if (n == ticks) {
        code.b = p;
        MdStyle(md, MD_STYLE_CODE, 1);
        MdText(md, code.a, code.b);
        MdStyle(md, MD_STYLE_CODE, 0);
        if (cols)
          *cols = MdWidth(&code);
        return p + ticks - b;
      }
      p += n;
    } else {
      p++;
    }
  }
  return 0;
}

// Render the inline markup of a slice; "\|" is unescaped for table cells.
U0 MdInline(CMarkdown *md, CStrs *text)
{
  U8 *saved_end = md->end;
  U8 *b = text->a;
  Bool bold = FALSE;
  Bool italic = FALSE;
  Bool strike = FALSE;
  I64 n;

  md->end = text->b;
  while (b < md->end) {
    n = 0;
    if (*b == '`')
      n = MdCodeSpan(md, b, NULL);
    else if (*b == '*' || *b == '_')
      n = MdEmphasis(md, b, &bold, &italic);
    else if (*b == '~')
      n = MdStrikethrough(md, b, &strike);
    else if (*b == '\\' && b + 1 < md->end && b[1] == '|')
      n = 1;
    if (n > 0) {
      b += n;
    } else {
      MdText(md, b, b + 1);
      b++;
    }
  }
  if (bold)
    MdStyle(md, MD_STYLE_BOLD, 0);
  if (italic)
    MdStyle(md, MD_STYLE_ITALIC, 0);
  if (strike)
    MdStyle(md, MD_STYLE_STRIKE, 0);
  md->end = saved_end;
}

// Display width of a slice once its inline markup is rendered: run the
// inline renderer with a counting text callback and no style callback.
U0 MdCountText(CMarkdown *md, CStrs *text)
{
  I64 *count = md->user(I64 *);

  *count += MdWidth(text);
}

I64 MdInlineWidth(CStrs *text)
{
  CMarkdown counter;
  I64 count = 0;

  MarkdownInit(&counter, &MdCountText, NULL, &count);
  MdInline(&counter, text);
  return count;
}

// --- block: horizontal rule ------------------------------------------------

I64 MdRenderHr(CMarkdown *md, U8 *b)
{
  CStrs line;
  CStrs dashes;
  U8 *p;
  I64 width;

  MdLine(md, b, &line);
  dashes = line;
  StrsTrim(&dashes);
  p = dashes.a;
  while (p < dashes.b && *p == '-')
    p++;
  if (p - dashes.a < 3 || p != dashes.b)
    return 0;
  width = md->width / 2;
  MdRepeat(md, " ", (md->width - width) / 2);
  MdStyle(md, MD_STYLE_HR, 1);
  if (md->utf8)
    MdRepeat(md, "─", width);
  else
    MdRepeat(md, "-", width);
  MdStyle(md, MD_STYLE_HR, 0);
  MdTextS(md, "\n");
  if (line.b < md->end)
    return line.b + 1 - b;
  return line.b - b;
}

// --- block: table ----------------------------------------------------------

Bool MdTableIsSep(CStrs *line)
{
  Bool has_dash = FALSE;
  U8 *p;

  for (p = line->a; p < line->b; p++) {
    if (*p == '-')
      has_dash = TRUE;
    else if (*p != '|' && *p != ':' && *p != ' ' && *p != '\t')
      return FALSE;
  }
  return has_dash;
}

// Split a table row into trimmed cell slices. Returns the cell count.
I64 MdTableSplitRow(CStrs *line, CStrs *cells, I64 max)
{
  I64 count = 0;
  Bool leading_pipe;
  CStrs row = *line;
  U8 *p;
  U8 *start;

  StrsTrim(&row);
  p = row.a;
  leading_pipe = p < row.b && *p == '|';
  if (leading_pipe)
    p++;
  while (count < max) {
    start = p;
    while (p < row.b && *p != '|') {
      if (*p == '\\' && p + 1 < row.b && p[1] == '|')
        p++;
      p++;
    }
    StrsInit(&cells[count], start, p);
    StrsTrim(&cells[count]);
    count++;
    if (p >= row.b)
      break;
    p++;
    if (p >= row.b) {
      if (count < max)
        StrsInit(&cells[count++], p, p);
      break;
    }
  }
  if (leading_pipe && count > 0 && StrsEmpty(&cells[count - 1]))
    count--;
  return count;
}

I64 MdTableColAlign(CStrs *cell)
{
  Bool left = StrsAt(cell, 0) == ':';
  Bool right = StrsLast(cell) == ':';

  if (left && right)
    return MD_ALIGN_CENTER;
  if (right)
    return MD_ALIGN_RIGHT;
  return MD_ALIGN_LEFT;
}

// A table body row is a non-blank line containing a pipe.
Bool MdTableRowLine(CStrs *line)
{
  CStrs row = *line;

  StrsTrim(&row);
  return !StrsEmpty(&row) && StrsFindC(&row, '|') != NULL;
}

U0 MdTableBorder(CMarkdown *md, I64 *widths, I64 ncols, U8 *l, U8 *m, U8 *r,
  U8 *h)
{
  I64 i;

  MdStyle(md, MD_STYLE_TABLE, 1);
  MdTextS(md, l);
  for (i = 0; i < ncols; i++) {
    MdRepeat(md, h, widths[i] + 2);
    if (i + 1 < ncols)
      MdTextS(md, m);
  }
  MdTextS(md, r);
  MdStyle(md, MD_STYLE_TABLE, 0);
  MdTextS(md, "\n");
}

U0 MdTableRow(CMarkdown *md, CStrs *cells, I64 ncells, I64 *widths,
  I64 *aligns, I64 ncols, U8 *v)
{
  CStrs empty;
  CStrs *cell;
  I64 i;
  I64 pad;
  I64 left;

  StrsInitN(&empty, "", 0);
  MdStyle(md, MD_STYLE_TABLE, 1);
  MdTextS(md, v);
  MdStyle(md, MD_STYLE_TABLE, 0);
  for (i = 0; i < ncols; i++) {
    cell = &empty;
    if (i < ncells)
      cell = &cells[i];
    pad = widths[i] - MdInlineWidth(cell);
    if (aligns[i] == MD_ALIGN_RIGHT)
      left = pad;
    else if (aligns[i] == MD_ALIGN_CENTER)
      left = pad / 2;
    else
      left = 0;
    MdRepeat(md, " ", left + 1);
    MdInline(md, cell);
    MdRepeat(md, " ", pad - left + 1);
    MdStyle(md, MD_STYLE_TABLE, 1);
    MdTextS(md, v);
    MdStyle(md, MD_STYLE_TABLE, 0);
  }
  MdTextS(md, "\n");
}

// Two passes over the rows: measure column widths, then draw. Nothing is
// stored, so tables of any size render without allocations.
I64 MdRenderTable(CMarkdown *md, U8 *b)
{
  CStrs header;
  CStrs sep;
  CStrs line;
  CStrs cells[MD_TABLE_MAX_COLS];
  I64 widths[MD_TABLE_MAX_COLS];
  I64 aligns[MD_TABLE_MAX_COLS];
  I64 ncols;
  I64 nseps;
  I64 nc;
  I64 i;
  I64 w;
  U8 *body;
  U8 *p;
  U8 *tl;
  U8 *tm;
  U8 *tr;
  U8 *ml;
  U8 *mm;
  U8 *mr;
  U8 *bl;
  U8 *bm;
  U8 *br;
  U8 *h;
  U8 *v;

  MdLine(md, b, &header);
  if (header.b >= md->end || !StrsFindC(&header, '|'))
    return 0;
  MdLine(md, header.b + 1, &sep);
  if (!MdTableIsSep(&sep))
    return 0;
  ncols = MdTableSplitRow(&header, cells, MD_TABLE_MAX_COLS);
  if (!ncols)
    return 0;
  for (i = 0; i < ncols; i++)
    widths[i] = MdInlineWidth(&cells[i]);
  nseps = MdTableSplitRow(&sep, cells, MD_TABLE_MAX_COLS);
  for (i = 0; i < ncols; i++) {
    aligns[i] = MD_ALIGN_LEFT;
    if (i < nseps)
      aligns[i] = MdTableColAlign(&cells[i]);
  }

  body = sep.b;
  if (body < md->end)
    body++;
  p = body;
  while (p < md->end) {
    MdLine(md, p, &line);
    if (!MdTableRowLine(&line))
      break;
    nc = MdTableSplitRow(&line, cells, MD_TABLE_MAX_COLS);
    for (i = 0; i < nc && i < ncols; i++) {
      w = MdInlineWidth(&cells[i]);
      if (w > widths[i])
        widths[i] = w;
    }
    p = line.b;
    if (p < md->end)
      p++;
  }

  if (md->utf8) {
    if (md->utf8_curvy) {
      tl = "╭"; tr = "╮"; bl = "╰"; br = "╯";
    } else {
      tl = "┌"; tr = "┐"; bl = "└"; br = "┘";
    }
    tm = "┬"; ml = "├"; mm = "┼"; mr = "┤"; bm = "┴"; h = "─"; v = "│";
  } else {
    tl = "+"; tm = "+"; tr = "+"; ml = "+"; mm = "+"; mr = "+";
    bl = "+"; bm = "+"; br = "+"; h = "-"; v = "|";
  }
  MdTableBorder(md, widths, ncols, tl, tm, tr, h);
  MdTableSplitRow(&header, cells, MD_TABLE_MAX_COLS);
  MdTableRow(md, cells, ncols, widths, aligns, ncols, v);
  MdTableBorder(md, widths, ncols, ml, mm, mr, h);
  while (body < p) {
    MdLine(md, body, &line);
    nc = MdTableSplitRow(&line, cells, MD_TABLE_MAX_COLS);
    MdTableRow(md, cells, nc, widths, aligns, ncols, v);
    body = line.b + 1;
  }
  MdTableBorder(md, widths, ncols, bl, bm, br, h);
  return p - b;
}

// --- block: titles ---------------------------------------------------------

I64 MdTitleLevel(CStrs *line)
{
  I64 level = 0;
  I64 next;

  while (level < 6 && StrsAt(line, level) == '#')
    level++;
  if (level < 1)
    return 0;
  next = StrsAt(line, level);
  if (next == ' ' || next == '\t' || next == '\r' || !next)
    return level;
  return 0;
}

// A banner filler line: `cols` spaces then end of the band.
U0 MdBannerLine(CMarkdown *md, I64 level, I64 cols)
{
  MdStyle(md, MD_STYLE_BANNER, level);
  MdRepeat(md, " ", cols);
  MdStyle(md, MD_STYLE_BANNER, 0);
  MdTextS(md, "\n");
}

U0 MdSlideTitle(CMarkdown *md, CStrs *title, I64 level)
{
  I64 fill = md->width + 2 - MdWidth(title);

  if (level == 1) {
    MdStyle(md, MD_STYLE_BANNER, 1);
    MdTextS(md, "  ");
    MdText(md, title->a, title->b);
    MdRepeat(md, " ", fill);
    MdStyle(md, MD_STYLE_BANNER, 0);
    MdTextS(md, "\n\n");
    return;
  }
  MdBannerLine(md, 2, md->width + 4);
  MdStyle(md, MD_STYLE_BANNER, level);
  MdTextS(md, "  ");
  MdText(md, title->a, title->b);
  MdRepeat(md, " ", fill);
  MdStyle(md, MD_STYLE_BANNER, 0);
  MdTextS(md, "\n");
  MdBannerLine(md, 2, md->width + 4);
}

I64 MdRenderTitle(CMarkdown *md, U8 *b)
{
  CStrs line;
  CStrs title;
  I64 level;

  MdLine(md, b, &line);
  level = MdTitleLevel(&line);
  if (level < 1)
    return 0;
  StrsInit(&title, line.a + level, line.b);
  StrsTrim(&title);
  if (md->slide_titles) {
    MdSlideTitle(md, &title, level);
  } else {
    MdStyle(md, MD_STYLE_TITLE_MARK, level);
    MdText(md, line.a, line.a + level);
    MdStyle(md, MD_STYLE_TITLE_MARK, 0);
    if (!StrsEmpty(&title)) {
      MdTextS(md, " ");
      MdStyle(md, MD_STYLE_TITLE, level);
      MdText(md, title.a, title.b);
      MdStyle(md, MD_STYLE_TITLE, 0);
    }
    MdTextS(md, "\n");
  }
  if (line.b < md->end)
    return line.b + 1 - b;
  return line.b - b;
}

// --- main loop -------------------------------------------------------------

U0 MdCodeBlockStart(CMarkdown *md)
{
  MdTextS(md, "  ");
  MdStyle(md, MD_STYLE_CODE_BLOCK, 1);
  MdTextS(md, " ");
}

// Close whatever is open on the current line.
U0 MdLineEnd(CMarkdown *md)
{
  if (md->codeblock) {
    if (md->col == 0)
      MdCodeBlockStart(md);
    MdRepeat(md, " ", md->width - 4 - md->col);
    MdStyle(md, MD_STYLE_CODE_BLOCK, 0);
  } else {
    if (md->bold)
      MdStyle(md, MD_STYLE_BOLD, 0);
    if (md->italic)
      MdStyle(md, MD_STYLE_ITALIC, 0);
    if (md->strike)
      MdStyle(md, MD_STYLE_STRIKE, 0);
  }
  md->bold = FALSE;
  md->italic = FALSE;
  md->strike = FALSE;
}

U0 MdNewline(CMarkdown *md)
{
  MdLineEnd(md);
  MdTextS(md, "\n");
  md->col = 0;
  if (md->codeblockline) {
    md->codeblock = FALSE;
    md->codeblockline = FALSE;
  }
}

// Render a markdown slice, streaming events to the callbacks.
U0 MarkdownRenderStrs(CMarkdown *md, CStrs *input)
{
  U8 *b = input->a;
  I64 ch;
  I64 n;
  I64 code_cols;

  md->end = input->b;
  md->col = 0;
  md->codeblock = FALSE;
  md->codeblockline = FALSE;
  md->bold = FALSE;
  md->italic = FALSE;
  md->strike = FALSE;
  if (md->width < 8)
    md->width = 75;

  while (b < md->end) {
    ch = *b;
    if (ch == '\n') {
      MdNewline(md);
      b++;
      goto next;
    }
    if (ch == '\t') {
      if (md->col == 0) {
        md->codeblock = TRUE;
        md->codeblockline = TRUE;
      } else {
        MdTextS(md, "  ");
      }
      b++;
      goto next;
    }
    if (ch == '\r') {
      b++;
      goto next;
    }
    if (md->col > md->width) {
      // soft wrap: break at a space, or hyphenate
      if (ch == ' ') {
        MdNewline(md);
        b++;
      } else {
        if (md->codeblock)
          md->col = 1;
        else
          MdTextS(md, "-");
        MdNewline(md);
      }
      goto next;
    }
    if (md->col == 0) {
      if (b + 2 < md->end && b[0] == '`' && b[1] == '`' && b[2] == '`') {
        while (b < md->end && *b != '\n')
          b++;
        md->codeblock = !md->codeblock;
        if (b < md->end)
          b++;
        goto next;
      }
      if (!md->codeblock) {
        n = MdRenderTitle(md, b);
        if (n > 0) {
          b += n;
          goto next;
        }
        n = MdRenderHr(md, b);
        if (n > 0) {
          b += n;
          goto next;
        }
        n = MdRenderTable(md, b);
        if (n > 0) {
          b += n;
          goto next;
        }
      }
      if (md->codeblock)
        MdCodeBlockStart(md);
      else
        MdTextS(md, "  ");
    }
    if (!md->codeblock && ch == '`') {
      code_cols = 0;
      n = MdCodeSpan(md, b, &code_cols);
      if (n > 0) {
        b += n;
        md->col += code_cols;
        goto next;
      }
    }
    if (!md->codeblock && (ch == '*' || ch == '_')) {
      n = MdEmphasis(md, b, &md->bold, &md->italic);
      if (n > 0) {
        b += n;
        md->col++;
        goto next;
      }
    }
    if (!md->codeblock && ch == '~') {
      n = MdStrikethrough(md, b, &md->strike);
      if (n > 0) {
        b += n;
        md->col++;
        goto next;
      }
    }
    // count runes, not bytes, so UTF-8 text wraps at the right column
    if ((ch & 0xC0) != 0x80)
      md->col++;
    MdText(md, b, b + 1);
    b++;
    next:;
  }
  if (md->col > 0)
    MdLineEnd(md);
}

U0 MarkdownRender(CMarkdown *md, U8 *text)
{
  CStrs input;

  if (StrsInitS(&input, text))
    MarkdownRenderStrs(md, &input);
}

#endif
