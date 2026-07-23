# Portable sockets, TLS, and HTTP

These HolyC modules target aholyc's native C and LLVM backends on Linux,
macOS, and Windows. They are deliberately blocking and small enough to read.

## Sockets

Include `socket.hc` for TCP and UDP:

```holyc
#include "lib/socket/socket.hc"

I64 server = TcpListen(8080, "127.0.0.1");
I64 client = TcpAccept(server);

U8 buffer[4096];
I64 size = SocketRecv(client, buffer, sizeof(buffer));
if (size > 0)
  SocketSendAll(client, buffer, size);

SocketClose(client);
SocketClose(server);
SocketFini;
```

The main entry points are:

- `TcpListen`, `TcpAccept`, and `TcpConnect`
- `UdpBind`, `UdpConnect`, `UdpSendTo`, and `UdpRecv`
- `UdpRecvFrom` plus `UdpSendAddress` to receive a datagram and reply to its
  opaque portable source address
- `SocketSend`, `SocketSendAll`, `SocketRecv`, `SocketShutdown`, and
  `SocketClose`
- `SocketLastError` for the last native or resolver error

Handles use `SOCKET_INVALID` (`-1`) on failure. Buffers always have explicit
byte lengths, so binary data is safe. On Windows, `SocketInit` dynamically
loads Winsock; all high-level constructors call it automatically.

## TLS

Include `ssl.hc` for a dynamically loaded OpenSSL client:

```holyc
#include "lib/socket/socket.hc"
#include "lib/socket/ssl.hc"

I64 socket = TcpConnect("example.com", 443);
CSsl *tls = SslConnect(socket, "example.com");
if (!tls)
  "TLS error: %s\n", SslLastError;

// SslRead, SslWrite, and SslWriteAll use explicit byte lengths.

SslClose(tls);
SocketClose(socket);
SslFini;
SocketFini;
```

`SslInit` probes common OpenSSL 3.x and 1.1 shared-library paths and resolves
symbols with `dlopen`/`dlsym` or `LoadLibraryA`/`GetProcAddress`. The final
program does not link OpenSSL. TLS requires version 1.2 or newer and verifies
both the CA chain and hostname. If OpenSSL's default CA path is unsuitable,
call `SslSetCaLocations(ca_file, ca_directory)` before connecting.

Applications include only `ssl.hc`. It selects `ssl_linux.hc`,
`ssl_macos.hc`, or `ssl_windows.hc` using aholyc's `IS_LINUX`, `IS_MACOS`,
and `IS_WINDOWS` predefined macros.

All `CSsl` sessions must be closed before `SslFini` unloads the libraries.

## HTTP

Including `http.hc` includes both lower layers:

```holyc
#include "lib/socket/http.hc"

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

`HttpRequest` accepts a method, optional raw header lines, a body pointer,
an explicit body length, and a content type. `HttpGet` and `HttpPost` are
convenience wrappers. Responses expose status, headers, and a binary-safe
body; use `HttpHeaderValue` to obtain an allocated header value.

`HttpUrlEncode`/`HttpUrlDecode` implement RFC-style percent coding and accept
explicit lengths. `HttpFormEncode`/`HttpFormDecode` additionally translate
spaces to/from `+`. Decode functions return the decoded byte length through
an optional output pointer.

The client supports HTTP and HTTPS, IPv4/IPv6 host syntax, `Content-Length`,
chunked transfer coding, and connection-close framing. It does not
automatically follow redirects or decompress content encodings. Define
`HTTP_MAX_MESSAGE` before inclusion to change the default 256 MiB limit.
