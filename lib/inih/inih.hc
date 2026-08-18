#ifndef AHOLYC_LIB_INIH_INIH_HC
#define AHOLYC_LIB_INIH_INIH_HC

// Callback based INI parser inspired by inih (https://github.com/benhoyt/inih).
// It never allocates: the input is a borrowed CStrs slice and the handler
// receives section, name and value as slices into it. Sections are
// "[name]", pairs are "name = value" with surrounding whitespace stripped,
// and lines starting with ';' or '#' are comments. Names before any section
// header get an empty section. A line without '=' is reported with a NULL
// value. The handler returns FALSE to stop parsing.
//
//   Bool OnPair(CIni *ini, CStrs *section, CStrs *name, CStrs *value)
//   {
//     ...
//     return TRUE;
//   }
//   CIni ini = IniParseS("[net]\nport = 80\n", &OnPair);
//   if (!ini.ok)
//     "error %d at line %d\n", ini.err, ini.line;

#include "../text/strs.hc"

#define INI_OK 0
#define INI_ERROR_INVALID_ARGS 1
#define INI_ERROR_MISSING_BRACKET 2
#define INI_ERROR_INVALID_DEF 3
#define INI_ERROR_TRAILING_CHARS 4
#define INI_ERROR_HANDLER 5

class CIni;
// Called for every name/value pair; return FALSE to stop parsing.
Bool IniHandler(CIni *ini, CStrs *section, CStrs *name, CStrs *value);

class CIni
{
  IniHandler *handler;
  U8 *user; // for the handler
  I64 line; // 1-based line where parsing stopped
  U8 err;   // INI_OK or the INI_ERROR_* that stopped the parse
  Bool ok;  // whole input parsed and the handler never stopped it
};

// Private: walk the lines and return INI_OK or the first error.
I64 IniScan(CIni *ini, CStrs *text)
{
  CStrs rest;
  CStrs line;
  CStrs section;
  CStrs name;
  CStrs value;
  U8 *close;
  Bool ok;

  if (!ini->handler || !StrsValid(text))
    return INI_ERROR_INVALID_ARGS;
  StrsInit(&rest, text->a, text->b);
  StrsInit(&section, text->a, text->a);
  while (!StrsEmpty(&rest)) {
    ini->line++;
    StrsSplitC(&rest, '\n', &line, &rest);
    StrsTrim(&line);
    if (StrsEmpty(&line) || *line.a == ';' || *line.a == '#') {
      // blank or comment
    } else if (*line.a == '[') {
      close = StrsFindC(&line, ']');
      if (!close)
        return INI_ERROR_MISSING_BRACKET;
      if (close + 1 != line.b)
        return INI_ERROR_TRAILING_CHARS;
      StrsInit(&section, line.a + 1, close);
    } else if (StrsSplitC(&line, '=', &name, &value)) {
      StrsTrim(&name);
      StrsTrim(&value);
      if (StrsEmpty(&name))
        return INI_ERROR_INVALID_DEF;
      ok = ini->handler(ini, &section, &name, &value);
      if (!ok)
        return INI_ERROR_HANDLER;
    } else {
      ok = ini->handler(ini, &section, &line, NULL);
      if (!ok)
        return INI_ERROR_HANDLER;
    }
  }
  return INI_OK;
}

CIni IniParse(CStrs *text, IniHandler *handler, U8 *user=NULL)
{
  CIni ini;

  MemSet(&ini, 0, sizeof(CIni));
  ini.handler = handler;
  ini.user = user;
  ini.err = IniScan(&ini, text);
  ini.ok = ini.err == INI_OK;
  return ini;
}

CIni IniParseS(U8 *string, IniHandler *handler, U8 *user=NULL)
{
  CStrs text;

  StrsInitS(&text, string);
  return IniParse(&text, handler, user);
}

#endif
