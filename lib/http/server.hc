#ifndef AHOLYC_LIB_HTTP_SERVER_HC
#define AHOLYC_LIB_HTTP_SERVER_HC

// Blocking HTTP/1.1 server that handles one connection at a time: accept a
// request, answer it, close. Small enough for local tools, health endpoints
// and protocol servers such as MCP; put a reverse proxy in front for TLS
// or concurrency.
//
//   CHttpServer server;
//   CHttpRequest *request;
//   if (HttpServerListen(&server, 8080)) {
//     while (request = HttpServerAccept(&server)) {
//       if (!request->error)
//         HttpRespond(request, 200, "hello\n", 6, "text/plain");
//       HttpRequestFree(request);
//     }
//   }
//   HttpServerClose(&server);
//
// Malformed requests are answered with 400 by HttpServerAccept itself and
// returned with request->error set so the loop can log them.  Bodies are
// framed by Content-Length or chunked coding, decoded, and limited by
// HTTP_MAX_MESSAGE.

#include "http.hc"

class CHttpServer
{
  I64 socket;
};

class CHttpRequest
{
  I64 socket;      // SOCKET_INVALID once answered
  U8 *method;
  U8 *target;      // path plus query, always starts with '/'
  U8 *headers;     // request line and header lines
  I64 headers_length;
  U8 *body;
  I64 body_length;
  U8 *error;
};

Bool HttpServerListen(CHttpServer *server, I64 port, U8 *host="127.0.0.1")
{
  server->socket = TcpListen(port, host);
  return server->socket != SOCKET_INVALID;
}

U0 HttpServerClose(CHttpServer *server)
{
  if (server->socket != SOCKET_INVALID)
    SocketClose(server->socket);
  server->socket = SOCKET_INVALID;
}

U8 *HttpRequestHeader(CHttpRequest *request, U8 *name)
{
  if (!request)
    return NULL;
  return HttpHeaderFind(request->headers, request->headers_length, name);
}

U0 HttpRequestFree(CHttpRequest *request)
{
  if (!request)
    return;
  if (request->socket != SOCKET_INVALID)
    SocketClose(request->socket);
  Free(request->method);
  Free(request->target);
  Free(request->headers);
  Free(request->body);
  Free(request->error);
  Free(request);
}

U8 *HttpStatusText(I64 status)
{
  switch (status) {
    case 200: return "OK";
    case 201: return "Created";
    case 202: return "Accepted";
    case 204: return "No Content";
    case 301: return "Moved Permanently";
    case 302: return "Found";
    case 304: return "Not Modified";
    case 400: return "Bad Request";
    case 401: return "Unauthorized";
    case 403: return "Forbidden";
    case 404: return "Not Found";
    case 405: return "Method Not Allowed";
    case 406: return "Not Acceptable";
    case 413: return "Payload Too Large";
    case 415: return "Unsupported Media Type";
    case 500: return "Internal Server Error";
    case 501: return "Not Implemented";
    case 503: return "Service Unavailable";
  }
  return "Status";
}

// Send the response and close the connection. extra_headers holds raw
// "Name: value\r\n" lines. Returns FALSE if the client went away or the
// request was already answered.
Bool HttpRespond(CHttpRequest *request, I64 status, U8 *body=NULL,
  I64 body_length=0, U8 *content_type="text/plain",
  U8 *extra_headers=NULL)
{
  CStrBuf head;
  Bool ok;

  if (!request || request->socket == SOCKET_INVALID || body_length < 0 ||
    body_length && !body)
    return FALSE;
  StrBufInit(&head);
  StrBufPrintf(&head, "HTTP/1.1 %d %s\r\n", status,
    HttpStatusText(status));
  if (!HttpHeadersHave(extra_headers, "Content-Type") && content_type &&
    *content_type && (body_length || status < 300))
    StrBufPrintf(&head, "Content-Type: %s\r\n", content_type);
  StrBufPrintf(&head, "Content-Length: %d\r\n", body_length);
  StrBufPutS(&head, "Connection: close\r\n");
  StrBufPutS(&head, extra_headers);
  if (extra_headers && *extra_headers && head.b[-1] != '\n')
    StrBufPutS(&head, "\r\n");
  StrBufPutS(&head, "\r\n");
  ok = SocketSendAll(request->socket, head.a, StrsLen(&head)) &&
    (!body_length || SocketSendAll(request->socket, body, body_length));
  StrBufFini(&head);
  SocketClose(request->socket);
  request->socket = SOCKET_INVALID;
  return ok;
}

