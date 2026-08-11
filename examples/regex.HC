#include "../lib/regex/regex.hc"

CRegex regex;
CRegexMatch *item;
U8 output[128];
I64 needed;
I64 matches;

RegexInit(&regex);
if (!RegexCompile(&regex, "[A-Za-z_][A-Za-z0-9_]*"))
  return 1;
item = RegexFind(&regex, "123 hello_42!");
if (item)
  "match=%d..%d\n", item->start, item->end;

RegexCompile(&regex, "[0-9]+");
needed = RegexReplace(&regex, "x12 y345", "<$0>", output, sizeof(output));
"replace=%s (%d)\n", output, needed;
matches = 0;
item = RegexFind(&regex, "x12 y345");
for (; item; item = RegexNext(item))
  matches++;
"stream=%d\n", matches;
"full=%d search=%d\n", RegexFullMatch(&regex, "12345"),
  RegexFind(&regex, "no digits") != NULL;
RegexCompile(&regex, "^(👋|🌍)+$");
"emoji=%d\n", RegexFullMatch(&regex, "👋🌍👋");
RegexFini(&regex);
