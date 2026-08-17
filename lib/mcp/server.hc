#ifndef AHOLYC_LIB_MCP_SERVER_HC
#define AHOLYC_LIB_MCP_SERVER_HC

// Model Context Protocol server: register tools, prompts and resources with
// handler functions, then serve them over stdio or Streamable HTTP. The
// registry keeps only the pointers it is given (string literals or memory
// the caller owns for the server's lifetime), the protocol core turns one
// request line into one response string, and transports are thin loops on
// top of it, so the whole thing runs in a few kilobytes.
//
//   U8 *Echo(CMcpServer *server, CMcpEntry *entry, CJsonValue *params)
//   {
//     CJsonValue message;
//     U8 *text;
//     U8 *result;
//
//     if (!JsonPathGet(params, "$.arguments.message", &message))
//       return McpResultText("message is required", TRUE);
//     text = JsonValueStringNew(&message);
//     result = McpResultText(text);
//     Free(text);
//     return result;
//   }
//
//   CMcpServer server;
//   McpServerInit(&server, "echo-server", "1.0");
//   McpServerTool(&server, "echo", "Echo a message",
//     "{\"type\":\"object\",\"properties\":{\"message\":{\"type\":\"string\"}}}",
//     &Echo);
//   McpServerRun(&server);              // stdio, returns at EOF
//   McpServerFini(&server);
//
// Handlers return the JSON result text for the request (the server frees
// it) or NULL to fail; McpServerFail sets the message. Tools should report
// their own failures with McpResultText(message, TRUE) so the model sees
// them. Public functions are the ones documented in README.md; the
// McpServerHandle* helpers below it are internal except McpServerHandle.

#include "jsonrpc.hc"
#include "../http/server.hc"

#define MCP_ENTRY_TOOL     1
#define MCP_ENTRY_PROMPT   2
#define MCP_ENTRY_RESOURCE 3

class CMcpServer;

class CMcpEntry
{
  I64 kind;
  U8 *name;         // tool or prompt name, resource uri
  U8 *description;  // tool/prompt description or resource name, NULL allowed
  U8 *json;         // tool inputSchema, prompt arguments array, or NULL
  U8 *mime;         // resource mimeType or NULL
  U8 *(*handler)(CMcpServer *server, CMcpEntry *entry, CJsonValue *params);
  CMcpEntry *next;
};

class CMcpServer
{
  U8 *name;
  U8 *version;
  U8 *instructions;    // NULL allowed
  I64 page_size;       // 0 lists everything at once
  CMcpEntry *first;
  CMcpEntry *last;
  U8 *error;           // set by McpServerFail during a handler
  Bool initialized;
  Bool stdio;          // McpServerRun is active: McpServerNotify writes stdout
  Bool stop;           // set by McpServerStop to leave the serving loop
};

#ifdef IS_WINDOWS
extern I64 _read(I64 fd, U8 *buffer, U32 count);
extern I64 _write(I64 fd, U8 *buffer, U32 count);
#else
extern I64 read(I64 fd, U8 *buffer, I64 count);
extern I64 write(I64 fd, U8 *buffer, I64 count);
#endif

I64 McpServerStdinRead(U8 *buffer, I64 capacity)
{
  #ifdef IS_WINDOWS
  return _read(0, buffer, capacity)(I32);
  #else
  return read(0, buffer, capacity);
  #endif
}

Bool McpServerStdoutWrite(U8 *data, I64 size)
{
  I64 written;

  while (size > 0) {
    #ifdef IS_WINDOWS
    written = _write(1, data, size)(I32);
    #else
    written = write(1, data, size);
    #endif
    if (written <= 0)
      return FALSE;
    data += written;
    size -= written;
  }
  return TRUE;
}

U0 McpServerInit(CMcpServer *server, U8 *name, U8 *version="1",
  U8 *instructions=NULL)
{
  MemSet(server, 0, sizeof(CMcpServer));
  server->name = name;
  server->version = version;
  server->instructions = instructions;
}

U0 McpServerFini(CMcpServer *server)
{
  CMcpEntry *entry = server->first;
  CMcpEntry *next;

  while (entry) {
    next = entry->next;
    Free(entry);
    entry = next;
  }
  Free(server->error);
  MemSet(server, 0, sizeof(CMcpServer));
}

