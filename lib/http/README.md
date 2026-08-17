# HTTP client, server and SSE

`lib/http` builds on `lib/net` (sockets and TLS). `http.hc` holds what both
sides share (URL parsing and percent coding, header lookup, chunked
decoding); applications include `client.hc`, `server.hc` or `sse.hc`.

## Client

```holyc
#include "lib/http/client.hc"

CHttpResponse *response = HttpGet("https://example.com/");
if (response->error)
  "request failed: %s\n", response->error;
else
  "HTTP %d, %d body bytes\n", response->status, response->body_length;
HttpResponseFree(response);

U8 binary[4] = {0, 1, 2, 255};
response = HttpPost("https://example.com/upload", binary, 4,
  "application/octet-stream");
HttpResponseFree(response);
```

`HttpRequest(method, url, extra_headers, body, body_length, content_type)`
is the general form; `HttpGet` and `HttpPost` wrap it. Responses expose
status, headers and a binary-safe body; `HttpHeaderValue` returns an
allocated header value. The default `Accept: */*` and `User-Agent` are
skipped when the extra `"Name: value\r\n"` lines provide their own.

The client is blocking, supports HTTP and HTTPS, IPv4/IPv6 host syntax,
`Content-Length`, chunked transfer coding and connection-close framing. It
does not follow redirects or decompress content encodings. Define
`HTTP_MAX_MESSAGE` before inclusion to change the 256 MiB limit shared with
the server.

`HttpUrlEncode`/`HttpUrlDecode` implement RFC-style percent coding with
explicit lengths; `HttpFormEncode`/`HttpFormDecode` also map spaces to `+`.

## Server

```holyc
#include "lib/http/server.hc"

CHttpServer server;
CHttpRequest *request;

if (HttpServerListen(&server, 8080)) {              // host defaults to 127.0.0.1
  while (request = HttpServerAccept(&server)) {
    if (!request->error) {
      "%s %s (%d body bytes)\n", request->method, request->target,
        request->body_length;
      HttpRespond(request, 200, "hello\n", 6, "text/plain",
        "X-Powered-By: aholyc\r\n");
    }
    HttpRequestFree(request);
  }
}
HttpServerClose(&server);
```

The server is deliberately small: blocking, one connection at a time,
`Connection: close`, plain HTTP (put a reverse proxy in front for TLS or
concurrency). `HttpServerAccept` reads and frames the whole request
(`Content-Length` or chunked, decoded, bounded by `HTTP_MAX_MESSAGE`),
answers malformed input with 400 itself and returns it with
`request->error` set. `HttpRequestHeader` returns an allocated header value;
`HttpRespond` sends status, `Content-Type`, `Content-Length` and any extra
header lines, then closes the connection.

## Server-Sent Events

`sse.hc` parses a `text/event-stream` body held in memory, such as the body
of a `CHttpResponse` (the client buffers whole responses, so this suits
servers that end the stream after answering, e.g. MCP):

```holyc
#include "lib/http/sse.hc"

CSse sse;
SseInit(&sse, response->body, response->body_length);
while (SseNext(&sse))
  "%s [%s]: %s\n", sse.event, sse.id, sse.data;   // data lines joined by \n
SseFini(&sse);
```

`sse.event` defaults to `"message"`, `sse.id` is `NULL` when absent, and the
strings stay valid until the next `SseNext` or `SseFini`. `\n`, `\r\n` and
`\r` line endings and `:` comment lines are handled; a final event without a
trailing blank line is still delivered.
