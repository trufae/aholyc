#ifndef AHOLYC_LIB_MCP_CLIENT_HC
#define AHOLYC_LIB_MCP_CLIENT_HC

// Model Context Protocol client over stdio (lib/io/process.hc) or Streamable
// HTTP (lib/http/client.hc + lib/http/sse.hc). A CMcp owns the session; the
// caller only frees the JSON strings the calls return.
//
//   CMcp mcp;
//   U8 *tools;
//   U8 *text;
//   if (McpOpen(&mcp, "npx -y @modelcontextprotocol/server-everything")) {
//     tools = McpList(&mcp, "tools");        // JSON array
//     if (McpTool(&mcp, "echo", "{\"message\":\"hi\"}")) {
//       text = McpText(&mcp);                // "Echo: hi"
//       Free(text);
//     }
//     Free(tools);
//   } else
//     "error: %s\n", mcp.error;
//   McpClose(&mcp);
//
// Remote servers take an URL and an optional bearer token:
//   McpOpen(&mcp, "https://mcp.example.com/mcp", getenv("MCP_TOKEN"));
//
// Public functions are the ones documented in README.md; helpers named
// McpSetError, McpReset, McpAccept, McpDecode, McpReadLine,
// McpSessionIsSafe, McpTransport* and McpRequest are internal.

#include "jsonrpc.hc"
#include "../io/process.hc"
#include "../http/client.hc"
#include "../http/sse.hc"

#define MCP_MAX_PAGES 1000

class CMcp
{
  U8 *url;                 // Streamable HTTP endpoint, NULL for stdio
  U8 *headers;             // Authorization and extra request headers
  U8 *session;             // Mcp-Session-Id assigned by the HTTP server
  U8 *version;             // negotiated protocol version
  CProcess process;        // stdio server
  CStrBuf inbox;           // unread stdio bytes
  I64 next_id;
  U8 *message;             // last JSON-RPC response text
  CJsonValue json;         // decoded last response
  CJsonValue result;       // its "result" member (or invalid)
  CHttpResponse *response; // last HTTP exchange, valid until the next call
  U8 *server_text;         // initialize result text
  CJsonValue server;       // decoded: $.serverInfo, $.capabilities, $.instructions
  U8 *error;               // NULL after a successful call
};

U0 McpSetError(CMcp *mcp, U8 *message)
{
  Free(mcp->error);
  mcp->error = StrNew(message);
}

U0 McpReset(CMcp *mcp)
{
  HttpResponseFree(mcp->response);
  mcp->response = NULL;
  Free(mcp->message);
  mcp->message = NULL;
  MemSet(&mcp->json, 0, sizeof(CJsonValue));
  MemSet(&mcp->result, 0, sizeof(CJsonValue));
  Free(mcp->error);
  mcp->error = NULL;
}

// Look at one incoming JSON-RPC message. Returns 1 when it is the response
// to id (kept in mcp->message/json/result), 2 when the server sent a request
// that deserves a reply (*reply is set, caller sends and frees), 0 otherwise.
I64 McpAccept(CMcp *mcp, U8 *text, I64 length, I64 id, U8 **reply)
{
  CJsonDecoder decoder;
  CJsonValue message;
  CJsonValue value;
  CJsonValue error;
  I64 number;
  U8 *raw;

  JsonDecoderInit(&decoder, text, length);
  if (!JsonDecode(&decoder, &message) || message.type != JSON_TYPE_OBJECT)
    return 0;
  if (JsonObjectGet(&message, "method", &value)) {
    if (!JsonObjectGet(&message, "id", &value))
      return 0;  // notification
    raw = McpJsonText(&value);
    *reply = McpJsonRpcError(raw, MCP_ERROR_METHOD_NOT_FOUND,
      "Method not found");
    Free(raw);
    return 2;
  }
  if (!JsonObjectGet(&message, "id", &value) ||
    !JsonValueAsI64(&value, &number) || number != id)
    return 0;
  Free(mcp->message);
  mcp->message = McpJsonText(&message);
  JsonDecoderInit(&decoder, mcp->message);
  JsonDecode(&decoder, &mcp->json);
  if (JsonObjectGet(&mcp->json, "error", &error)) {
    if (JsonObjectGet(&error, "message", &value) &&
      value.type == JSON_TYPE_STRING) {
        Free(mcp->error);
        mcp->error = JsonValueStringNew(&value);
      } else {
        McpSetError(mcp, "request failed");
      }
  } else if (!JsonObjectGet(&mcp->json, "result", &mcp->result)) {
    McpSetError(mcp, "response has no result");
  }
  return 1;
}

