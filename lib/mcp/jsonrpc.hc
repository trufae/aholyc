#ifndef AHOLYC_LIB_MCP_JSONRPC_HC
#define AHOLYC_LIB_MCP_JSONRPC_HC

// JSON-RPC 2.0 plumbing shared by the MCP client and server: message
// builders on lib/json/pj.hc, zero-copy access to decoded messages, and the
// newline framing used by the stdio transport. Nothing here talks to a
// transport; client.hc and server.hc do.

#include "../json/query.hc"
#include "../json/pj.hc"
#include "../text/strbuf.hc"

#define MCP_PROTOCOL_VERSION "2025-06-18"

#define MCP_ERROR_PARSE            -32700
#define MCP_ERROR_INVALID_REQUEST  -32600
#define MCP_ERROR_METHOD_NOT_FOUND -32601
#define MCP_ERROR_INVALID_PARAMS   -32602
#define MCP_ERROR_INTERNAL         -32603

#ifndef MCP_MAX_MESSAGE
#define MCP_MAX_MESSAGE 268435456
#endif

// Copy a decoded JSON value into a NUL-terminated string. Caller frees.
U8 *McpJsonText(CJsonValue *value)
{
  U8 *text;

  if (!value || !value->data || value->length < 0)
    return NULL;
  text = MAlloc(value->length + 1);
  MemCpy(text, value->data, value->length);
  text[value->length] = 0;
  return text;
}

// {"jsonrpc":"2.0","id":id,"method":method,"params":params}; id < 0 makes
// a notification, params may be NULL. Caller frees.
U8 *McpJsonRpcRequest(I64 id, U8 *method, U8 *params=NULL)
{
  CPj *pj = PjNew;

  PjO(pj);
  PjKs(pj, "jsonrpc", "2.0");
  if (id >= 0)
    PjKn(pj, "id", id);
  PjKs(pj, "method", method);
  if (params)
    PjKj(pj, "params", params);
  PjEnd(pj);
  return PjDrain(pj);
}

// Success response; id is raw JSON text (a number or a string literal) so
// whatever the peer sent is echoed back. Caller frees.
U8 *McpJsonRpcResult(U8 *id, U8 *result)
{
  CPj *pj = PjNew;

  PjO(pj);
  PjKs(pj, "jsonrpc", "2.0");
  PjKj(pj, "id", id);
  PjKj(pj, "result", result);
  PjEnd(pj);
  return PjDrain(pj);
}

// Error response; id may be NULL when the request could not be parsed.
U8 *McpJsonRpcError(U8 *id, I64 code, U8 *message)
{
  CPj *pj = PjNew;

  PjO(pj);
  PjKs(pj, "jsonrpc", "2.0");
  if (id)
    PjKj(pj, "id", id);
  else
    PjKnull(pj, "id");
  PjKo(pj, "error");
  PjKn(pj, "code", code);
  PjKs(pj, "message", message);
  PjEnd(pj);
  PjEnd(pj);
  return PjDrain(pj);
}

// Take the first complete line out of an inbox fed with StrBufPutN. Returns
// NULL when no newline is buffered yet; the caller reads more and retries.
U8 *McpInboxLine(CStrBuf *inbox)
{
  U8 *line;
  U8 *rest;
  I64 length = StrsLen(inbox);
  I64 i;

  for (i = 0; i < length; i++) {
    if (inbox->a[i] == '\n') {
      line = MAlloc(i + 1);
      MemCpy(line, inbox->a, i);
      line[i] = 0;
      rest = MAlloc(length - i);
      MemCpy(rest, inbox->a + i + 1, length - i - 1);
      StrBufClear(inbox);
      StrBufPutN(inbox, rest, length - i - 1);
      Free(rest);
      return line;
    }
  }
  return NULL;
}

#endif
