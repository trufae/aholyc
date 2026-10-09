#ifndef AHOLYC_LIB_TEXT_MD_EDIT_HC
#define AHOLYC_LIB_TEXT_MD_EDIT_HC

#include "markdown.hc"
#include "edit.hc"

#define MD_TABLE_INSERT 0
#define MD_TABLE_ADD_ROW 1
#define MD_TABLE_ADD_COL 2
#define MD_TABLE_DEL_ROW 3
#define MD_TABLE_DEL_COL 4
#define MD_TABLE_LEFT 5
#define MD_TABLE_CENTER 6
#define MD_TABLE_RIGHT 7
#define MD_TABLE_BORDER 8

class CMdTable
{
  CStrs text;
  I64 columns, row, column;
};

Bool MdTableProbe(CStrs *text, U8 *p, CMdTable *table);

// Return the state byte in a list task marker, or NULL for ordinary text.
U8 *MdTaskMarker(CStrs *line)
{
  U8 *p = line->a, *start;

  while (p < line->b && *p == ' ') p++;
  while (p < line->b && *p == '>') {
    p++;
    while (p < line->b && *p == ' ') p++;
  }
  if (p == line->b) return NULL;
  if (*p == '-' || *p == '*' || *p == '+') p++;
  else {
    start = p;
    while (p < line->b && *p >= '0' && *p <= '9') p++;
    if (p == start || p - start > 9 || p == line->b || *p != '.' && *p != ')') return NULL;
    p++;
  }
  if (p == line->b || *p != ' ' && *p != '\t') return NULL;
  while (p < line->b && (*p == ' ' || *p == '\t')) p++;
  if (line->b - p < 3 || p[0] != '[' || p[2] != ']' ||
    p[1] != ' ' && p[1] != 'x' && p[1] != 'X') return NULL;
  if (p + 3 < line->b && p[3] != ' ' && p[3] != '\t') return NULL;
  return p + 1;
}

// Locate a task on the source line containing at; fenced code is inert.
I64 MdTaskAt(CStrs *text, I64 at)
{
  U8 *p = text->a, *next, *marker;
  CStrs line;
  CMdBlock code;

  if (at < 0 || at > StrsLen(text)) return -1;
  while (p < text->b) {
    if (MdCodeAt(text, p, &code)) {
      if (at < code.source.b - text->a) return -1;
      next = code.source.b;
    } else {
      next = MdNextLine(text, p, &line);
      if (at < next - text->a || at == StrsLen(text) && next == text->b && text->b[-1] != '\n') {
        marker = MdTaskMarker(&line);
        if (marker) return marker - text->a;
        return -1;
      }
    }
    p = next;
  }
  return -1;
}

// Change only the marker, preserving caret/selection and one undo boundary.
Bool MdEditTask(CEdit *edit, I64 at)
{
  I64 marker = MdTaskAt(&edit->text, at), cursor = edit->cursor, anchor = edit->anchor;
  U8 state = ' ';
  CStrs text;
  Bool changed;

  if (edit->readonly || marker < 0) return FALSE;
  if (edit->text.a[marker] == ' ') state = 'x';
  StrsInitN(&text, &state, 1);
  changed = EditReplace(edit, marker, marker + 1, &text);
  if (changed) { edit->cursor = cursor; edit->anchor = anchor; }
  return changed;
}

// Walk whole paragraphs/known divs, protecting fenced code and tables.
U8 *MdParagraphNext(CStrs *text, U8 *p, CStrs *body, I64 *kind)
{
  CStrs line, trim;
  CMdAlignment aligned;
  CMdBlock code;
  CMdTable table;
  U8 *next, *at;

  *kind = 1;
  if (MdAlignBlock(text, p, &aligned)) { *body = aligned.body; return aligned.source.b; }
  if (MdCodeAt(text, p, &code)) { *kind = -1; *body = code.source; return code.source.b; }
  if (MdTableProbe(text, p, &table)) { *kind = -1; *body = table.text; return table.text.b; }
  next = MdNextLine(text, p, &line); trim = line; StrsTrim(&trim);
  if (StrsEmpty(&trim)) { *kind = 0; StrsInit(body, p, p); return next; }
  if (line.a < line.b && *line.a == '\t') { *kind = -1; StrsInit(body, p, next); return next; }
  if (MdTitleLevel(&line)) { StrsInit(body, p, next); return next; }
  at = next;
  while (at < text->b) {
    next = MdNextLine(text, at, &line); trim = line; StrsTrim(&trim);
    if (StrsEmpty(&trim) || MdAlignOpen(&line) || MdAlignClose(&line) ||
        MdTitleLevel(&line) || MdCodeAt(text, at, &code) || MdTableProbe(text, at, &table)) break;
    at = next;
  }
  StrsInit(body, p, at); return at;
}