CMcpEntry *McpServerAdd(CMcpServer *server, I64 kind, U8 *name,
  U8 *description, U8 *json, U8 *mime, U8 *handler)
{
  CMcpEntry *entry;

  if (!name || !*name || !handler || json && !JsonValid(json))
    return NULL;
  entry = CAlloc(sizeof(CMcpEntry));
  entry->kind = kind;
  entry->name = name;
  entry->description = description;
  entry->json = json;
  entry->mime = mime;
  entry->handler = handler;
  if (server->last)
    server->last->next = entry;
  else
    server->first = entry;
  server->last = entry;
  return entry;
}

// Register a tool; input_schema is a JSON Schema object (NULL for
// {"type":"object"}). The handler receives the request params
// ($.name, $.arguments) and returns a tools/call result.
Bool McpServerTool(CMcpServer *server, U8 *name, U8 *description,
  U8 *input_schema, U8 *handler)
{
  return McpServerAdd(server, MCP_ENTRY_TOOL, name, description,
    input_schema, NULL, handler) != NULL;
}

// Register a prompt; arguments is a JSON array of {name, description,
// required} objects or NULL. The handler returns a prompts/get result.
Bool McpServerPrompt(CMcpServer *server, U8 *name, U8 *description,
  U8 *arguments, U8 *handler)
{
  return McpServerAdd(server, MCP_ENTRY_PROMPT, name, description,
    arguments, NULL, handler) != NULL;
}

// Register a resource by uri with a human-readable name (NULL repeats the
// uri). The handler returns a resources/read result.
Bool McpServerResource(CMcpServer *server, U8 *uri, U8 *name,
  U8 *mime_type, U8 *handler)
{
  return McpServerAdd(server, MCP_ENTRY_RESOURCE, uri, name, NULL,
    mime_type, handler) != NULL;
}

// Handlers call this and return NULL to answer with a JSON-RPC error.
U0 McpServerFail(CMcpServer *server, U8 *message)
{
  Free(server->error);
  server->error = StrNew(message);
}

// Ask the serving loop to return after the current message.
U0 McpServerStop(CMcpServer *server)
{
  server->stop = TRUE;
}

// tools/call result with one text content part. Caller frees.
U8 *McpResultText(U8 *text, Bool is_error=FALSE)
{
  CPj *pj = PjNew;

  PjO(pj);
  PjKa(pj, "content");
  PjO(pj);
  PjKs(pj, "type", "text");
  PjKs(pj, "text", text);
  PjEnd(pj);
  PjEnd(pj);
  if (is_error)
    PjKb(pj, "isError", TRUE);
  PjEnd(pj);
  return PjDrain(pj);
}

// prompts/get result with one text message. Caller frees.
U8 *McpResultMessage(U8 *role, U8 *text, U8 *description=NULL)
{
  CPj *pj = PjNew;

  PjO(pj);
  if (description)
    PjKs(pj, "description", description);
  PjKa(pj, "messages");
  PjO(pj);
  PjKs(pj, "role", role);
  PjKo(pj, "content");
  PjKs(pj, "type", "text");
  PjKs(pj, "text", text);
  PjEnd(pj);
  PjEnd(pj);
  PjEnd(pj);
  PjEnd(pj);
  return PjDrain(pj);
}

// resources/read result with one text content. Caller frees.
U8 *McpResultContents(U8 *uri, U8 *mime_type, U8 *text)
{
  CPj *pj = PjNew;

  PjO(pj);
  PjKa(pj, "contents");
  PjO(pj);
  PjKs(pj, "uri", uri);
  if (mime_type)
    PjKs(pj, "mimeType", mime_type);
  PjKs(pj, "text", text);
  PjEnd(pj);
  PjEnd(pj);
  PjEnd(pj);
  return PjDrain(pj);
}

U8 *McpEntryKindName(I64 kind)
{
  if (kind == MCP_ENTRY_TOOL)
    return "tool";
  if (kind == MCP_ENTRY_PROMPT)
    return "prompt";
  return "resource";
}

