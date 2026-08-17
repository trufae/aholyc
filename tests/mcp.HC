// lib/mcp: the client against the fixture server in tests/mcp_server.HC
// (its command line is the first argument) over stdio and Streamable HTTP,
// plus transport-free checks of both protocol cores.

#include "../lib/mcp/client.hc"
#include "../lib/mcp/server.hc"

#define MCP_TEST_PORT 18765

extern I64 usleep(U32 microseconds);

I64 failures = 0;

U0 Check(Bool condition, U8 *name)
{
  if (!condition) {
    "FAIL %s\n", name;
    failures++;
  }
}

U0 Session(CMcp *mcp, U8 *transport)
{
  CJsonValue value;
  U8 *json;
  U8 *text;

  Check(!StrCmp(mcp->version, "2025-06-18"), "negotiated version");
  Check(JsonPathGet(&mcp->server, "$.serverInfo.name", &value) &&
    JsonValueStringEquals(&value, "fake"), "server info");
  Check(JsonPathGet(&mcp->server, "$.instructions", &value), "instructions");
  Check(JsonPathGet(&mcp->server, "$.capabilities.tools", &value) &&
    JsonPathGet(&mcp->server, "$.capabilities.prompts", &value) &&
    JsonPathGet(&mcp->server, "$.capabilities.resources", &value),
    "capabilities");

  json = McpList(mcp, "tools");
  "%s tools: %s\n", transport, json;
  Free(json);
  json = McpList(mcp, "prompts");
  "%s prompts: %s\n", transport, json;
  Free(json);
  json = McpList(mcp, "resources");
  "%s resources: %s\n", transport, json;
  Free(json);

  json = McpTool(mcp, "echo", "{\"message\":\"hi \\\"there\\\"\"}");
  Check(json != NULL, "echo tool");
  text = McpText(mcp);
  "%s echo: %s\n", transport, text;
  Free(text);
  Free(json);

  json = McpTool(mcp, "fail");
  Check(!json, "failing tool returns NULL");
  "%s fail: %s\n", transport, mcp->error;
  json = McpTool(mcp, "missing");
  Check(!json, "unknown tool returns NULL");
  "%s missing: %s\n", transport, mcp->error;
  Check(!McpTool(mcp, "echo", "[1]"), "arguments must be an object");

  json = McpPrompt(mcp, "greet", "{\"who\":\"pancake\"}");
  Check(json != NULL, "prompt");
  text = McpText(mcp);
  "%s prompt: %s\n", transport, text;
  Free(text);
  Free(json);
  json = McpPrompt(mcp, "greet");
  Check(!json && !StrCmp(mcp->error, "who is required"), "prompt error");

  json = McpResource(mcp, "file:///a.txt");
  Check(json != NULL, "resource");
  text = McpText(mcp);
  "%s resource: %s\n", transport, text;
  Free(text);
  Free(json);

  json = McpCall(mcp, "ping");
  Check(json && !StrCmp(json, "{}"), "ping");
  Free(json);
  json = McpCall(mcp, "nope");
  Check(!json && !StrCmp(mcp->error, "Method not found"), "unknown method");
  Check(McpNotify(mcp, "notifications/cancelled", "{\"requestId\":1}"),
    "notify");
}

U0 TestStdio(U8 *command)
{
  CMcp mcp;

  if (!McpOpen(&mcp, command)) {
    "FAIL open: %s\n", mcp.error;
    failures++;
  } else {
    Session(&mcp, "stdio");
  }
  McpClose(&mcp);
  Check(mcp.process.exit_code == 0, "server exited cleanly");
}

U0 TestHttp(U8 *command)
{
  CProcess process;
  CMcp mcp;
  U8 *server_command = MStrPrint("%s http %d", command, MCP_TEST_PORT);
  U8 *url = MStrPrint("http://127.0.0.1:%d/mcp", MCP_TEST_PORT);
  U8 *json;
  I64 attempts = 0;
  Bool open;

  Check(ProcessOpen(&process, server_command), "start http server");
  open = McpOpen(&mcp, url);
  while (!open && attempts < 100) {
    McpClose(&mcp);
    usleep(50000);
    open = McpOpen(&mcp, url);
    attempts++;
  }
  if (!open) {
    "FAIL http open: %s\n", mcp.error;
    failures++;
  } else {
    Session(&mcp, "http");
    json = McpTool(&mcp, "stop");
    Check(json != NULL, "stop tool");
    Free(json);
  }
  McpClose(&mcp);
  Check(ProcessClose(&process) == 0, "http server exited cleanly");
  Free(server_command);
  Free(url);
}