// Find the response to id in an HTTP body: a single JSON message or an SSE
// stream carrying several. Returns TRUE when it was found; mcp->error tells
// whether it is a success or a JSON-RPC error.
Bool McpDecode(CMcp *mcp, U8 *body, I64 length, I64 id, Bool sse)
{
  CSse stream;
  U8 *reply = NULL;
  Bool found = FALSE;

  if (!sse) {
    found = McpAccept(mcp, body, length, id, &reply) == 1;
    Free(reply);  // server requests cannot be answered on this stream
  } else {
    SseInit(&stream, body, length);
    while (!found && SseNext(&stream)) {
      reply = NULL;
      found = McpAccept(mcp, stream.data, -1, id, &reply) == 1;
      Free(reply);
    }
    SseFini(&stream);
  }
  if (!found && !mcp->error)
    McpSetError(mcp, "no response from server");
  return found;
}

// Take the next line from the stdio server. Caller frees; NULL at EOF.
U8 *McpReadLine(CMcp *mcp)
{
  U8 buffer[8192];
  U8 *line;
  I64 received;

  while (TRUE) {
    line = McpInboxLine(&mcp->inbox);
    if (line)
      return line;
    if (StrsLen(&mcp->inbox) > MCP_MAX_MESSAGE)
      return NULL;
    received = ProcessRead(&mcp->process, buffer, sizeof(buffer));
    if (received <= 0)
      return NULL;
    StrBufPutN(&mcp->inbox, buffer, received);
  }
}

Bool McpTransportStdio(CMcp *mcp, U8 *text, I64 id)
{
  U8 *line;
  U8 *reply;
  I64 state;

  if (!ProcessWrite(&mcp->process, text, StrLen(text)) ||
    !ProcessWrite(&mcp->process, "\n", 1)) {
      McpSetError(mcp, "server is not running");
      return FALSE;
    }
  if (id < 0)
    return TRUE;
  while (TRUE) {
    line = McpReadLine(mcp);
    if (!line) {
      McpSetError(mcp, "server closed the connection");
      return FALSE;
    }
    reply = NULL;
    state = McpAccept(mcp, line, -1, id, &reply);
    Free(line);
    if (state == 2) {
      ProcessWrite(&mcp->process, reply, StrLen(reply));
      ProcessWrite(&mcp->process, "\n", 1);
      Free(reply);
    } else if (state == 1) {
      return TRUE;
    }
  }
}

// The spec limits session ids to visible ASCII; anything else could smuggle
// header lines into later requests, so it is ignored.
Bool McpSessionIsSafe(U8 *session)
{
  U8 *cursor = session;

  if (!cursor || !*cursor)
    return FALSE;
  while (*cursor) {
    if (*cursor < 0x21 || *cursor > 0x7E)
      return FALSE;
    cursor++;
  }
  return TRUE;
}

Bool McpTransportHttp(CMcp *mcp, U8 *text, I64 id)
{
  CStrBuf headers;
  U8 *all;
  U8 *content_type;
  U8 *session;
  Bool sse;
  Bool found;

  StrBufInit(&headers);
  StrBufPutS(&headers, "Accept: application/json, text/event-stream\r\n");
  if (mcp->version)
    StrBufPrintf(&headers, "MCP-Protocol-Version: %s\r\n", mcp->version);
  if (mcp->session)
    StrBufPrintf(&headers, "Mcp-Session-Id: %s\r\n", mcp->session);
  StrBufPutS(&headers, mcp->headers);
  all = StrBufTake(&headers);
  mcp->response = HttpPost(mcp->url, text, StrLen(text), "application/json",
    all);
  Free(all);
  if (mcp->response->error) {
    McpSetError(mcp, mcp->response->error);
    return FALSE;
  }
  session = HttpHeaderValue(mcp->response, "Mcp-Session-Id");
  if (McpSessionIsSafe(session)) {
    Free(mcp->session);
    mcp->session = session;
  } else {
    Free(session);
  }
  if (id < 0 && mcp->response->status < 400)
    return TRUE;
  content_type = HttpHeaderValue(mcp->response, "Content-Type");
  sse = HttpStartsWithInsensitive(content_type, "text/event-stream");
  Free(content_type);
  found = McpDecode(mcp, mcp->response->body, mcp->response->body_length,
    id, sse);
  if (!found && mcp->response->status >= 400) {
    Free(mcp->error);
    if (mcp->response->status == 401)
      mcp->error = StrNew("HTTP 401: authorization required");
    else if (mcp->response->status == 404 && mcp->session)
      mcp->error = StrNew("HTTP 404: session expired");
    else
      mcp->error = MStrPrint("HTTP %d", mcp->response->status);
  }
  return found;
}

