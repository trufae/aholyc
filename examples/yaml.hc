#include "../lib/yaml/yaml.hc"

U0 Show(CStrs *slice)
{
  U8 *copy = StrsDup(slice);

  "%s", copy;
  Free(copy);
}

U8 *doc =
  "# server config\n"
  "---\n"
  "name: demo\n"
  "port: 8080\n"
  "debug: true\n"
  "motd: ~\n"
  "tags: [fast, simple]\n"
  "server:\n"
  "  host: 'localhost'\n"
  "  url: http://nopcode.org # no comment\n"
  "limits: {cpu: 2, mem: 512}\n"
  "users:\n"
  "  - name: ada\n"
  "    admin: true\n"
  "  - name: linus\n"
  "    admin: false\n"
  "matrix:\n"
  "  - [1, 2]\n"
  "  - [3, 4]\n";

CYaml yaml = YamlParseS(doc);
CYamlNode *node;
CYamlNode *user;
U8 *text;

if (!yaml.ok)
  "yaml: %s at line %d\n", YamlErrName(yaml.err), yaml.line;

text = YamlStr(YamlGet(yaml.root, "name"));
"name: %s\n", text;
Free(text);
"port: %d\n", YamlI64(YamlGet(yaml.root, "port"));
"debug: %d\n", YamlBool(YamlGet(yaml.root, "debug"));
"motd null: %d\n", YamlIsNull(YamlGet(yaml.root, "motd"));

text = YamlStr(YamlGet(YamlGet(yaml.root, "server"), "url"));
"url: %s\n", text;
Free(text);
"mem: %d\n", YamlI64(YamlGet(YamlGet(yaml.root, "limits"), "mem"));

node = YamlGet(yaml.root, "tags");
"tags(%d):", YamlCount(node);
for (node = node->child; node; node = node->next) {
  " ";
  Show(&node->value);
}
"\n";

for (user = YamlGet(yaml.root, "users")->child; user; user = user->next) {
  node = YamlGet(user, "name");
  "user ";
  Show(&node->value);
  " admin=%d\n", YamlBool(YamlGet(user, "admin"));
}

node = YamlGet(yaml.root, "matrix");
"matrix[1][0]: %d\n", YamlI64(YamlAt(YamlAt(node, 1), 0));
YamlFree(&yaml);

yaml = YamlParseS("bad: [1, 2\n");
"bad: ok=%d %s at line %d\n", yaml.ok, YamlErrName(yaml.err), yaml.line;
YamlFree(&yaml);
