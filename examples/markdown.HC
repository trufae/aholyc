#include "../lib/text/markdown.hc"
#include "../lib/text/md_ansi.hc"

// A second backend: emit style events as tags, like a UI toolkit would map
// them to fonts and colors.
U0 TagText(CMarkdown *md, CStrs *text)
{
  StrBufPutStrs(md->user(CStrBuf *), text);
}

U0 TagStyle(CMarkdown *md, I64 style, I64 on)
{
  U8 *names[MD_STYLE_COUNT] = {"", "b", "i", "s", "code", "pre", "h", "hmark",
      "banner", "hr", "table"};

  if (on)
    StrBufPrintf(md->user(CStrBuf *), "<%s%d>", names[style], on);
  else
    StrBufPrintf(md->user(CStrBuf *), "</%s>", names[style]);
}

U0 MarkdownExample()
{
  U8 *source = "# Title\n\n## Sub *title*\n\nSome **bold** and _italic_ and ~~gone~~ text with `code`.\n\n---\n\n| Name | Value | Note |\n|:-----|------:|:----:|\n| a | 1 | left |\n| bb | **22** | center \\| pipe |\n\n```\nint main() { return 0; }\n```\n\tindented code\nA very long paragraph line that keeps going and going so that the renderer is forced to wrap it around at the configured column width limit.\n";
  CMarkdown md;
  CMdAnsi ansi;
  CStrBuf tags;

  // plain text
  MdAnsiInit(&ansi, FALSE, FALSE);
  MarkdownInit(&md, &MdAnsiText, &MdAnsiStyle, &ansi);
  MarkdownRender(&md, source);
  PutS(ansi.out.a);
  MdAnsiFini(&ansi);

  // attributes and box drawing, narrow
  MdAnsiInit(&ansi, FALSE);
  md.utf8 = TRUE;
  md.width = 40;
  MarkdownRender(&md, source);
  PutS(ansi.out.a);
  MdAnsiFini(&ansi);

  // colors, slide titles, curvy tables
  MdAnsiInit(&ansi);
  md.slide_titles = TRUE;
  md.utf8_curvy = TRUE;
  MarkdownRender(&md, "# Big\n### Small\n| a | b |\n|---|---|\n| 1 | 2 |\n\ttab code\n");
  PutS(ansi.out.a);
  MdAnsiFini(&ansi);

  // custom backend
  StrBufInit(&tags);
  MarkdownInit(&md, &TagText, &TagStyle, &tags);
  MarkdownRender(&md, "## Hi *there*\n\n| a | b |\n|---|---|\n| `x` | ~~y~~ |\n\n\tcode\n");
  PutS(tags.a);
  StrBufFini(&tags);
}

MarkdownExample;