// Send one JSON-RPC message and, for requests, wait for its response.
Bool McpTransport(CMcp *mcp, U8 *text, I64 id)
{
  if (mcp->url)
    return McpTransportHttp(mcp, text, id);
  return McpTransportStdio(mcp, text, id);
}

// Perform a request; on success mcp->result holds the result value.
Bool McpRequest(CMcp *mcp, U8 *method, U8 *params=NULL)
{
  U8 *text;
  I64 id;
  Bool ok;

  McpReset(mcp);
  if (!method || !*method) {
    McpSetError(mcp, "missing method");
    return FALSE;
  }
  if (params && !JsonValid(params, JSON_TYPE_OBJECT)) {
    McpSetError(mcp, "params must be a JSON object");
    return FALSE;
  }
  if (!mcp->url && mcp->process.output == PROCESS_INVALID) {
    McpSetError(mcp, "not connected");
    return FALSE;
  }
  id = mcp->next_id++;
  text = McpJsonRpcRequest(id, method, params);
  ok = McpTransport(mcp, text, id);
  Free(text);
  return ok && !mcp->error;
}

// Send a JSON-RPC request. Returns the result as JSON text (caller frees)
// or NULL with mcp->error set; mcp->result keeps the decoded value.
U8 *McpCall(CMcp *mcp, U8 *method, U8 *params=NULL)
{
  if (!McpRequest(mcp, method, params))
    return NULL;
  return McpJsonText(&mcp->result);
}

// Send a JSON-RPC notification (no response is expected).
Bool McpNotify(CMcp *mcp, U8 *method, U8 *params=NULL)
{
  U8 *text;
  Bool ok;

  McpReset(mcp);
  if (!method || !*method || params && !JsonValid(params, JSON_TYPE_OBJECT)) {
    McpSetError(mcp, "invalid notification");
    return FALSE;
  }
  text = McpJsonRpcRequest(-1, method, params);
  ok = McpTransport(mcp, text, -1);
  Free(text);
  return ok;
}

// Terminate the session and release everything. Safe after a failed open.
U0 McpClose(CMcp *mcp)
{
  CStrBuf headers;
  U8 *all;
  CHttpResponse *response;

  if (mcp->url && mcp->session) {
    StrBufInit(&headers);
    StrBufPrintf(&headers, "Mcp-Session-Id: %s\r\n", mcp->session);
    if (mcp->version)
      StrBufPrintf(&headers, "MCP-Protocol-Version: %s\r\n", mcp->version);
    StrBufPutS(&headers, mcp->headers);
    all = StrBufTake(&headers);
    response = HttpRequest("DELETE", mcp->url, all);  // best effort
    HttpResponseFree(response);
    Free(all);
  }
  McpReset(mcp);
  if (!mcp->url)
    ProcessClose(&mcp->process);
  StrBufFini(&mcp->inbox);
  Free(mcp->url);
  Free(mcp->headers);
  Free(mcp->session);
  Free(mcp->version);
  Free(mcp->server_text);
  MemSet(mcp, 0, sizeof(CMcp));
  mcp->process.input = PROCESS_INVALID;
  mcp->process.output = PROCESS_INVALID;
}