CMcpEntry *McpServerFind(CMcpServer *server, I64 kind, U8 *name)
{
  CMcpEntry *entry = server->first;

  while (entry) {
    if (entry->kind == kind && !StrCmp(entry->name, name))
      return entry;
    entry = entry->next;
  }
  return NULL;
}

Bool McpServerHas(CMcpServer *server, I64 kind)
{
  CMcpEntry *entry = server->first;

  while (entry) {
    if (entry->kind == kind)
      return TRUE;
    entry = entry->next;
  }
  return FALSE;
}

U0 McpServerCapability(CPj *pj, CMcpServer *server, I64 kind, U8 *key)
{
  if (McpServerHas(server, kind)) {
    PjKo(pj, key);
    PjKb(pj, "listChanged", FALSE);
    PjEnd(pj);
  }
}

// initialize: echo a supported protocol version, advertise what exists.
U8 *McpServerHandleInitialize(CMcpServer *server, CJsonValue *params)
{
  CPj *pj = PjNew;
  CJsonValue value;
  U8 *version = NULL;

  if (params && JsonObjectGet(params, "protocolVersion", &value) &&
    value.type == JSON_TYPE_STRING)
    version = JsonValueStringNew(&value);
  PjO(pj);
  if (version)
    PjKs(pj, "protocolVersion", version);
  else
    PjKs(pj, "protocolVersion", MCP_PROTOCOL_VERSION);
  PjKo(pj, "capabilities");
  McpServerCapability(pj, server, MCP_ENTRY_TOOL, "tools");
  McpServerCapability(pj, server, MCP_ENTRY_PROMPT, "prompts");
  McpServerCapability(pj, server, MCP_ENTRY_RESOURCE, "resources");
  PjEnd(pj);
  PjKo(pj, "serverInfo");
  PjKs(pj, "name", server->name);
  PjKs(pj, "version", server->version);
  PjEnd(pj);
  if (server->instructions)
    PjKs(pj, "instructions", server->instructions);
  PjEnd(pj);
  Free(version);
  server->initialized = TRUE;
  return PjDrain(pj);
}

U0 McpServerListEntry(CPj *pj, CMcpEntry *entry)
{
  PjO(pj);
  if (entry->kind == MCP_ENTRY_RESOURCE) {
    PjKs(pj, "uri", entry->name);
    if (entry->description)
      PjKs(pj, "name", entry->description);
    else
      PjKs(pj, "name", entry->name);
    if (entry->mime)
      PjKs(pj, "mimeType", entry->mime);
  } else {
    PjKs(pj, "name", entry->name);
    if (entry->description)
      PjKs(pj, "description", entry->description);
  }
  if (entry->kind == MCP_ENTRY_TOOL) {
    if (entry->json)
      PjKj(pj, "inputSchema", entry->json);
    else
      PjKj(pj, "inputSchema", "{\"type\":\"object\"}");
  } else if (entry->kind == MCP_ENTRY_PROMPT && entry->json) {
    PjKj(pj, "arguments", entry->json);
  }
  PjEnd(pj);
}

// */list with an optional numeric cursor and server->page_size paging.
U8 *McpServerHandleList(CMcpServer *server, I64 kind, U8 *key,
  CJsonValue *params)
{
  CPj *pj = PjNew;
  CJsonValue value;
  CMcpEntry *entry = server->first;
  U8 *cursor;
  I64 start = 0;
  I64 index = 0;
  I64 count = 0;

  if (params && JsonObjectGet(params, "cursor", &value) &&
    value.type == JSON_TYPE_STRING) {
      cursor = JsonValueStringNew(&value);
      if (!HttpParseDecimal(cursor, &start))
        start = 0;
      Free(cursor);
    }
  PjO(pj);
  PjKa(pj, key);
  while (entry) {
    if (entry->kind == kind) {
      if (index >= start &&
        (!server->page_size || count < server->page_size)) {
          McpServerListEntry(pj, entry);
          count++;
        }
      index++;
    }
    entry = entry->next;
  }
  PjEnd(pj);
  if (server->page_size && start + count < index) {
    cursor = MStrPrint("%d", start + count);
    PjKs(pj, "nextCursor", cursor);
    Free(cursor);
  }
  PjEnd(pj);
  return PjDrain(pj);
}

