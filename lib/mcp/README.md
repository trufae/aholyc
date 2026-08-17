# Model Context Protocol

`lib/mcp` implements both ends of MCP on `lib/json`, `lib/io/process.hc` and
`lib/http`:

- `client.hc` — connect to a server over stdio or Streamable HTTP; list and
  call tools, prompts and resources.
- `server.hc` — register tools, prompts and resources with handler
  functions; serve them over stdio or Streamable HTTP.
- `jsonrpc.hc` — the JSON-RPC builders and newline framing both share.

Everything is JSON text in and out (build params with `lib/json/pj.hc`,
read results with `lib/json/query.hc`), one owning object per side, and
transports are blocking.

## Client

```holyc
#include "lib/mcp/client.hc"

CMcp mcp;
U8 *tools;
U8 *text;

if (!McpOpen(&mcp, "npx -y @modelcontextprotocol/server-everything")) {
  "error: %s\n", mcp.error;
} else {
  tools = McpList(&mcp, "tools");                     // JSON array
  if (McpTool(&mcp, "echo", "{\"message\":\"hi\"}")) {
    text = McpText(&mcp);                             // "Echo: hi"
    Free(text);
  } else {
    "tool error: %s\n", mcp.error;
  }
  Free(tools);
}
McpClose(&mcp);
```

The target decides the transport: an `http://` or `https://` URL is a
Streamable HTTP endpoint (`Mcp-Session-Id` and `MCP-Protocol-Version` are
handled, the session is deleted by `McpClose`), anything else is a command
line started with piped stdio and shut down per the MCP sequence (stdin
EOF, SIGTERM, SIGKILL). Remote servers usually want a bearer token:
`McpOpen(&mcp, "https://mcp.example.com/mcp", getenv("MCP_TOKEN"))`; extra
`"Name: value\r\n"` header lines go in the fourth argument.

| Function | Purpose |
| --- | --- |
| `McpOpen(&mcp, target, token=NULL, headers=NULL)` | Connect and run `initialize`; FALSE with `mcp.error` set (still call `McpClose`). |
| `McpClose(&mcp)` | Terminate the session/process and release everything. |
| `McpList(&mcp, kind)` | `"tools"`, `"prompts"`, `"resources"` or `"resources/templates"` as one JSON array, following pagination. Caller frees. |
| `McpTool(&mcp, name, arguments=NULL)` | `tools/call` with a JSON object of arguments. Returns the result JSON (caller frees); a tool that reports `isError` returns `NULL` with its text in `mcp.error`. |
| `McpPrompt(&mcp, name, arguments=NULL)` | `prompts/get`; the result has `$.messages`. |
| `McpResource(&mcp, uri)` | `resources/read`; the result has `$.contents`. |
| `McpText(&mcp)` | Join the text parts of the last result (tool content, prompt messages, resource contents). Caller frees; `NULL` when there is none. |
| `McpCall(&mcp, method, params=NULL)` | Any JSON-RPC request; returns the result JSON or `NULL` with `mcp.error`. |
| `McpNotify(&mcp, method, params=NULL)` | Any JSON-RPC notification. |

After a call `mcp.result` holds the decoded result for `JsonPathGet` and
`mcp.json` the whole response; `mcp.server` is the decoded `initialize`
result (`$.serverInfo.name`, `$.instructions`, `$.capabilities`) and
`mcp.version` the negotiated protocol version. Over HTTP `mcp.response`
keeps the last `CHttpResponse`.

Notifications from the server are skipped and its requests (`roots/list`,
sampling, elicitation) are answered with "Method not found" over stdio; the
client declares no capabilities. Streaming progress is not surfaced: the
HTTP transport reads the whole SSE response, so servers must end the stream
after answering (as the SDKs do). The legacy HTTP+SSE transport (separate
`/sse` endpoint) is not supported.

Feeding tools to `lib/llm/llm.hc` is a matter of reshaping the `McpList`
array into the provider's `tools` field with `lib/json/pj.hc`, and passing
each `tool_call` to `McpTool`.

## Server

```holyc
#include "lib/mcp/server.hc"

U8 *Echo(CMcpServer *server, CMcpEntry *entry, CJsonValue *params)
{
  CJsonValue message;
  U8 *text;
  U8 *result;

  if (!JsonPathGet(params, "$.arguments.message", &message))
    return McpResultText("message is required", TRUE);   // isError
  text = JsonValueStringNew(&message);
  result = McpResultText(text);
  Free(text);
  return result;
}

CMcpServer server;
McpServerInit(&server, "echo-server", "1.0", "Call echo to hear yourself.");
McpServerTool(&server, "echo", "Echo a message",
  "{\"type\":\"object\",\"properties\":{\"message\":{\"type\":\"string\"}}}",
  &Echo);
McpServerRun(&server);                       // stdio; or McpServerRunHttp
McpServerFini(&server);
```

The registry stores only the pointers it is given (string literals or
memory the caller keeps alive), so a server costs one small node per entry.
The protocol core `McpServerHandle` turns one JSON-RPC message into one
response string; the transports are thin loops on top of it, and any other
transport can drive it the same way.

| Function | Purpose |
| --- | --- |
| `McpServerInit(&s, name, version="1", instructions=NULL)` | Set up an empty registry. `s.page_size` (0 = all) enables list pagination. |
| `McpServerFini(&s)` | Free the registry. |
| `McpServerTool(&s, name, description, input_schema, handler)` | Register a tool; `input_schema` is a JSON Schema object or `NULL` for `{"type":"object"}`. |
| `McpServerPrompt(&s, name, description, arguments, handler)` | Register a prompt; `arguments` is the JSON array of argument descriptors or `NULL`. |
| `McpServerResource(&s, uri, name, mime_type, handler)` | Register a resource. |
| `McpServerRun(&s)` | Serve newline-delimited JSON-RPC on stdin/stdout until EOF or `McpServerStop`. |
| `McpServerRunHttp(&s, port, host="127.0.0.1", path="/mcp", token=NULL)` | Serve Streamable HTTP (stateless, JSON responses); a `token` requires `Authorization: Bearer`. |
| `McpServerHandle(&s, message, length=-1)` | Protocol core: response text for one message (caller frees) or `NULL` when nothing is sent back. |
| `McpServerNotify(&s, method, params=NULL)` | Push a notification to the client (stdio only). |
| `McpServerFail(&s, message)` / `McpServerStop(&s)` | Set the error for a `NULL` handler result; leave the serving loop. |
| `McpResultText(text, is_error=FALSE)` | Build a `tools/call` result with one text part. |
| `McpResultMessage(role, text, description=NULL)` | Build a `prompts/get` result with one text message. |
| `McpResultContents(uri, mime_type, text)` | Build a `resources/read` result. |

Handlers get `(server, entry, params)`: `entry` is the registered node
(`entry->name` is the tool/prompt name or resource uri, `entry->mime` the
mime type) and `params` the request params (`$.arguments.x`, `$.uri`). They
return the JSON result text (the server frees it) or `NULL`; a `NULL` from a
tool becomes an `isError` result carrying `McpServerFail`'s message, from a
prompt or resource a JSON-RPC error. `initialize` echoes the client's
protocol version and advertises only the capabilities that have entries;
`ping`, `*/list` with cursors and `resources/templates/list` (empty) are
built in. Windows note: stdio uses the C runtime's `_read`/`_write`, so
responses may end in `\r\n`, which clients accept.

`tests/mcp_server.HC` is a complete server example; `tests/mcp.HC` runs the
client against it over both transports.
