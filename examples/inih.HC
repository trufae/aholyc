#include "../lib/inih/inih.hc"

U0 Show(CStrs *slice)
{
  U8 *copy = StrsDup(slice);

  "%s", copy;
  Free(copy);
}

Bool OnPair(CIni *ini, CStrs *section, CStrs *name, CStrs *value)
{
  I64 *count = ini->user;

  (*count)++;
  "%d: [", ini->line;
  Show(section);
  "] ";
  Show(name);
  if (value) {
    " = '";
    Show(value);
    "'";
  }
  "\n";
  return !StrsEqualsS(name, "stop");
}

I64 count = 0;
CIni ini;
CStrs text;
U8 *doc = "; comment\ntop = level\n\n[ user ]\r\n  name = Ada Lovelace  \n"
  "# hash\nempty =\nflag\n[last]\nkey=value=more\n";

ini = IniParseS(doc, &OnPair, &count);
"parse: %d count: %d err: %d\n", ini.ok, count, ini.err;

StrsInitS(&text, "[a\nx=1\n");
ini = IniParse(&text, &OnPair);
"missing bracket: %d err: %d line: %d\n", ini.ok, ini.err, ini.line;
ini = IniParseS("[a] b\n", &OnPair);
"trailing: %d err: %d\n", ini.ok, ini.err;
ini = IniParseS("\n\n = 1\n", &OnPair);
"no name: %d err: %d line: %d\n", ini.ok, ini.err, ini.line;
ini = IniParseS("a=1\nstop=2\nb=3\n", &OnPair, &count);
"stopped: %d err: %d line: %d\n", ini.ok, ini.err, ini.line;
"empty: %d err: %d\n", IniParseS("", &OnPair).ok, IniParseS("", &OnPair).err;
"no handler: %d\n", IniParse(&text, NULL).ok;
