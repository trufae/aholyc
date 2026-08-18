#ifndef AHOLYC_LIB_YAML_YAML_HC
#define AHOLYC_LIB_YAML_YAML_HC

// Small YAML subset parser built on CStrs slices. YamlParse returns a CYaml
// whose node tree borrows the input buffer: keys and scalar values are
// [a, b) slices into it, so the buffer must outlive the tree and nothing is
// copied until the caller asks for YamlStr. Only the nodes themselves are
// allocated; YamlFree releases them.
//
// Supported: comments ('#' at start of line or preceded by a blank), block
// mappings and sequences nested by indentation (spaces), "- key: value"
// inline map items, flow collections "[a, b]" and "{a: b}" as leaf values,
// quoted scalars (quotes stripped, no escape processing), and a leading
// "---" document marker.
//
// Not supported (deliberately): anchors, tags, block scalars (| and >),
// multi-document streams, escapes inside quotes, and '#' or ':' inside
// quoted scalars on block lines.
//
//   CYaml yaml = YamlParseS("port: 80\ntags: [a, b]\n");
//   if (!yaml.ok)
//     "yaml: %s at line %d\n", YamlErrName(yaml.err), yaml.line;
//   "port %d\n", YamlI64(YamlGet(yaml.root, "port"));
//   YamlFree(&yaml);

#include "../text/strs.hc"

#define YAML_OK 0
#define YAML_ERR_ARGS 1
#define YAML_ERR_NESTING 2
#define YAML_ERR_FLOW 3
#define YAML_ERR_TRAILING 4

#define YAML_SCALAR 0
#define YAML_SEQ 1
#define YAML_MAP 2

#define YAML_MAX_DEPTH 64

class CYamlNode
{
  I64 type;
  CStrs key;        // set when the parent is a map
  CStrs value;      // scalar text, quotes stripped
  CYamlNode *child; // first child of a seq or map
  CYamlNode *next;  // next sibling
};

class CYaml
{
  CYamlNode *root;
  I64 line; // 1-based line where parsing stopped
  U8 err;   // YAML_OK or the YAML_ERR_* that stopped the parse
  Bool ok;
};

// Private parser state: rest of the input plus one buffered line.
class CYamlParser
{
  CStrs rest;
  CStrs line; // current line, comment and indent stripped
  I64 indent;
  I64 line_no;
  Bool have;
  I64 err;
  I64 err_line;
};

U0 YamlNodeFree(CYamlNode *node)
{
  CYamlNode *next;

  while (node) {
    next = node->next;
    YamlNodeFree(node->child);
    Free(node);
    node = next;
  }
}

U0 YamlFree(CYaml *yaml)
{
  if (!yaml)
    return;
  YamlNodeFree(yaml->root);
  yaml->root = NULL;
}

CYamlNode *YamlFail(CYamlParser *parser, I64 err)
{
  if (!parser->err) {
    parser->err = err;
    parser->err_line = parser->line_no;
  }
  return NULL;
}

CYamlNode *YamlNode(I64 type)
{
  CYamlNode *node = CAlloc(sizeof(CYamlNode));

  node->type = type;
  return node;
}

U0 YamlSkipBlank(CStrs *slice)
{
  while (slice->a < slice->b && (*slice->a == ' ' || *slice->a == '\t'))
    slice->a++;
}

U0 YamlUnquote(CStrs *slice)
{
  I64 quote = StrsAt(slice, 0);

  if (StrsLen(slice) >= 2 && (quote == '"' || quote == '\'') &&
    StrsLast(slice) == quote) {
      slice->a++;
      slice->b--;
    }
}

CYamlNode *YamlScalarNode(CStrs *value)
{
  CYamlNode *node = YamlNode(YAML_SCALAR);

  StrsTrim(value);
  YamlUnquote(value);
  node->value = *value;
  return node;
}

// Buffer the next meaningful line: skips blanks, comments and "---",
// counts the indentation and trims the content.
Bool YamlPeek(CYamlParser *parser)
{
  CStrs line;
  U8 *hash;
  CStrs tail;

  while (!parser->have && !StrsEmpty(&parser->rest)) {
    parser->line_no++;
    StrsSplitC(&parser->rest, '\n', &line, &parser->rest);
    hash = StrsFindC(&line, '#');
    while (hash && hash != line.a && hash[-1] != ' ' && hash[-1] != '\t') {
      StrsInit(&tail, hash + 1, line.b);
      hash = StrsFindC(&tail, '#');
    }
    if (hash)
      line.b = hash;
    parser->indent = 0;
    while (line.a < line.b && *line.a == ' ') {
      line.a++;
      parser->indent++;
    }
    StrsTrim(&line);
    if (!StrsEmpty(&line) && !StrsEqualsS(&line, "---")) {
      parser->line = line;
      parser->have = TRUE;
    }
  }
  return parser->have;
}

Bool YamlIsDash(CYamlParser *parser)
{
  return StrsAt(&parser->line, 0) == '-' &&
    (StrsLen(&parser->line) == 1 || StrsAt(&parser->line, 1) == ' ');
}

