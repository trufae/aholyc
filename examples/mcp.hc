// MCP client walk-through: list what a server offers, then call a tool.
//
//   ./aholyc run examples/mcp.hc -- "npx -y @modelcontextprotocol/server-everything"
//   ./aholyc run examples/mcp.hc -- "npx -y @modelcontextprotocol/server-everything" echo '{"message":"hi"}'
//   MCP_TOKEN=... ./aholyc run examples/mcp.hc -- https://mcp.example.com/mcp
//
// The first argument is a stdio command line or an http(s):// endpoint; the
// bearer token comes from $MCP_TOKEN. With a tool name (and optional JSON
// arguments) the tool is called and its text content printed.

#include "../lib/mcp/client.hc"

extern U8 *getenv(U8 *name);

U0 Show(CMcp *mcp, U8 *kind)
{
  U8 *json = McpList(mcp, kind);

  if (json)
    "%s: %s\n", kind, json;
  else
    "%s: %s\n", kind, mcp->error;
  Free(json);
}

U0 Main(I64 ac, U8 **av)
{
  CMcp mcp;
  CJsonValue value;
  U8 *arguments = NULL;
  U8 *json;
  U8 *text;

  if (ac < 1) {
    "usage: mcp <command|url> [tool [arguments-json]]\n";
    Exit(1);
  }
  if (!McpOpen(&mcp, av[0], getenv("MCP_TOKEN"))) {
    "error: %s\n", mcp.error;
    McpClose(&mcp);
    Exit(1);
  }
  if (JsonPathGet(&mcp.server, "$.serverInfo.name", &value)) {
    text = JsonValueStringNew(&value);
    "server: %s (protocol %s)\n", text, mcp.version;
    Free(text);
  }
  if (ac < 2) {
    Show(&mcp, "tools");
    Show(&mcp, "prompts");
    Show(&mcp, "resources");
  } else {
    if (ac > 2)
      arguments = av[2];
    json = McpTool(&mcp, av[1], arguments);
    if (json) {
      text = McpText(&mcp);
      if (text)
        "%s\n", text;
      else
        "%s\n", json;
      Free(text);
    } else {
      "error: %s\n", mcp.error;
    }
    Free(json);
  }
  McpClose(&mcp);
}

Main(argc, argv);
