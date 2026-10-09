#ifndef AHOLYC_LIB_TEXT_MD_BLOCK_HC
#define AHOLYC_LIB_TEXT_MD_BLOCK_HC

// Bounded block scanning shared by rendering, navigation and export.
class CMdFence
{
  I64 mark, count;
};
class CMdBlock
{
  CStrs source, code, language;
};

U8 *MdNextLine(CStrs *text, U8 *at, CStrs *line)
{
  U8 *end = MemChr(at, '\n', text->b - at);

  if (!end) end = text->b;
  StrsInit(line, at, end);
  if (line->b > line->a && line->b[-1] == '\r') line->b--;
  if (end < text->b) end++;
  return end;
}

// Returns 1 for an opening fence, -1 for its matching close, 0 otherwise.
I64 MdFenceStep(CMdFence *fence, CStrs *line, CStrs *language=NULL)
{
  U8 *p = line->a, *start;
  I64 spaces = 0, count, mark;

  while (p < line->b && *p == ' ' && spaces < 3) { p++; spaces++; }
  if (p == line->b || (*p != '`' && *p != '~')) return 0;
  mark = *p; start = p;
  while (p < line->b && *p == mark) p++;
  count = p - start;
  if (count < 3) return 0;
  if (fence->count) {
    while (p < line->b && (*p == ' ' || *p == '\t')) p++;
    if (mark != fence->mark || count < fence->count || p != line->b) return 0;
    fence->count = 0;
    return -1;
  }
  if (mark == '`' && MemChr(p, '`', line->b - p)) return 0;
  fence->mark = mark; fence->count = count;
  if (language) { StrsInit(language, p, line->b); StrsTrim(language); }
  return 1;
}

Bool MdCodeAt(CStrs *text, U8 *p, CMdBlock *block)
{
  CMdFence fence;
  CStrs line;
  U8 *next = MdNextLine(text, p, &line), *end;

  if (MdFenceStep(&fence, &line, &block->language) != 1) return FALSE;
  block->source.a = p;
  block->code.a = next;
  while (next < text->b) {
    end = MdNextLine(text, next, &line);
    if (MdFenceStep(&fence, &line) == -1) {
      block->code.b = next;
      block->source.b = end;
      return TRUE;
    }
    next = end;
  }
  block->code.b = text->b;
  block->source.b = text->b;
  return TRUE;
}

Bool MdPageBreak(CStrs *line)
{
  CStrs trim = *line;

  StrsTrim(&trim);
  return StrsLen(&trim) == 18 && !MemCmp(trim.a, "<!-- pagebreak -->", 18);
}

Bool MdCodeWord(I64 ch)
{
  return ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z' || ch == '_' ||
    ch >= '0' && ch <= '9';
}

// A deliberately small lexer: keywords, numbers, strings and comments.
// The language label is preserved; no language runtime or plugin is loaded.
U0 MdCodeLine(CMarkdown *md, CStrs *line, Bool *comment)
{
  U8 *p = line->a, *start;
  U8 *words = " if else for while do switch case break return class struct enum typedef extern public static const import from def fn function let var void int char bool true false NULL U0 U8 U16 U32 U64 I8 I16 I32 I64 F64 Bool try catch throw new delete sizeof include define " ;
  CStrs token;
  I64 style, quote;
  U8 *word;

  while (p < line->b) {
    start = p; style = 0;
    if (*comment || MdStarts(p, line->b, "/*")) {
      if (!*comment) p += 2;
      *comment = TRUE;
      while (p < line->b && !MdStarts(p, line->b, "*/")) p++;
      if (p < line->b) { p += 2; *comment = FALSE; }
      style = 3;
    } else if (MdStarts(p, line->b, "//") || *p == '#') { p = line->b; style = 3; }
    else if (*p == '"' || *p == '\'') {
      quote = *p++;
      while (p < line->b) {
        if (*p == '\\' && p + 1 < line->b) p += 2;
        else if (*p++ == quote) break;
      }
      style = 2;
    } else if (*p >= '0' && *p <= '9') {
      while (p < line->b && (MdCodeWord(*p) || *p == '.')) p++;
      style = 4;
    } else if (MdCodeWord(*p)) {
      while (p < line->b && MdCodeWord(*p)) p++;
      // Match whole identifiers without temporary allocation.
      word = words;
      while (*word) {
        while (*word == ' ') word++;
        U8 *end = word;
        while (*end && *end != ' ') end++;
        if (end - word == p - start && !MemCmp(word, start, p - start)) style = 1;
        word = end;
      }
    } else p++;
    md->source = start;
    if (style) MdStyle(md, MD_STYLE_CODE_TOKEN, style);
    MdText(md, start, p);
    if (style) MdStyle(md, MD_STYLE_CODE_TOKEN, 0);
  }
}

#endif