// Probe only this line, keeping export and full-document walks linear.
Bool MdTableProbe(CStrs *text, U8 *p, CMdTable *table)
{
  CStrs line, sep, cells[MD_TABLE_MAX_COLS];
  U8 *next = MdNextLine(text, p, &line), *body, *end;
  I64 n;

  if (next >= text->b || !MdTableRowLine(&line)) return FALSE;
  body = MdNextLine(text, next, &sep);
  n = MdTableSplitRow(&line, cells, MD_TABLE_MAX_COLS);
  if (n < 1 || n > MD_TABLE_MAX_COLS || !MdTableIsSep(&sep) ||
    MdTableSplitRow(&sep, cells, MD_TABLE_MAX_COLS) != n) return FALSE;
  end = body;
  while (end < text->b) {
    body = MdNextLine(text, end, &line);
    if (!MdTableRowLine(&line)) break;
    if (MdTableSplitRow(&line, cells, MD_TABLE_MAX_COLS) > n) return FALSE;
    end = body;
  }
  StrsInit(&table->text, p, end);
  table->columns = n;
  table->row = 0;
  table->column = 0;
  return TRUE;
}

Bool MdEditAlign(CEdit *edit, I64 align)
{
  CStrs region, body;
  CStrBuf out;
  U8 *p = edit->text.a, *next;
  I64 start, end, a = StrsLen(&edit->text) + 1, b = 0, kind, base, content;
  I64 cursor = edit->cursor, anchor = edit->anchor, mapped_cursor = cursor, mapped_anchor = anchor, delta;
  Bool selected, hit, change;

  if (edit->readonly || align < 0 || align > MD_ALIGN_JUSTIFY) return FALSE;
  EditSelection(edit, &start, &end); selected = start != end;
  while (p < edit->text.b) {
    next = MdParagraphNext(&edit->text, p, &body, &kind);
    hit = next - edit->text.a > start && p - edit->text.a < end;
    if (!selected) hit = start >= p - edit->text.a &&
      (start < next - edit->text.a || start == StrsLen(&edit->text) && next == edit->text.b);
    if (hit && (kind > 0 || !kind && !selected)) {
      a = MinI64(a, p - edit->text.a); b = next - edit->text.a;
    }
    p = next;
  }
  if (StrsEmpty(&edit->text)) a = b = 0;
  if (a > b) return FALSE;
  StrsInit(&region, edit->text.a + a, edit->text.a + b);
  StrBufInit(&out); p = region.a;
  do {
    kind = 0; body.a = body.b = p; next = p;
    if (p < region.b) next = MdParagraphNext(&region, p, &body, &kind);
    base = StrsLen(&out);
    if (kind > 0 || !selected && !kind) {
      StrBufPrintf(&out, "%s\n", md_align_fences[align]);
      base = StrsLen(&out); content = StrsLen(&body);
      if (content && body.b[-1] == '\n') content--;
      if (cursor >= p - edit->text.a && cursor <= next - edit->text.a)
        mapped_cursor = a + base + MaxI64(0, MinI64(content, cursor - (body.a - edit->text.a)));
      if (anchor >= p - edit->text.a && anchor <= next - edit->text.a)
        mapped_anchor = a + base + MaxI64(0, MinI64(content, anchor - (body.a - edit->text.a)));
      StrBufPutStrs(&out, &body);
      if (StrsEmpty(&body) || body.b[-1] != '\n') StrBufPutC(&out, '\n');
      StrBufPutS(&out, ":::\n");
    } else {
      if (cursor >= p - edit->text.a && cursor <= next - edit->text.a) mapped_cursor = a + base + cursor - (p - edit->text.a);
      if (anchor >= p - edit->text.a && anchor <= next - edit->text.a) mapped_anchor = a + base + anchor - (p - edit->text.a);
      StrBufPutN(&out, p, next - p);
    }
    p = next;
  } while (p < region.b);
  delta = StrsLen(&out) - (b - a);
  if (cursor > b) mapped_cursor = cursor + delta;
  if (anchor > b) mapped_anchor = anchor + delta;
  change = EditReplace(edit, a, b, &out);
  if (change) { edit->cursor = mapped_cursor; edit->anchor = mapped_anchor; }
  StrBufFini(&out); return change;
}

