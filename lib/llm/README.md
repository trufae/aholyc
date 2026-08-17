# LLM client

`lib/llm/llm.hc` talks to OpenAI-compatible Chat Completions endpoints
(OpenAI, Ollama, llama.cpp, vLLM, OpenRouter, ...) and to the OpenAI
Responses API through `lib/net/http.hc`. A `CLlm` owns the conversation; the
caller only frees the reply strings.

```holyc
#include "lib/llm/llm.hc"

extern U8 *getenv(U8 *name);

CLlm llm;
U8 *answer;

LlmInit(&llm, "https://api.openai.com/v1/chat/completions", "gpt-4o-mini",
  getenv("OPENAI_API_KEY"));
LlmSystem(&llm, "Answer briefly.");
answer = LlmAsk(&llm, "Why is the sky blue?");
if (answer)
  "%s\n", answer;
else
  "error: %s\n", llm.error;
Free(answer);
LlmFini(&llm);
```

Every `LlmAsk` appends the user turn and the assistant reply to the history,
so calling it again continues the conversation. Local servers need no key:
`LlmInit(&llm, "http://127.0.0.1:11434/v1/chat/completions", "gpt-oss:20b")`.
The Responses API is selected automatically when the URL ends in
`/responses`; the system prompt then travels as `instructions` and content
parts use the `input_*` names.

## API

| Function | Purpose |
| --- | --- |
| `LlmInit(&llm, url, model, api_key=NULL, headers=NULL)` | Bind endpoint, model, bearer key and extra `Name: value\r\n` header lines. |
| `LlmFini(&llm)` | Release history, headers and the last response. |
| `LlmSystem(&llm, prompt)` | Set (or clear with `NULL`) the system prompt. |
| `LlmSet(&llm, key, json)` | Add a top-level request field: `"temperature"`, `"tools"`, `"response_format"`, ... The value is validated JSON text. |
| `LlmImage(&llm, url, detail=NULL)` | Queue an image (http(s) or `data:` URL) for the next message. |
| `LlmFile(&llm, file_id, filename=NULL, data_url=NULL)` | Queue an uploaded file id, or inline data as filename plus `data:` URL. |
| `LlmMessage(&llm, role, text)` | Append a message together with the queued attachments. |
| `LlmRaw(&llm, json)` | Append a complete JSON message object (tool results, assistant `tool_calls`, ...). |
| `LlmRequest(&llm)` | Build the request body without sending it. Caller frees. |
| `LlmSend(&llm)` | POST the conversation; returns the reply (caller frees) and appends it to the history, or `NULL` with `llm.error` set. |
| `LlmAsk(&llm, text)` | `LlmMessage(&llm, "user", text)` followed by `LlmSend`. |
| `LlmParse(&llm, body, length=-1)` | Decode a response body without a transport; used by `LlmSend` and by tests. |

After a call, `llm.response` holds the raw `CHttpResponse`, `llm.json` the
decoded body for `JsonPathGet` (tool calls, provider extras), and
`llm.input_tokens` / `llm.output_tokens` the usage counters (`-1` if absent).
They stay valid until the next `LlmSend` or `LlmFini`.

## Images and files

Attachments are queued and flushed by the next `LlmMessage`/`LlmAsk`. Reading
files is not part of this library; use `lib/io/file.hc` and
`lib/text/base64.hc`:

```holyc
#include "lib/io/file.hc"
#include "lib/text/base64.hc"

I64 size;
U8 *png = FileRead("photo.png", &size);
U8 *b64 = Base64EncodeAlloc(png, size);
U8 *url = MStrPrint("data:image/png;base64,%s", b64);

LlmImage(&llm, url, "auto");
answer = LlmAsk(&llm, "What is in this picture?");
Free(url);
Free(b64);
Free(png);
```

## Tools and provider options

Anything the helpers do not cover goes through JSON text: `LlmSet` for
request fields such as `tools`, `LlmRaw` for messages such as tool results,
and `llm.json` for reading the answer. `lib/json/pj.hc` (the builder this
library uses internally) is the easy way to produce those documents:

```holyc
LlmSet(&llm, "tools",
  "[{\"type\":\"function\",\"function\":{\"name\":\"lookup\","
  "\"parameters\":{\"type\":\"object\"}}}]");
if (!LlmAsk(&llm, "Look up X") &&
  JsonPathGet(&llm.json, "$.choices[0].message.tool_calls", &calls))
  ...
LlmRaw(&llm, "{\"role\":\"tool\",\"tool_call_id\":\"call_1\",\"content\":\"42\"}");
```

A tool-call turn has no text, so `LlmSend` returns `NULL` and leaves the
history untouched: re-add the assistant message from `llm.json` with `LlmRaw`
before appending the tool result and sending again.

The transport is blocking, like `lib/net/http.hc`. Streaming (`"stream": true`)
is not interpreted; the buffered SSE body is available as `llm.response->body`.