// Run a registered handler for tools/call, prompts/get or resources/read.
// Returns the result or NULL with *code and server->error set.
U8 *McpServerHandleCall(CMcpServer *server, I64 kind, U8 *key,
  CJsonValue *params, I64 *code)
{
  CJsonValue value;
  CMcpEntry *entry = NULL;
  U8 *name;
  U8 *result;

  if (params && JsonObjectGet(params, key, &value) &&
    value.type == JSON_TYPE_STRING) {
      name = JsonValueStringNew(&value);
      entry = McpServerFind(server, kind, name);
      if (!entry) {
        Free(server->error);
        server->error = MStrPrint("Unknown %s: %s", McpEntryKindName(kind),
          name);
      }
      Free(name);
    } else {
      Free(server->error);
      server->error = MStrPrint("Missing %s", key);
    }
  if (!entry) {
    *code = MCP_ERROR_INVALID_PARAMS;
    return NULL;
  }
  Free(server->error);
  server->error = NULL;
  result = entry->handler(server, entry, params);
  if (result)
    return result;
  if (!server->error)
    McpServerFail(server, "handler failed");
  if (kind == MCP_ENTRY_TOOL)
    return McpResultText(server->error, TRUE);
  *code = MCP_ERROR_INTERNAL;
  return NULL;
}

// Handle one JSON-RPC message. Returns the response text (caller frees) or
// NULL when nothing must be sent back (notifications, client responses).
U8 *McpServerHandle(CMcpServer *server, U8 *message, I64 length=-1)
{
  CJsonDecoder decoder;
  CJsonValue root;
  CJsonValue value;
  CJsonValue params;
  U8 *id = NULL;
  U8 *method = NULL;
  U8 *result = NULL;
  U8 *response;
  I64 code = MCP_ERROR_METHOD_NOT_FOUND;
  Bool have_params;

  JsonDecoderInit(&decoder, message, length);
  if (!JsonDecode(&decoder, &root))
    return McpJsonRpcError(NULL, MCP_ERROR_PARSE, "Parse error");
  if (root.type != JSON_TYPE_OBJECT ||
    !JsonObjectGet(&root, "method", &value) ||
    value.type != JSON_TYPE_STRING) {
      if (JsonObjectGet(&root, "id", &value) &&
        !JsonObjectGet(&root, "result", &params) &&
        !JsonObjectGet(&root, "error", &params)) {
          id = McpJsonText(&value);
          response = McpJsonRpcError(id, MCP_ERROR_INVALID_REQUEST,
            "Invalid Request");
          Free(id);
          return response;
        }
      return NULL;  // a response to one of our own requests: ignored
    }
  method = JsonValueStringNew(&value);
  if (JsonObjectGet(&root, "id", &value))
    id = McpJsonText(&value);
  have_params = JsonObjectGet(&root, "params", &params) &&
    params.type == JSON_TYPE_OBJECT;
  if (!have_params)
    MemSet(&params, 0, sizeof(CJsonValue));

  if (!id) {
    // Notifications carry no reply; initialized/cancelled need no action.
  } else if (!StrCmp(method, "initialize")) {
    result = McpServerHandleInitialize(server, &params);
  } else if (!StrCmp(method, "ping")) {
    result = StrNew("{}");
  } else if (!StrCmp(method, "tools/list")) {
    result = McpServerHandleList(server, MCP_ENTRY_TOOL, "tools", &params);
  } else if (!StrCmp(method, "prompts/list")) {
    result = McpServerHandleList(server, MCP_ENTRY_PROMPT, "prompts",
      &params);
  } else if (!StrCmp(method, "resources/list")) {
    result = McpServerHandleList(server, MCP_ENTRY_RESOURCE, "resources",
      &params);
  } else if (!StrCmp(method, "resources/templates/list")) {
    result = StrNew("{\"resourceTemplates\":[]}");
  } else if (!StrCmp(method, "tools/call")) {
    result = McpServerHandleCall(server, MCP_ENTRY_TOOL, "name", &params,
      &code);
  } else if (!StrCmp(method, "prompts/get")) {
    result = McpServerHandleCall(server, MCP_ENTRY_PROMPT, "name", &params,
      &code);
  } else if (!StrCmp(method, "resources/read")) {
    result = McpServerHandleCall(server, MCP_ENTRY_RESOURCE, "uri", &params,
      &code);
  } else {
    McpServerFail(server, "Method not found");
  }
  Free(method);
  if (!id)
    return NULL;
  if (result)
    response = McpJsonRpcResult(id, result);
  else
    response = McpJsonRpcError(id, code, server->error);
  Free(result);
  Free(id);
  return response;
}