U0 TestClientDecode()
{
  CMcp mcp;
  CJsonValue value;
  U8 *reply = NULL;
  U8 *text;

  MemSet(&mcp, 0, sizeof(CMcp));
  Check(McpDecode(&mcp,
      "{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{\"ok\":true}}", -1, 7,
      FALSE) && !mcp.error &&
    JsonObjectGet(&mcp.result, "ok", &value), "json body");
  McpReset(&mcp);
  Check(!McpDecode(&mcp, "{\"jsonrpc\":\"2.0\",\"id\":8,\"result\":{}}", -1,
      7, FALSE) && !StrCmp(mcp.error, "no response from server"),
    "other id is ignored");
  McpReset(&mcp);
  Check(McpDecode(&mcp,
      "event: message\r\n"
      "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\"}\r\n"
      "\r\n"
      ": keep-alive\r\n\r\n"
      "id: 3\r\n"
      "data: {\"jsonrpc\":\"2.0\",\"id\":9,\r\n"
      "data:  \"error\":{\"code\":-32000,\"message\":\"nope\"}}\r\n"
      "\r\n", -1, 9, TRUE) && !StrCmp(mcp.error, "nope"), "sse error body");
  McpReset(&mcp);
  Check(McpDecode(&mcp,
      "data: {\"jsonrpc\":\"2.0\",\"id\":\"srv\",\"method\":\"roots/list\"}\n\n"
      "data: {\"jsonrpc\":\"2.0\",\"id\":10,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"a\"},{\"type\":\"image\"},{\"type\":\"text\",\"text\":\"b\"}]}}\n",
      -1, 10, TRUE) && !mcp.error, "sse without trailing blank line");
  Check(JsonPathGet(&mcp.json, "$.result.content[1].type", &value),
    "raw message kept");
  text = McpText(&mcp);
  Check(!StrCmp(text, "a\nb"), "text joins parts");
  Free(text);
  McpReset(&mcp);
  Check(McpAccept(&mcp,
      "{\"jsonrpc\":\"2.0\",\"id\":\"srv-1\",\"method\":\"roots/list\"}", -1,
      1, &reply) == 2 &&
    !StrCmp(reply,
      "{\"jsonrpc\":\"2.0\",\"id\":\"srv-1\",\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}"),
    "server request gets a reply");
  Free(reply);
  reply = NULL;
  Check(!McpAccept(&mcp,
      "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/message\"}", -1, 1,
      &reply) && !reply, "notification is skipped");
  McpReset(&mcp);
}

U8 *Add(CMcpServer *server, CMcpEntry *entry, CJsonValue *params)
{
  CJsonValue a;
  CJsonValue b;
  I64 x = 0;
  I64 y = 0;
  U8 *text;
  U8 *result;

  if (!JsonPathGet(params, "$.arguments.a", &a) ||
    !JsonPathGet(params, "$.arguments.b", &b))
    return McpResultText("a and b are required", TRUE);
  JsonValueAsI64(&a, &x);
  JsonValueAsI64(&b, &y);
  text = MStrPrint("%d", x + y);
  result = McpResultText(text);
  Free(text);
  return result;
}

U0 TestServerCore()
{
  CMcpServer server;
  U8 *response;

  McpServerInit(&server, "core", "2");
  McpServerTool(&server, "add", "Add", NULL, &Add);
  Check(!McpServerTool(&server, "bad", NULL, "{", &Add),
    "schema must be JSON");
  response = McpServerHandle(&server,
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"t\",\"version\":\"0\"}}}");
  "init: %s\n", response;
  Free(response);
  Check(!McpServerHandle(&server,
      "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"),
    "notification has no response");
  Check(!McpServerHandle(&server,
      "{\"jsonrpc\":\"2.0\",\"id\":\"x\",\"result\":[]}"),
    "client response is ignored");
  response = McpServerHandle(&server,
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"add\",\"arguments\":{\"a\":40,\"b\":2}}}");
  "call: %s\n", response;
  Free(response);
  response = McpServerHandle(&server,
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"add\"}}");
  "call error: %s\n", response;
  Free(response);
  response = McpServerHandle(&server,
    "{\"jsonrpc\":\"2.0\",\"id\":\"s4\",\"method\":\"prompts/get\",\"params\":{\"name\":\"nope\"}}");
  "unknown prompt: %s\n", response;
  Free(response);
  response = McpServerHandle(&server, "{\"jsonrpc\":\"2.0\",\"id\":5}");
  "no method: %s\n", response;
  Free(response);
  response = McpServerHandle(&server, "{oops");
  "parse error: %s\n", response;
  Free(response);
  response = McpServerHandle(&server,
    "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"resources/list\"}");
  "empty list: %s\n", response;
  Free(response);
  McpServerFini(&server);
}

U0 Main(I64 ac, U8 **av)
{
  TestClientDecode;
  TestServerCore;
  if (ac > 0) {
    TestStdio(av[0]);  // AOT argv excludes the program name
    TestHttp(av[0]);
  }
  if (failures)
    Exit(1);
  "mcp ok\n";
}

Main(argc, argv);
