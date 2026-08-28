#include "lib/r2pipe/r2pipe.hc"
#include "lib/json/query.hc"

CR2Pipe r2;
U8 *reply;
U8 *arch;
CJsonValue value;
Bool ok;

ok = R2PipeOpen(&r2, "/bin/ls");
if (!ok) {
  "r2pipe open failed: %s\n", r2.error;
  Exit(1);
}

reply = R2PipeCmd(&r2, "?V");
if (reply) {
  "radare2 version: %s", reply;
}

ok = R2PipeCmdJ(&r2, "ij");
if (ok) {
  if (JsonPathGet(&r2.json, "$.bin.arch", &value) &&
      value.type == JSON_TYPE_STRING) {
    arch = JsonValueStringNew(&value);
    "ij reports arch: %s\n", arch;
    Free(arch);
  } else {
    "no binarch or broken json\n";
  }
  "ij JSON size: %d bytes\n", r2.json.length;
} else {
  "ij failed: %s\n", r2.error;
}

R2PipeClose(&r2);
"r2pipe ok\n";