// Parse "METHOD target HTTP/1.x"; FALSE on anything else.
Bool HttpParseRequestLine(CHttpRequest *request)
{
  U8 *line = request->headers;
  I64 i = 0;
  I64 method_end;
  I64 target_start;
  I64 target_end;

  while (i < request->headers_length && line[i] != ' ' && line[i] != '\r')
    i++;
  method_end = i;
  if (!method_end || i >= request->headers_length || line[i] != ' ')
    return FALSE;
  target_start = ++i;
  while (i < request->headers_length && line[i] != ' ' && line[i] != '\r')
    i++;
  target_end = i;
  if (target_end == target_start || i >= request->headers_length ||
    line[i] != ' ')
    return FALSE;
  if (!HttpStartsWithInsensitive(line + i + 1, "HTTP/1."))
    return FALSE;
  request->method = HttpSlice(line, 0, method_end);
  request->target = HttpSlice(line, target_start, target_end);
  return HttpMethodIsSafe(request->method) &&
    HttpTargetIsSafe(request->target);
}

// Read one request from a connected socket into request. Returns FALSE with
// request->error set on malformed or oversized input.
Bool HttpReadRequest(CHttpRequest *request)
{
  CStrBuf raw;
  U8 chunk[8192];
  U8 *transfer_encoding = NULL;
  U8 *content_length_text = NULL;
  U8 *decoded = NULL;
  I64 decoded_size = 0;
  I64 header_finish = -1;
  I64 content_length = -1;
  I64 received;
  Bool chunked = FALSE;
  Bool ok = FALSE;

  StrBufInit(&raw);
  while (TRUE) {
    if (header_finish >= 0) {
      if (chunked) {
        decoded = HttpDecodeChunked(raw.a + header_finish,
          StrsLen(&raw) - header_finish, &decoded_size);
        if (decoded) {
          request->body = decoded;
          request->body_length = decoded_size;
          decoded = NULL;
          ok = TRUE;
          break;
        }
      } else if (StrsLen(&raw) - header_finish >= content_length) {
        request->body = HttpSlice(raw.a, header_finish,
          header_finish + content_length);
        request->body_length = content_length;
        ok = TRUE;
        break;
      }
    }
    received = SocketRecv(request->socket, chunk, sizeof(chunk));
    if (received <= 0) {
      Free(request->error);
      request->error = StrNew("incomplete HTTP request");
      break;
    }
    if (!HttpBufferAppend(&raw, chunk, received)) {
      Free(request->error);
      request->error = StrNew("HTTP request exceeds limit");
      break;
    }
    if (header_finish < 0)
      header_finish = HttpFindHeaderEnd(raw.a, StrsLen(&raw));
    if (header_finish >= 0 && !request->headers) {
      request->headers_length = header_finish - 2;
      request->headers = HttpSlice(raw.a, 0, request->headers_length);
      if (!HttpParseRequestLine(request)) {
        Free(request->error);
        request->error = StrNew("malformed HTTP request line");
        break;
      }
      transfer_encoding = HttpRequestHeader(request, "Transfer-Encoding");
      content_length_text = HttpRequestHeader(request, "Content-Length");
      chunked = HttpValueHasToken(transfer_encoding, "chunked");
      content_length = 0;
      if (!chunked && content_length_text &&
        !HttpParseDecimal(content_length_text, &content_length)) {
          Free(request->error);
          request->error = StrNew("invalid Content-Length");
          break;
        }
    }
  }
  Free(transfer_encoding);
  Free(content_length_text);
  Free(decoded);
  StrBufFini(&raw);
  return ok;
}

// Wait for the next connection and read its request. Returns NULL only when
// accepting fails (server closed); a bad request is answered with 400 and
// returned with request->error set.
CHttpRequest *HttpServerAccept(CHttpServer *server)
{
  CHttpRequest *request;
  I64 client;

  if (server->socket == SOCKET_INVALID)
    return NULL;
  client = TcpAccept(server->socket);
  if (client == SOCKET_INVALID)
    return NULL;
  request = CAlloc(sizeof(CHttpRequest));
  request->socket = client;
  if (!HttpReadRequest(request))
    HttpRespond(request, 400, request->error, StrLen(request->error));
  return request;
}

#endif
