#ifndef AHOLYC_LIB_HTTP_CLIENT_HC
#define AHOLYC_LIB_HTTP_CLIENT_HC

// Blocking HTTP/1.1 client with binary-safe request and response bodies.
//
//   CHttpResponse *r = HttpGet("https://example.com/");
//   if (r->error)
//     "error: %s\n", r->error;
//   else
//     "status=%d body-bytes=%d\n", r->status, r->body_length;
//   HttpResponseFree(r);
//
//   U8 bytes[4] = {0, 1, 2, 255};
//   r = HttpPost("https://example.com/upload", bytes, 4,
//     "application/octet-stream");
//
// Response body buffers have one convenience NUL after body_length, but the
// length is authoritative and embedded NUL bytes are preserved.  Redirects
// are returned to the caller rather than followed automatically.

#include "http.hc"
#include "../net/ssl.hc"

class CHttpResponse
{
  I64 status;
  U8 *headers;
  I64 headers_length;
  U8 *body;
  I64 body_length;
  U8 *error;
};

CHttpResponse *HttpResponseNew()
{
  return CAlloc(sizeof(CHttpResponse));
}

U0 HttpResponseSetError(CHttpResponse *response, U8 *message)
{
  Free(response->error);
  response->error = StrNew(message);
}

U0 HttpResponseFree(CHttpResponse *response)
{
  if (!response)
    return;
  Free(response->headers);
  Free(response->body);
  Free(response->error);
  Free(response);
}

U8 *HttpHostHeader(CHttpUrl *url)
{
  Bool default_port = !url->secure && url->port == 80 ||
    url->secure && url->port == 443;

  if (url->ipv6) {
    if (default_port)
      return MStrPrint("[%s]", url->host);
    return MStrPrint("[%s]:%d", url->host, url->port);
  }
  if (default_port)
    return StrNew(url->host);
  return MStrPrint("%s:%d", url->host, url->port);
}

I64 HttpParseStatus(U8 *headers, I64 size)
{
  I64 i = 0;

  while (i < size && headers[i] != ' ' && headers[i] != '\r')
    i++;
  while (i < size && headers[i] == ' ')
    i++;
  if (i + 2 >= size ||
    headers[i] < '0' || headers[i] > '9' ||
    headers[i + 1] < '0' || headers[i + 1] > '9' ||
    headers[i + 2] < '0' || headers[i + 2] > '9')
    return 0;
  return (headers[i] - '0') * 100 +
    (headers[i + 1] - '0') * 10 + headers[i + 2] - '0';
}

U8 *HttpHeaderValue(CHttpResponse *response, U8 *name)
{
  if (!response)
    return NULL;
  return HttpHeaderFind(response->headers, response->headers_length, name);
}

Bool HttpCopyBody(CHttpResponse *response, U8 *data, I64 size)
{
  if (size < 0 || size > HTTP_MAX_MESSAGE)
    return FALSE;
  response->body = MAlloc(size + 1);
  if (size)
    MemCpy(response->body, data, size);
  response->body[size] = 0;
  response->body_length = size;
  return TRUE;
}

Bool HttpSendBytes(I64 socket, CSsl *tls, U8 *data, I64 size)
{
  if (tls)
    return SslWriteAll(tls, data, size);
  return SocketSendAll(socket, data, size);
}

I64 HttpRecvBytes(I64 socket, CSsl *tls, U8 *data, I64 capacity)
{
  if (tls)
    return SslRead(tls, data, capacity);
  return SocketRecv(socket, data, capacity);
}