// First ':' followed by a blank or end of line, so URLs in values survive.
U8 *YamlKeyColon(CStrs *line)
{
  CStrs slice = *line;
  U8 *colon;

  while ((colon = StrsFindC(&slice, ':'))) {
    if (colon + 1 == line->b || colon[1] == ' ')
      return colon;
    slice.a = colon + 1;
  }
  return NULL;
}

// Take one flow scalar, quoted or running until a stop character.
Bool YamlFlowScalar(CStrs *slice, U8 *stops, CStrs *result)
{
  CStrs stop_set;
  I64 quote;
  U8 *close;

  YamlSkipBlank(slice);
  result->a = slice->a;
  quote = StrsAt(slice, 0);
  if (quote == '"' || quote == '\'') {
    slice->a++;
    close = StrsFindC(slice, quote);
    if (!close)
      return FALSE;
    slice->a = close + 1;
  } else {
    StrsInitS(&stop_set, stops);
    while (slice->a < slice->b && !StrsHasC(&stop_set, *slice->a))
      slice->a++;
  }
  result->b = slice->a;
  return TRUE;
}

// Recursive flow value: "[a, b]", "{a: b}" or a scalar, advancing *slice.
CYamlNode *YamlFlow(CYamlParser *parser, CStrs *slice, I64 depth)
{
  CYamlNode *node;
  CYamlNode *item;
  CYamlNode **tail;
  CStrs key;
  I64 open;
  I64 close;

  if (depth >= YAML_MAX_DEPTH)
    return YamlFail(parser, YAML_ERR_NESTING);
  YamlSkipBlank(slice);
  open = StrsAt(slice, 0);
  if (open != '[' && open != '{') {
    if (!YamlFlowScalar(slice, ",]}", &key))
      return YamlFail(parser, YAML_ERR_FLOW);
    return YamlScalarNode(&key);
  }
  if (open == '[') {
    node = YamlNode(YAML_SEQ);
    close = ']';
  } else {
    node = YamlNode(YAML_MAP);
    close = '}';
  }
  tail = &node->child;
  slice->a++;
  YamlSkipBlank(slice);
  while (StrsAt(slice, 0) != close) {
    if (StrsEmpty(slice)) {
      YamlNodeFree(node);
      return YamlFail(parser, YAML_ERR_FLOW);
    }
    if (node->type == YAML_MAP) {
      if (!YamlFlowScalar(slice, ":", &key) || StrsAt(slice, 0) != ':') {
        YamlNodeFree(node);
        return YamlFail(parser, YAML_ERR_FLOW);
      }
      slice->a++;
      StrsTrim(&key);
      YamlUnquote(&key);
    }
    item = YamlFlow(parser, slice, depth + 1);
    if (!item) {
      YamlNodeFree(node);
      return NULL;
    }
    if (node->type == YAML_MAP)
      item->key = key;
    *tail = item;
    tail = &item->next;
    YamlSkipBlank(slice);
    if (StrsAt(slice, 0) == ',') {
      slice->a++;
      YamlSkipBlank(slice);
    } else if (StrsAt(slice, 0) != close) {
      YamlNodeFree(node);
      return YamlFail(parser, YAML_ERR_FLOW);
    }
  }
  slice->a++;
  return node;
}

// An inline value after "key: " or a whole scalar line.
CYamlNode *YamlValueNode(CYamlParser *parser, CStrs *value, I64 depth)
{
  CYamlNode *node;
  I64 first;

  YamlSkipBlank(value);
  first = StrsAt(value, 0);
  if (first != '[' && first != '{')
    return YamlScalarNode(value);
  node = YamlFlow(parser, value, depth);
  YamlSkipBlank(value);
  if (node && !StrsEmpty(value)) {
    YamlNodeFree(node);
    return YamlFail(parser, YAML_ERR_FLOW);
  }
  return node;
}