// Connect and run the initialize handshake. target is an http(s):// URL of
// a Streamable HTTP server or a command line started with piped stdio.
// token becomes an "Authorization: Bearer" header; headers holds extra
// "Name: value\r\n" lines. On failure mcp->error is set and McpClose still
// has to be called.
Bool McpOpen(CMcp *mcp, U8 *target, U8 *token=NULL, U8 *headers=NULL)
{
  CStrBuf all;
  CJsonDecoder decoder;
  CJsonValue value;
  CPj *pj;
  U8 *params;
  Bool ok;

  MemSet(mcp, 0, sizeof(CMcp));
  mcp->process.input = PROCESS_INVALID;
  mcp->process.output = PROCESS_INVALID;
  StrBufInit(&mcp->inbox);
  mcp->next_id = 1;
  if (!target || !*target) {
    McpSetError(mcp, "missing server");
    return FALSE;
  }
  StrBufInit(&all);
  if (token && *token)
    StrBufPrintf(&all, "Authorization: Bearer %s\r\n", token);
  if (headers)
    StrBufPutS(&all, headers);
  if (StrsLen(&all))
    mcp->headers = StrBufTake(&all);
  StrBufFini(&all);
  if (HttpStartsWithInsensitive(target, "http://") ||
    HttpStartsWithInsensitive(target, "https://")) {
      mcp->url = StrNew(target);
    } else if (!ProcessOpen(&mcp->process, target)) {
      McpSetError(mcp, "cannot start server");
      return FALSE;
    }

  pj = PjNew;
  PjO(pj);
  PjKs(pj, "protocolVersion", MCP_PROTOCOL_VERSION);
  PjKo(pj, "capabilities");
  PjEnd(pj);
  PjKo(pj, "clientInfo");
  PjKs(pj, "name", "aholyc");
  PjKs(pj, "version", "1");
  PjEnd(pj);
  PjEnd(pj);
  params = PjDrain(pj);
  ok = McpRequest(mcp, "initialize", params);
  Free(params);
  if (!ok)
    return FALSE;
  mcp->server_text = McpJsonText(&mcp->result);
  JsonDecoderInit(&decoder, mcp->server_text);
  JsonDecode(&decoder, &mcp->server);
  if (JsonObjectGet(&mcp->server, "protocolVersion", &value) &&
    value.type == JSON_TYPE_STRING)
    mcp->version = JsonValueStringNew(&value);
  else
    mcp->version = StrNew(MCP_PROTOCOL_VERSION);
  return McpNotify(mcp, "notifications/initialized");
}

// List "tools", "prompts", "resources" or "resources/templates", following
// pagination. Returns a JSON array (caller frees) or NULL with mcp->error.
U8 *McpList(CMcp *mcp, U8 *kind)
{
  CPj *out = PjNew;
  CPj *pj;
  CJsonValue items;
  CJsonValue item;
  U8 *key = kind;
  U8 *method;
  U8 *params = NULL;
  U8 *cursor = NULL;
  U8 *text;
  I64 page;
  I64 i;
  Bool more = TRUE;

  if (!kind || !*kind) {
    McpReset(mcp);
    McpSetError(mcp, "missing kind");
    PjFree(out);
    return NULL;
  }
  if (!StrCmp(kind, "resources/templates"))
    key = "resourceTemplates";
  method = MStrPrint("%s/list", kind);
  PjA(out);
  for (page = 0; more && page < MCP_MAX_PAGES; page++) {
    if (cursor) {
      pj = PjNew;
      PjO(pj);
      PjKs(pj, "cursor", cursor);
      PjEnd(pj);
      params = PjDrain(pj);
    }
    more = McpRequest(mcp, method, params);
    Free(params);
    params = NULL;
    Free(cursor);
    cursor = NULL;
    if (!more) {
      PjFree(out);
      out = NULL;
    } else {
      if (JsonObjectGet(&mcp->result, key, &items)) {
        for (i = 0; JsonArrayGet(&items, i, &item); i++) {
          text = McpJsonText(&item);
          PjJ(out, text);
          Free(text);
        }
      }
      if (JsonObjectGet(&mcp->result, "nextCursor", &item) &&
        item.type == JSON_TYPE_STRING)
        cursor = JsonValueStringNew(&item);
      more = cursor != NULL;
    }
  }
  Free(method);
  Free(cursor);
  if (!out)
    return NULL;
  PjEnd(out);
  return PjDrain(out);
}

