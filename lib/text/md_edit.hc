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

// Locate a table and the cell containing a source byte; ignore fenced code.
Bool MdTableAt(CStrs *text, I64 at, CMdTable *table)
{
  U8 *p = text->a, *next;
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
            for (i = 0; i < n && i < table->columns; i++)
              if (at >= cells[i].a - text->a) table->column = i;
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