// Parse the block starting at the next line if it is indented at least
// min_indent; an absent block yields an empty scalar (null) node.
CYamlNode *YamlBlock(CYamlParser *parser, I64 min_indent, I64 depth)
{
  CYamlNode *node;
  CYamlNode *item;
  CYamlNode **tail;
  CStrs key;
  CStrs value;
  U8 *colon;
  U8 *start;
  I64 block_indent;

  if (depth >= YAML_MAX_DEPTH)
    return YamlFail(parser, YAML_ERR_NESTING);
  if (!YamlPeek(parser) || parser->indent < min_indent)
    return YamlNode(YAML_SCALAR);
  block_indent = parser->indent;
  if (YamlIsDash(parser)) {
    node = YamlNode(YAML_SEQ);
    tail = &node->child;
    while (YamlPeek(parser) && parser->indent == block_indent &&
      YamlIsDash(parser)) {
        start = parser->line.a;
        parser->line.a++;
        YamlSkipBlank(&parser->line);
        if (StrsEmpty(&parser->line)) {
          parser->have = FALSE;
          item = YamlBlock(parser, block_indent + 1, depth + 1);
        } else {
          // "- key: value": reparse the remainder as a block at its column
          parser->indent = block_indent + parser->line.a - start;
          item = YamlBlock(parser, parser->indent, depth + 1);
        }
        if (!item) {
          YamlNodeFree(node);
          return NULL;
        }
        *tail = item;
        tail = &item->next;
      }
    return node;
  }
  if (YamlKeyColon(&parser->line)) {
    node = YamlNode(YAML_MAP);
    tail = &node->child;
    while (YamlPeek(parser) && parser->indent == block_indent &&
      !YamlIsDash(parser) && (colon = YamlKeyColon(&parser->line))) {
        StrsInit(&key, parser->line.a, colon);
        StrsInit(&value, colon + 1, parser->line.b);
        StrsTrim(&key);
        YamlUnquote(&key);
        StrsTrim(&value);
        parser->have = FALSE;
        if (!StrsEmpty(&value)) {
          item = YamlValueNode(parser, &value, depth + 1);
        } else if (YamlPeek(parser) && (parser->indent > block_indent ||
            parser->indent == block_indent && YamlIsDash(parser))) {
              item = YamlBlock(parser, parser->indent, depth + 1);
            } else {
              item = YamlNode(YAML_SCALAR);
            }
        if (!item) {
          YamlNodeFree(node);
          return NULL;
        }
        item->key = key;
        *tail = item;
        tail = &item->next;
      }
    return node;
  }
  value = parser->line;
  parser->have = FALSE;
  return YamlValueNode(parser, &value, depth);
}

CYaml YamlParse(CStrs *text)
{
  CYaml yaml;
  CYamlParser parser;

  MemSet(&yaml, 0, sizeof(CYaml));
  MemSet(&parser, 0, sizeof(CYamlParser));
  if (!StrsValid(text)) {
    yaml.err = YAML_ERR_ARGS;
    return yaml;
  }
  parser.rest = *text;
  yaml.root = YamlBlock(&parser, 0, 0);
  if (!parser.err && YamlPeek(&parser))
    YamlFail(&parser, YAML_ERR_TRAILING);
  if (parser.err) {
    YamlFree(&yaml);
    yaml.err = parser.err;
    yaml.line = parser.err_line;
  }
  yaml.ok = yaml.err == YAML_OK;
  return yaml;
}

CYaml YamlParseS(U8 *string)
{
  CStrs text;

  StrsInitS(&text, string);
  return YamlParse(&text);
}

CYamlNode *YamlGet(CYamlNode *map, U8 *key)
{
  CYamlNode *child;

  if (!map || map->type != YAML_MAP)
    return NULL;
  for (child = map->child; child; child = child->next) {
    if (StrsEqualsS(&child->key, key))
      return child;
  }
  return NULL;
}

CYamlNode *YamlAt(CYamlNode *node, I64 index)
{
  CYamlNode *child;

  if (!node || index < 0)
    return NULL;
  child = node->child;
  while (child && index--)
    child = child->next;
  return child;
}

I64 YamlCount(CYamlNode *node)
{
  CYamlNode *child;
  I64 count = 0;

  if (node) {
    for (child = node->child; child; child = child->next)
      count++;
  }
  return count;
}

// Heap copy of a scalar value; caller frees. NULL for missing/non-scalars.
U8 *YamlStr(CYamlNode *node)
{
  if (!node || node->type != YAML_SCALAR)
    return NULL;
  return StrsDup(&node->value);
}

I64 YamlI64(CYamlNode *node, I64 def=0)
{
  I64 value = 0;
  I64 sign = 1;
  U8 *p;

  if (!node || node->type != YAML_SCALAR || StrsEmpty(&node->value))
    return def;
  p = node->value.a;
  if (*p == '-' || *p == '+') {
    if (*p == '-')
      sign = -1;
    p++;
  }
  if (p == node->value.b)
    return def;
  while (p < node->value.b) {
    if (*p < '0' || *p > '9')
      return def;
    value = value * 10 + *p++ - '0';
  }
  return sign * value;
}

Bool YamlBool(CYamlNode *node, Bool def=FALSE)
{
  if (!node)
    return def;
  if (StrsEqualsS(&node->value, "true") ||
    StrsEqualsS(&node->value, "yes") || StrsEqualsS(&node->value, "on"))
    return TRUE;
  if (StrsEqualsS(&node->value, "false") ||
    StrsEqualsS(&node->value, "no") || StrsEqualsS(&node->value, "off"))
    return FALSE;
  return def;
}

Bool YamlIsNull(CYamlNode *node)
{
  return !node || node->type == YAML_SCALAR &&
    (StrsEmpty(&node->value) || StrsEqualsS(&node->value, "null") ||
      StrsEqualsS(&node->value, "~"));
}

U8 *YamlErrName(I64 err)
{
  switch (err) {
    case YAML_OK:
      return "ok";
    case YAML_ERR_ARGS:
      return "invalid arguments";
    case YAML_ERR_NESTING:
      return "maximum nesting depth exceeded";
    case YAML_ERR_FLOW:
      return "malformed flow collection";
    case YAML_ERR_TRAILING:
      return "trailing content";
  }
  return "unknown error";
}

#endif
