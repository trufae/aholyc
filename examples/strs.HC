#include "../lib/text/strs.hc"

I64 failures = 0;

U0 Check(Bool condition, U8 *name)
{
  if (!condition) {
    "FAIL %s\n", name;
    failures++;
  }
}

U8 raw[7] = {'a', 'b', 0, 'c', 'd', 'e', 'f'};
U8 middle[3] = {0, 'c', 'd'};
U8 padded[6] = {' ', '\t', 'i', 'd', ' ', '\n'};
U8 tokens[9] = {',', 'o', 'n', 'e', ',', ',', 't', 'w', 'o'};
U8 path[6] = {'a', ':', ':', 'b', ':', ':'};
U8 ident[6] = {'a', 'b', 'c', '_', '9', '!'};
CStrs slice;
CStrs needle;
CStrs part;
CStrs prefix;
CStrs suffix;
CStrs separators;
CStrs token;
CStrs head;
CStrs tail;
U8 *copy;

Check(StrsInitN(&slice, raw, sizeof(raw)) && StrsLen(&slice) == 7 &&
  StrsAt(&slice, 2) == 0 && StrsLast(&slice) == 'f',
  "explicit length and embedded nul");
StrsInitN(&needle, middle, sizeof(middle));
Check(StrsFind(&slice, &needle) == raw + 2, "bounded substring search");
Check(StrsFindC(&slice, 'd') == raw + 4, "bounded byte search");
Check(StrsSub(&slice, 2, 5, &part) && StrsEquals(&part, &needle),
  "subslice and equality");
StrsInitS(&prefix, "ab");
StrsInitS(&suffix, "ef");
Check(StrsStartsWith(&slice, &prefix) && StrsEndsWith(&slice, &suffix),
  "prefix and suffix");
copy = StrsDup(&slice);
Check(copy && !MemCmp(copy, raw, sizeof(raw)) && !copy[sizeof(raw)],
  "nul-terminated duplicate");
Free(copy);

StrsInitN(&part, padded, sizeof(padded));
StrsTrim(&part);
Check(StrsEqualsS(&part, "id"), "ascii trim");

StrsInitN(&slice, tokens, sizeof(tokens));
StrsInitS(&separators, ",");
Check(StrsNextToken(&slice, &separators, &token) &&
  StrsEqualsS(&token, "one"), "first token");
Check(StrsNextToken(&slice, &separators, &token) &&
  StrsEqualsS(&token, "two"), "second token");
Check(!StrsNextToken(&slice, &separators, &token), "token end");

StrsInitN(&slice, path, sizeof(path));
StrsInitS(&separators, "::");
Check(StrsSplit(&slice, &separators, &head, &tail) &&
  StrsEqualsS(&head, "a") && StrsLen(&tail) == 3 && tail.a[0] == 'b',
  "substring split");

StrsInitN(&slice, ident, sizeof(ident));
Check(StrsTakeIdent(&slice, &part) && StrsEqualsS(&part, "abc_9") &&
  StrsLen(&slice) == 1 && StrsAt(&slice, 0) == '!', "identifier take");
Check(!StrsInitN(&part, raw, -1) && StrsEmpty(&part),
  "invalid length rejected");

if (failures)
  Exit(1);
"strs ok\n";
