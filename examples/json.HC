#include "lib/json/pj.hc"
#include "lib/json/query.hc"

I64 failures = 0;

U0 Check(Bool condition, U8 *name)
{
  if (!condition) {
    "FAIL %s\n", name;
    failures++;
  }
}

CPj *pj = PjNew;
CPj *bare = PjNew;
CJsonDecoder decoder;
CJsonValue root;
CJsonValue value;
U8 *json;
U8 *text;

PjO(pj);
PjKs(pj, "name", "aholyc \"q\"\n");
PjKn(pj, "count", -3);
PjKd(pj, "ratio", 0.5);
PjKb(pj, "ok", TRUE);
PjKnull(pj, "none");
PjKa(pj, "tags");
PjS(pj, "holyc");
PjN(pj, 7);
PjO(pj);
PjEnd(pj);
PjEnd(pj);
PjKo(pj, "nested");
PjKj(pj, "raw", "[1,2]");
PjEnd(pj);
PjEnd(pj);
json = PjDrain(pj);
Check(!StrCmp(json,
    "{\"name\":\"aholyc \\\"q\\\"\\n\",\"count\":-3,\"ratio\":0.5,\"ok\":true,\"none\":null,\"tags\":[\"holyc\",7,{}],\"nested\":{\"raw\":[1,2]}}"),
  "pj document");
JsonDecoderInit(&decoder, json);
Check(JsonDecode(&decoder, &root), "pj output decodes");
Check(JsonPathGet(&root, "$.tags[1]", &value) &&
  JsonValueStringEquals(&value, "holyc") == FALSE &&
  value.type == JSON_TYPE_NUMBER, "pj array item");
text = NULL;
if (JsonPathGet(&root, "$.name", &value))
  text = JsonValueStringNew(&value);
Check(text && !StrCmp(text, "aholyc \"q\"\n"), "JsonValueStringNew");
Free(text);
Free(json);

// A builder without an enclosing container yields comma separated values
// that PjJ splices into another document.
PjS(bare, "a");
PjN(bare, 1);
Check(!StrCmp(PjString(bare), "\"a\",1"), "bare values");
pj = PjNew;
PjA(pj);
PjJ(pj, PjString(bare));
PjS(pj, "b");
PjEnd(pj);
Check(!StrCmp(PjString(pj), "[\"a\",1,\"b\"]"), "pj splice");
PjReset(pj);
PjO(pj);
PjEnd(pj);
Check(!StrCmp(PjString(pj), "{}"), "pj reset");
PjFree(pj);
PjFree(bare);

if (failures)
  Exit(1);
"json ok\n";
