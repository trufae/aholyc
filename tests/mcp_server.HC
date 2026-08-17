// MCP server fixture for tests/mcp.HC built on lib/mcp/server.hc: a couple
// of tools, a prompt and a resource, served over stdio by default or over
// Streamable HTTP with "http <port>". Tool "stop" ends the serving loop.

#include "../lib/mcp/server.hc"

U8 *Echo(CMcpServer *server, CMcpEntry *entry, CJsonValue *params)
{
  CJsonValue value;
  U8 *message = NULL;
  U8 *text;
  U8 *result;

  // A notification before the response: the client must skip it.
  McpServerNotify(server, "notifications/message",
    "{\"level\":\"info\",\"data\":\"working\"}");
  if (JsonPathGet(params, "$.arguments.message", &value))
    message = JsonValueStringNew(&value);
  if (message)
    text = MStrPrint("Echo: %s", message);
  else
    text = StrNew("Echo:");
  result = McpResultText(text);
  Free(text);
  Free(message);
  return result;
}

U8 *Fail(CMcpServer *server, CMcpEntry *entry, CJsonValue *params)
{
  return McpResultText("boom", TRUE);
}

U8 *Stop(CMcpServer *server, CMcpEntry *entry, CJsonValue *params)
{
  McpServerStop(server);
  return McpResultText("bye");
}

U8 *Greet(CMcpServer *server, CMcpEntry *entry, CJsonValue *params)
{
  CJsonValue value;
  U8 *who;
  U8 *text;
  U8 *result;

  if (!JsonPathGet(params, "$.arguments.who", &value)) {
    McpServerFail(server, "who is required");
    return NULL;
  }
  who = JsonValueStringNew(&value);
  text = MStrPrint("Hello %s", who);
  result = McpResultMessage("user", text);
  Free(text);
  Free(who);
  return result;
}

U8 *ReadA(CMcpServer *server, CMcpEntry *entry, CJsonValue *params)
{
  return McpResultContents(entry->name, entry->mime, "contents of a");
}

U0 Main(I64 ac, U8 **av)
{
  CMcpServer server;
  I64 port = 0;

  McpServerInit(&server, "fake", "0.1", "Be nice.");
  server.page_size = 2;
  McpServerTool(&server, "echo", "Echo a message",
    "{\"type\":\"object\",\"properties\":{\"message\":{\"type\":\"string\"}}}",
    &Echo);
  McpServerTool(&server, "fail", "Always fails", NULL, &Fail);
  McpServerTool(&server, "stop", "Stop the server", NULL, &Stop);
  McpServerPrompt(&server, "greet", NULL, "[{\"name\":\"who\"}]", &Greet);
  McpServerResource(&server, "file:///a.txt", "a", "text/plain", &ReadA);
  if (ac >= 2 && !StrCmp(av[0], "http") &&
    HttpParseDecimal(av[1], &port))
    McpServerRunHttp(&server, port);
  else
    McpServerRun(&server);
  McpServerFini(&server);
}

Main(argc, argv);