// Locate a table and the cell containing a source byte; ignore fenced code.
Bool MdTableAt(CStrs *text, I64 at, CMdTable *table)
{
  U8 *p = text->a, *next, *start;
  CStrs line, cells[MD_TABLE_MAX_COLS];
  I64 n, row, i;
  CMdFence fence;

  while (p < text->b) {
    next = MdNextLine(text, p, &line);
    MdFenceStep(&fence, &line);
    if (!fence.count && MdTableProbe(text, p, table)) {
      if (at >= p - text->a && at < table->text.b - text->a) {
        row = 0;
        while (p < table->text.b) {
          next = MdNextLine(text, p, &line);
          if (at >= p - text->a && at <= line.b - text->a) {
            table->row = row;
            n = MdTableSplitRow(&line, cells, MD_TABLE_MAX_COLS);
            for (i = 0; i < n && i < table->columns; i++) {
              start = cells[i].a;
              while (start > line.a && (start[-1] == ' ' || start[-1] == '\t')) start--;
              if (at >= start - text->a) table->column = i;
            }
            return TRUE;
          }
          row++;
          p = next;
        }
        return TRUE;
      }
      next = table->text.b;
    }
    p = next;
  }
  return FALSE;
}

// Move in row order, skipping the Markdown alignment row. At either end the
// caret stays in the table; navigation never changes its contents or history.
Bool MdTableMove(CEdit *edit, Bool back=FALSE)
{
  CMdTable table;
  CStrs line, cells[MD_TABLE_MAX_COLS];
  U8 *p;
  I64 row = 0, i, n, previous = -1, at;
  Bool found = FALSE;

  if (!MdTableAt(&edit->text, edit->cursor, &table) || table.row == 1) return FALSE;
  p = table.text.a;
  while (p < table.text.b) {
    p = MdNextLine(&table.text, p, &line);
    if (row != 1) {
      n = MdTableSplitRow(&line, cells, MD_TABLE_MAX_COLS);
      for (i = 0; i < n; i++) {
        at = cells[i].a - edit->text.a;
        // Keep an empty cell's caret between its padding spaces when possible.
        if (StrsEmpty(&cells[i]) && cells[i].a > line.a &&
          (cells[i].a[-1] == ' ' || cells[i].a[-1] == '\t')) at--;
        if (found || row == table.row && i == table.column && back) {
          if (back && previous >= 0) at = previous;
          edit->cursor = at; edit->anchor = -1; edit->typing = FALSE;
          return TRUE;
        }
        if (row == table.row && i == table.column) found = TRUE;
        previous = at;
      }
    }
    row++;
  }
  if (found) { edit->cursor = previous; edit->anchor = -1; edit->typing = FALSE; }
  return found;
}

Bool MdEditTable(CEdit *edit, I64 action, I64 border=0)
{
  CMdTable table;
  CStrBuf out;
  CStrs line, cells[MD_TABLE_MAX_COLS], insert;
  U8 *p, *next, *style[4] = {"single", "round", "ascii", "none"};
  I64 row = 0, i, n, a, b, selected = -1;
  Bool ok;

  if (edit->readonly) return FALSE;
  if (action == MD_TABLE_INSERT) {
    StrsInitS(&insert, "\n|  |  |\n| --- | --- |\n|  |  |\n");
    EditSelection(edit, &a, &b);
    ok = EditInsert(edit, &insert);
    if (ok) { edit->anchor = -1; edit->cursor = a + 3; }
    return ok;
  }
  if (!MdTableAt(&edit->text, edit->cursor, &table)) return FALSE;
  if (action == MD_TABLE_DEL_COL && table.columns == 1) return FALSE;
  if (action == MD_TABLE_ADD_COL && table.columns == MD_TABLE_MAX_COLS) return FALSE;
  if (action == MD_TABLE_DEL_ROW && table.row < 2) return FALSE;
  a = table.text.a - edit->text.a;
  b = table.text.b - edit->text.a;
  StrBufInit(&out);
  if (action == MD_TABLE_BORDER) {
    StrBufPrintf(&out, "<!-- table-border: %s -->\n", style[border & 3]);
    selected = StrsLen(&out) + edit->cursor - a;
    // Replace our preceding hint when there is one, rather than accumulating.
    if (a > 0) {
      p = edit->text.a + a - 1;
      while (p > edit->text.a && p[-1] != '\n') p--;
      if (MdStarts(p, table.text.a, "<!-- table-border: "))
        a = p - edit->text.a;
    }
    StrBufPutStrs(&out, &table.text);
  } else {
    p = table.text.a;
    while (p < table.text.b) {
      next = MdNextLine(&table.text, p, &line);
      n = MdTableSplitRow(&line, cells, MD_TABLE_MAX_COLS);
      if (n > table.columns) { StrBufFini(&out); return FALSE; }
      if (action != MD_TABLE_DEL_ROW || row != table.row) {
        StrBufPutC(&out, '|');
        for (i = 0; i < table.columns; i++) {
          if (action != MD_TABLE_DEL_COL || i != table.column) {
            StrBufPutC(&out, ' ');
            if (row == table.row && i == table.column) selected = StrsLen(&out);
            if (row == 1 && i == table.column && action >= MD_TABLE_LEFT && action <= MD_TABLE_RIGHT) {
              if (action != MD_TABLE_RIGHT) StrBufPutC(&out, ':');
              StrBufPutS(&out, "---");
              if (action != MD_TABLE_LEFT) StrBufPutC(&out, ':');
            } else if (i < n) StrBufPutStrs(&out, &cells[i]);
            else if (row == 1) StrBufPutS(&out, "---");
            StrBufPutS(&out, " |");
          }
          if (action == MD_TABLE_ADD_COL && i == table.column) {
            if (row == 1) StrBufPutS(&out, " --- |");
            else StrBufPutS(&out, "  |");
          }
        }
        StrBufPutC(&out, '\n');
      }
      if (action == MD_TABLE_ADD_ROW && row == MaxI64(1, table.row)) {
        selected = StrsLen(&out) + 2;
        StrBufPutC(&out, '|');
        for (i = 0; i < table.columns; i++) StrBufPutS(&out, "  |");
        StrBufPutC(&out, '\n');
      }
      p = next;
      row++;
    }
  }
  ok = EditReplace(edit, a, b, &out);
  if (ok) edit->cursor = a + MaxI64(0, selected);
  StrBufFini(&out);
  return ok;
}