// Send a notification to the client. Only the stdio transport can push;
// over HTTP (no SSE) this returns FALSE.
Bool McpServerNotify(CMcpServer *server, U8 *method, U8 *params=NULL)
{
  U8 *text;
  Bool ok;

  if (!server->stdio || params && !JsonValid(params, JSON_TYPE_OBJECT))
    return FALSE;
  text = McpJsonRpcRequest(-1, method, params);
  ok = McpServerStdoutWrite(text, StrLen(text)) &&
    McpServerStdoutWrite("\n", 1);
  Free(text);
  return ok;
}

// Serve newline-delimited JSON-RPC on stdin/stdout until EOF or
// McpServerStop. Returns FALSE when stdout could not be written.
Bool McpServerRun(CMcpServer *server)
{
  CStrBuf inbox;
  U8 buffer[8192];
  U8 *line;
  U8 *response;
  I64 received;
  Bool ok = TRUE;

  StrBufInit(&inbox);
  server->stdio = TRUE;
  server->stop = FALSE;
  while (ok && !server->stop) {
    line = McpInboxLine(&inbox);
    if (line) {
      if (*line) {
        response = McpServerHandle(server, line);
        if (response) {
          ok = McpServerStdoutWrite(response, StrLen(response)) &&
            McpServerStdoutWrite("\n", 1);
          Free(response);
        }
      }
      Free(line);
    } else {
      if (StrsLen(&inbox) > MCP_MAX_MESSAGE)
        break;
      received = McpServerStdinRead(buffer, sizeof(buffer));
      if (received <= 0)
        break;
      StrBufPutN(&inbox, buffer, received);
    }
  }
  server->stdio = FALSE;
  StrBufFini(&inbox);
  return ok;
}

// Serve Streamable HTTP (stateless, JSON responses) on host:port at path
// until McpServerStop or a listen failure. token, when given, is required
// as "Authorization: Bearer <token>".
Bool McpServerRunHttp(CMcpServer *server, I64 port, U8 *host="127.0.0.1",
  U8 *path="/mcp", U8 *token=NULL)
{
  CHttpServer http;
  CHttpRequest *request;
  U8 *authorization;
  U8 *response;
  Bool authorized;

  if (!HttpServerListen(&http, port, host))
    return FALSE;
  server->stop = FALSE;
  while (!server->stop && (request = HttpServerAccept(&http))) {
    if (request->error) {
      // already answered with 400
    } else if (StrCmp(request->target, path)) {
      HttpRespond(request, 404, "not found", 9);
    } else if (!StrCmp(request->method, "POST")) {
      authorized = TRUE;
      if (token && *token) {
        authorization = HttpRequestHeader(request, "Authorization");
        authorized = HttpStartsWithInsensitive(authorization, "Bearer ") &&
          !StrCmp(authorization + 7, token);
        Free(authorization);
      }
      if (!authorized) {
        HttpRespond(request, 401, "unauthorized", 12, "text/plain",
          "WWW-Authenticate: Bearer\r\n");
      } else {
        response = McpServerHandle(server, request->body,
          request->body_length);
        if (response)
          HttpRespond(request, 200, response, StrLen(response),
            "application/json");
        else
          HttpRespond(request, 202);
        Free(response);
      }
    } else if (!StrCmp(request->method, "DELETE")) {
      HttpRespond(request, 200);
    } else {
      HttpRespond(request, 405, "method not allowed", 18, "text/plain",
        "Allow: POST, DELETE\r\n");
    }
    HttpRequestFree(request);
  }
  HttpServerClose(&http);
  return TRUE;
}

#endif
