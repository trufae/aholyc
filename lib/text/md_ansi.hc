#ifndef AHOLYC_LIB_TEXT_MD_ANSI_HC
#define AHOLYC_LIB_TEXT_MD_ANSI_HC

// Terminal backend for lib/text/markdown.hc: collects the rendered text in
// a CStrBuf and turns MD_STYLE_* events into ANSI escapes. With color=FALSE
// only bold/italic/strike attributes are emitted when attrs=TRUE, otherwise
// the output is plain text.
//
//   CMdAnsi ansi;
//   CMarkdown md;
//   MdAnsiInit(&ansi, TRUE);
//   MarkdownInit(&md, &MdAnsiText, &MdAnsiStyle, &ansi);
//   MarkdownRender(&md, source);
//   PutS(ansi.out.a);           // or take ownership: StrBufTake(&ansi.out)
//   MdAnsiFini(&ansi);

#include "markdown.hc"
#include "strbuf.hc"

class CMdAnsi
{
  CStrBuf out;
  Bool color; // colors and backgrounds
  Bool attrs; // bold, italic and strikethrough
};

U0 MdAnsiInit(CMdAnsi *ansi, Bool color=TRUE, Bool attrs=TRUE)
{
  StrBufInit(&ansi->out);
  ansi->color = color;
  ansi->attrs = attrs;
}

U0 MdAnsiFini(CMdAnsi *ansi)
{
  StrBufFini(&ansi->out);
}

U0 MdAnsiText(CMarkdown *md, CStrs *text)
{
  CMdAnsi *ansi = md->user(CMdAnsi *);

  StrBufPutStrs(&ansi->out, text);
}

U0 MdAnsiStyle(CMarkdown *md, I64 style, I64 on)
{
  CMdAnsi *ansi = md->user(CMdAnsi *);
  U8 *seq = NULL;

  if (style == MD_STYLE_BOLD && ansi->attrs) {
    if (on) seq = "\x1B[1m"; else seq = "\x1B[22m";
  } else if (style == MD_STYLE_ITALIC && ansi->attrs) {
    if (on) seq = "\x1B[3m"; else seq = "\x1B[23m";
  } else if (style == MD_STYLE_STRIKE && ansi->attrs) {
    if (on) seq = "\x1B[9m"; else seq = "\x1B[29m";
  } else if (!ansi->color) {
    return;
  } else if (style == MD_STYLE_CODE || style == MD_STYLE_CODE_BLOCK) {
    if (on) seq = "\x1B[48;5;234m\x1B[37m"; else seq = "\x1B[49m\x1B[0m";
  } else if (style == MD_STYLE_TITLE) {
    if (on) seq = "\x1B[1m"; else seq = "\x1B[0m";
  } else if (style == MD_STYLE_TITLE_MARK) {
    if (on) seq = "\x1B[1;34m"; else seq = "\x1B[0m";
  } else if (style == MD_STYLE_BANNER) {
    if (on == 1) seq = "\x1B[30m\x1B[42m";
    else if (on == 2) seq = "\x1B[30m\x1B[44m";
    else if (on > 2) seq = "\x1B[34m\x1B[46m";
    else seq = "\x1B[49m\x1B[0m";
  }
  if (seq)
    StrBufPutS(&ansi->out, seq);
}

#endif