// Format each selected line as one history step; Markdown emphasis cannot
// span block boundaries. A second application removes the same wrappers.
Bool MdEditWrap(CEdit *edit, CStrs *prefix, CStrs *suffix)
{
  I64 a, b, plen = StrsLen(prefix), slen = StrsLen(suffix), length;
  CStrs selection, line;
  CStrBuf out;
  U8 *p, *next;
  Bool toggle = TRUE, changed;

  EditSelection(edit, &a, &b);
  if (!MemChr(edit->text.a + a, '\n', b - a)) return EditWrap(edit, prefix, suffix);
  if (EditWrapped(edit, prefix, suffix)) { a -= plen; b += slen; }
  StrsInit(&selection, edit->text.a + a, edit->text.a + b);
  p = selection.a;
  while (p < selection.b) {
    p = MdNextLine(&selection, p, &line);
    length = StrsLen(&line);
    if (length && (length < plen + slen || MemCmp(line.a, prefix->a, plen) ||
        MemCmp(line.b - slen, suffix->a, slen))) toggle = FALSE;
  }
  StrBufInit(&out);
  p = selection.a;
  while (p < selection.b) {
    next = MdNextLine(&selection, p, &line);
    if (!StrsEmpty(&line)) {
      if (toggle) { line.a += plen; line.b -= slen; }
      else StrBufPutStrs(&out, prefix);
      StrBufPutStrs(&out, &line);
      if (!toggle) StrBufPutStrs(&out, suffix);
    }
    if (next > p && next[-1] == '\n') StrBufPutC(&out, '\n');
    p = next;
  }
  changed = EditReplace(edit, a, b, &out);
  if (changed) {
    edit->anchor = a;
    edit->cursor = a + StrsLen(&out);
  }
  StrBufFini(&out);
  return changed;
}

U0 MdSlug(CStrBuf *out, CStrs *title)
{
  U8 *p;
  I64 c;

  for (p = title->a; p < title->b; p++) {
    c = *p;
    if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
    if (c == ' ' || c == '\t') {
      if (StrsLen(out) && out->b[-1] != '-') StrBufPutC(out, '-');
    } else if (c >= 128 || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-' || c == '_')
      StrBufPutC(out, c);
  }
}

// The nearest heading starts the section; children belong to their parent.
U0 MdSection(CStrs *text, I64 at, CStrs *section)
{
  U8 *p = text->a, *next;
  CStrs line;
  CMdFence fence;
  I64 level = 0, current;

  *section = *text;
  while (p < text->b) {
    next = MdNextLine(text, p, &line);
    MdFenceStep(&fence, &line);
    current = 0;
    if (!fence.count) current = MdTitleLevel(&line);
    if (current) {
      if (p - text->a <= at) { section->a = p; level = current; }
      else if (!level || current <= level) { section->b = p; break; }
    }
    p = next;
  }
}

#endif