CHttpResponse *HttpRequest(U8 *method, U8 *url_text,
  U8 *extra_headers=NULL, U8 *body=NULL, I64 body_length=0,
  U8 *content_type=NULL)
{
  CHttpResponse *response = HttpResponseNew;
  CHttpUrl url;
  CHttpBuffer request;
  CHttpBuffer raw;
  U8 *host_header = NULL;
  U8 receive_buffer[8192];
  U8 *transfer_encoding = NULL;
  U8 *content_length_text = NULL;
  U8 *decoded = NULL;
  I64 decoded_size = 0;
  I64 socket = SOCKET_INVALID;
  CSsl *tls = NULL;
  I64 received;
  I64 header_finish;
  I64 available;
  I64 content_length;
  Bool transport_ok = FALSE;

  HttpBufferInit(&request);
  HttpBufferInit(&raw);

  if (!HttpMethodIsSafe(method)) {
    HttpResponseSetError(response, "invalid HTTP method");
    goto http_request_done;
  }
  if (body_length < 0 || body_length && !body) {
    HttpResponseSetError(response, "invalid HTTP request body");
    goto http_request_done;
  }
  if (!HttpUrlParse(url_text, &url)) {
    HttpResponseSetError(response, "invalid HTTP URL");
    goto http_request_done;
  }

  host_header = HttpHostHeader(&url);
  if (!HttpBufferAppendFormat(&request, "%s %s HTTP/1.1\r\n",
      method, url.target) ||
    !HttpBufferAppendFormat(&request, "Host: %s\r\n", host_header) ||
    !HttpHeadersHave(extra_headers, "User-Agent") &&
    !HttpBufferAppendString(&request, "User-Agent: aholyc-http/1\r\n") ||
    !HttpHeadersHave(extra_headers, "Accept") &&
    !HttpBufferAppendString(&request, "Accept: */*\r\n") ||
    !HttpBufferAppendString(&request, "Connection: close\r\n")) {
      HttpResponseSetError(response, "HTTP request is too large");
      goto http_request_url_done;
    }
  if (content_type && *content_type &&
    !HttpBufferAppendFormat(&request, "Content-Type: %s\r\n",
      content_type)) {
        HttpResponseSetError(response, "HTTP request is too large");
        goto http_request_url_done;
      }
  if ((body_length || HttpEqualsInsensitive(method, "POST")) &&
    !HttpBufferAppendFormat(&request, "Content-Length: %d\r\n",
      body_length)) {
        HttpResponseSetError(response, "HTTP request is too large");
        goto http_request_url_done;
      }
  if (extra_headers && *extra_headers) {
    if (!HttpBufferAppendString(&request, extra_headers)) {
      HttpResponseSetError(response, "HTTP request is too large");
      goto http_request_url_done;
    }
    if (request.length < 1 || request.data[request.length - 1] != '\n') {
      if (!HttpBufferAppendString(&request, "\r\n")) {
        HttpResponseSetError(response, "HTTP request is too large");
        goto http_request_url_done;
      }
    }
  }
  if (!HttpBufferAppendString(&request, "\r\n")) {
    HttpResponseSetError(response, "HTTP request is too large");
    goto http_request_url_done;
  }

  socket = TcpConnect(url.host, url.port);
  if (socket == SOCKET_INVALID) {
    HttpResponseSetError(response, "TCP connection failed");
    goto http_request_url_done;
  }
  if (url.secure) {
    tls = SslConnect(socket, url.host);
    if (!tls) {
      HttpResponseSetError(response, SslLastError);
      goto http_request_connection_done;
    }
  }

  if (!HttpSendBytes(socket, tls, request.data, request.length) ||
    body_length && !HttpSendBytes(socket, tls, body, body_length)) {
      if (tls)
        HttpResponseSetError(response, SslLastError);
      else
        HttpResponseSetError(response, "HTTP send failed");
      goto http_request_connection_done;
    }

  received = HttpRecvBytes(socket, tls, receive_buffer,
    sizeof(receive_buffer));
  while (received > 0) {
    if (!HttpBufferAppend(&raw, receive_buffer, received)) {
      HttpResponseSetError(response, "HTTP response exceeds limit");
      goto http_request_connection_done;
    }
    received = HttpRecvBytes(socket, tls, receive_buffer,
      sizeof(receive_buffer));
  }
  if (received < 0) {
    if (tls)
      HttpResponseSetError(response, SslLastError);
    else
      HttpResponseSetError(response, "HTTP receive failed");
    goto http_request_connection_done;
  }
  transport_ok = TRUE;

http_request_connection_done:
  SslClose(tls);
  SocketClose(socket);

  if (!transport_ok)
    goto http_request_url_done;
  header_finish = HttpFindHeaderEnd(raw.data, raw.length);
  if (header_finish < 0) {
    HttpResponseSetError(response, "malformed HTTP response headers");
    goto http_request_url_done;
  }

  response->headers_length = header_finish - 2;
  response->headers = HttpSlice(raw.data, 0, response->headers_length);
  response->status = HttpParseStatus(response->headers,
    response->headers_length);
  if (!response->status) {
    HttpResponseSetError(response, "malformed HTTP status line");
    goto http_request_url_done;
  }

  available = raw.length - header_finish;
  transfer_encoding = HttpHeaderValue(response, "Transfer-Encoding");
  content_length_text = HttpHeaderValue(response, "Content-Length");

  if (HttpValueHasToken(transfer_encoding, "chunked")) {
    decoded = HttpDecodeChunked(raw.data + header_finish, available,
      &decoded_size);
    if (!decoded) {
      HttpResponseSetError(response, "malformed chunked HTTP body");
      goto http_request_url_done;
    }
    response->body = decoded;
    response->body_length = decoded_size;
    decoded = NULL;
  } else if (content_length_text) {
    if (!HttpParseDecimal(content_length_text, &content_length) ||
      content_length > available ||
      !HttpCopyBody(response, raw.data + header_finish, content_length)) {
        HttpResponseSetError(response, "invalid or incomplete Content-Length");
        goto http_request_url_done;
      }
  } else if (!HttpCopyBody(response, raw.data + header_finish, available)) {
    HttpResponseSetError(response, "HTTP body exceeds limit");
    goto http_request_url_done;
  }

http_request_url_done:
  HttpUrlFree(&url);

http_request_done:
  Free(host_header);
  Free(transfer_encoding);
  Free(content_length_text);
  Free(decoded);
  HttpBufferFree(&request);
  HttpBufferFree(&raw);
  return response;
}

CHttpResponse *HttpGet(U8 *url, U8 *extra_headers=NULL)
{
  return HttpRequest("GET", url, extra_headers);
}

CHttpResponse *HttpPost(U8 *url, U8 *body, I64 body_length,
  U8 *content_type="application/octet-stream", U8 *extra_headers=NULL)
{
  return HttpRequest("POST", url, extra_headers, body, body_length,
    content_type);
}

#endif
