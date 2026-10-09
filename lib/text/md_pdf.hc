#ifndef AHOLYC_LIB_TEXT_MD_PDF_HC
#define AHOLYC_LIB_TEXT_MD_PDF_HC

#include "../io/process.hc"
#include "../io/replace.hc"
#include "strbuf.hc"
#include "markdown.hc"

// Pandoc's LaTeX engines share paper, geometry and font-size variables.
class CMdPdf
{
  I64 paper, engine, font_size;
  I64 margins[4]; // top, right, bottom, left, in millimeters
  Bool landscape, toc;
};

U8 *md_pdf_papers[4] = {"a4", "a5", "letter", "legal"};
U8 *md_pdf_engines[3] = {"xelatex", "pdflatex", "lualatex"};

U0 MdPdfDefault(CMdPdf *options)
{
  I64 i;

  MemSet(options, 0, sizeof(CMdPdf));
  options->font_size = 11;
  for (i = 0; i < 4; i++) options->margins[i] = 20;
}

Bool MdPdfValid(CMdPdf *options)
{
  I64 widths[4] = {210, 148, 216, 216}, heights[4] = {297, 210, 279, 356};
  I64 i, w, h;

  if (options->paper < 0 || options->paper >= 4 || options->engine < 0 ||
    options->engine >= 3 || options->font_size < 10 || options->font_size > 12) return FALSE;
  for (i = 0; i < 4; i++) if (options->margins[i] < 0 || options->margins[i] > 100) return FALSE;
  w = widths[options->paper]; h = heights[options->paper];
  if (options->landscape) { i = w; w = h; h = i; }
  return options->margins[1] + options->margins[3] < w - 20 &&
    options->margins[0] + options->margins[2] < h - 20;
}

Bool MdPdfQuote(CStrBuf *command, U8 *argument)
{
  U8 *p;

  #ifdef IS_WINDOWS
  // cmd.exe expands these even inside quotes; reject them in file paths.
  for (p = argument; *p; p++)
    if (*p == '%' || *p == '!' || *p == '"' || *p == '\r' || *p == '\n') return FALSE;
  StrBufPrintf(command, "\"%s\"", argument);
  #else
  StrBufPutC(command, '\'');
  for (p = argument; *p; p++) {
    if (*p == '\'') StrBufPutS(command, "'\\''");
    else StrBufPutC(command, *p);
  }
  StrBufPutC(command, '\'');
  #endif
  return TRUE;
}

Bool MdPdfCommand(CStrBuf *command, CMdPdf *options, U8 *output, U8 *resources)
{
  if (!MdPdfValid(options)) return FALSE;
  StrBufPrintf(command, "pandoc --from=markdown --to=latex --standalone --pdf-engine=%s --output ",
    md_pdf_engines[options->engine]);
  if (!MdPdfQuote(command, output)) return FALSE;
  StrBufPutS(command, " --resource-path ");
  if (!MdPdfQuote(command, resources)) return FALSE;
  StrBufPrintf(command, " -V papersize=%s -V fontsize=%dpt -V geometry=top=%dmm,right=%dmm,bottom=%dmm,left=%dmm",
    md_pdf_papers[options->paper], options->font_size, options->margins[0],
    options->margins[1], options->margins[2], options->margins[3]);
  if (options->landscape) StrBufPutS(command, ",landscape");
  if (options->toc) StrBufPutS(command, " --toc");
  StrBufPutS(command, " 2>&1");
  return TRUE;
}

// Translate our known alignment divs into LaTeX environments for Pandoc.
// Fenced code and every other source byte remain literal input.
U0 MdPdfInput(CStrs *source, CStrBuf *out)
{
  CMdAlignment aligned;
  CMdBlock code;
  CStrs line;
  U8 *p = source->a, *next;
  U8 *begins[4] = {"\\begin{flushleft}", "\\begin{flushright}", "\\begin{center}",
    "\\begingroup\\leftskip=0pt\\rightskip=0pt\\parfillskip=0pt plus 1fil\\relax"};
  U8 *ends[4] = {"\\end{flushleft}", "\\end{flushright}", "\\end{center}", "\\par\\endgroup"};

  while (p < source->b) {
    if (MdCodeAt(source, p, &code)) {
      StrBufPutStrs(out, &code.source); next = code.source.b;
    } else if (MdAlignBlock(source, p, &aligned)) {
      StrBufPrintf(out, "\n```{=latex}\n%s\n```\n\n", begins[aligned.align]);
      MdPdfInput(&aligned.body, out);
      StrBufPrintf(out, "\n```{=latex}\n%s\n```\n\n", ends[aligned.align]);
      next = aligned.source.b;
    } else {
      next = MdNextLine(source, p, &line); StrBufPutN(out, p, next - p);
    }
    p = next;
  }
}

// Feed the current buffer, including unsaved edits. Capture diagnostics so the
// terminal stays intact, and replace the destination only after a valid result.
Bool MdPdfExport(CStrs *source, U8 *path, U8 *resources, CMdPdf *options, CStrBuf *error)
{
  CProcess process;
  CStrBuf command, input;
  CStrs pdf;
  U8 *temporary = NULL, *stream = NULL, *bytes;
  U8 buffer[4096];
  I64 i, n, size, code;
  Bool ok = FALSE, written;

  StrBufClear(error);
  if (!MdPdfValid(options) || !StrsValid(source) || !path || !*path || !resources) {
    StrBufPutS(error, "Invalid PDF settings or destination."); return FALSE;
  }
  for (i = 0; i < 100 && !stream; i++) {
    Free(temporary);
    temporary = MStrPrint("%s.aholyc-%X.pdf", path, RandI64);
    stream = fopen(temporary, "wbx");
  }
  if (!stream) {
    Free(temporary); StrBufPutS(error, "Cannot write to the PDF destination."); return FALSE;
  }
  fclose(stream);
  StrBufInit(&command);
  StrBufInit(&input); MdPdfInput(source, &input);
  if (MdPdfCommand(&command, options, temporary, resources) && ProcessOpen(&process, command.a)) {
    written = ProcessWrite(&process, input.a, StrsLen(&input));
    ProcessCloseInput(&process);
    while ((n = ProcessRead(&process, buffer, sizeof(buffer))) > 0) {
      if (StrsLen(error) < 4096) StrBufPutN(error, buffer, MinI64(n, 4096 - StrsLen(error)));
    }
    code = ProcessClose(&process);
    if (written && n == 0 && !code) {
      bytes = FileRead(temporary, &size);
      if (bytes && size >= 5 && !MemCmp(bytes, "%PDF-", 5)) {
        StrsInitN(&pdf, bytes, size);
        ok = FileReplace(path, &pdf);
      }
      Free(bytes);
    }
  }
  if (ok) StrBufClear(error);
  else if (StrsEmpty(error)) StrBufPutS(error, "PDF export failed. Check Pandoc, the selected LaTeX engine and destination.");
  remove(temporary); Free(temporary);
  StrBufFini(&command); StrBufFini(&input);
  return ok;
}

#endif