// Concatenate the text parts of the last result: tool content, prompt
// messages or resource contents. Caller frees; NULL when there is no text.
U8 *McpText(CMcp *mcp)
{
  CStrBuf sb;
  CJsonValue items;
  CJsonValue item;
  CJsonValue text;
  U8 *keys[3];
  U8 *part;
  I64 k;
  I64 i;
  Bool any = FALSE;

  keys[0] = "content";
  keys[1] = "contents";
  keys[2] = "messages";
  StrBufInit(&sb);
  for (k = 0; k < 3; k++) {
    if (JsonObjectGet(&mcp->result, keys[k], &items)) {
      for (i = 0; JsonArrayGet(&items, i, &item); i++) {
        if (JsonObjectGet(&item, "content", &text) &&
          text.type == JSON_TYPE_OBJECT)
          item = text;
        if (JsonObjectGet(&item, "text", &text) &&
          text.type == JSON_TYPE_STRING) {
            if (any)
              StrBufPutC(&sb, '\n');
            part = JsonValueStringNew(&text);
            StrBufPutS(&sb, part);
            Free(part);
            any = TRUE;
          }
      }
    }
  }
  if (!any) {
    StrBufFini(&sb);
    return NULL;
  }
  return StrBufTake(&sb);
}

// tools/call. arguments is a JSON object (NULL for none). Returns the result
// JSON (caller frees); a tool that reports isError yields NULL and its
// message in mcp->error. McpText extracts the text content afterwards.
U8 *McpTool(CMcp *mcp, U8 *name, U8 *arguments=NULL)
{
  CPj *pj;
  CJsonValue value;
  U8 *params;
  U8 *text;
  Bool is_error = FALSE;
  Bool ok;

  if (!arguments)
    arguments = "{}";
  if (!name || !*name || !JsonValid(arguments, JSON_TYPE_OBJECT)) {
    McpReset(mcp);
    McpSetError(mcp, "tool name and JSON object arguments are required");
    return NULL;
  }
  pj = PjNew;
  PjO(pj);
  PjKs(pj, "name", name);
  PjKj(pj, "arguments", arguments);
  PjEnd(pj);
  params = PjDrain(pj);
  ok = McpRequest(mcp, "tools/call", params);
  Free(params);
  if (!ok)
    return NULL;
  if (JsonObjectGet(&mcp->result, "isError", &value))
    JsonValueAsBool(&value, &is_error);
  if (is_error) {
    text = McpText(mcp);
    if (text)
      mcp->error = text;
    else
      McpSetError(mcp, "tool failed");
    return NULL;
  }
  return McpJsonText(&mcp->result);
}

// prompts/get. arguments is a JSON object of string values (NULL for none).
// Returns the result JSON with $.messages (caller frees) or NULL.
U8 *McpPrompt(CMcp *mcp, U8 *name, U8 *arguments=NULL)
{
  CPj *pj;
  U8 *params;
  U8 *result;

  if (!name || !*name || arguments && !JsonValid(arguments, JSON_TYPE_OBJECT)) {
    McpReset(mcp);
    McpSetError(mcp, "prompt name and JSON object arguments are required");
    return NULL;
  }
  pj = PjNew;
  PjO(pj);
  PjKs(pj, "name", name);
  if (arguments)
    PjKj(pj, "arguments", arguments);
  PjEnd(pj);
  params = PjDrain(pj);
  result = McpCall(mcp, "prompts/get", params);
  Free(params);
  return result;
}

// resources/read. Returns the result JSON with $.contents (caller frees) or
// NULL; McpText joins the textual contents.
U8 *McpResource(CMcp *mcp, U8 *uri)
{
  CPj *pj;
  U8 *params;
  U8 *result;

  if (!uri || !*uri) {
    McpReset(mcp);
    McpSetError(mcp, "resource uri is required");
    return NULL;
  }
  pj = PjNew;
  PjO(pj);
  PjKs(pj, "uri", uri);
  PjEnd(pj);
  params = PjDrain(pj);
  result = McpCall(mcp, "resources/read", params);
  Free(params);
  return result;
}

#endif
