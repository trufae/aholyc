#include "../lib/regex/regex.hc"

CRegex regex;
CRegexMatch match;
U8 output[128];
I64 needed;

RegexInit(&regex);
if (!RegexCompile(&regex, "[A-Za-z_][A-Za-z0-9_]*"))
  return 1;
if (RegexMatch(&regex, "123 hello_42!", &match))
  "match=%d..%d\n", match.start, match.end;

RegexCompile(&regex, "[0-9]+");
needed = RegexReplace(&regex, "x12 y345", "<$0>", output, sizeof(output));
"replace=%s (%d)\n", output, needed;
"full=%d search=%d\n", RegexFullMatch(&regex, "12345"),
  RegexMatch(&regex, "no digits", &match);
RegexCompile(&regex, "^(👋|🌍)+$");
"emoji=%d\n", RegexFullMatch(&regex, "👋🌍👋");
RegexFini(&regex);
