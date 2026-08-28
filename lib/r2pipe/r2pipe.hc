#ifndef AHOLYC_LIB_R2PIPE_HC
#define AHOLYC_LIB_R2PIPE_HC

// Blocking radare2 client for spawned r2, R2PIPE_IN/R2PIPE_OUT, and r2web.
// Command replies belong to CR2Pipe and are replaced by the next command.

// Set any of these to 0 before including this file to omit that transport or
// JSON support (and its transitive library dependencies). All features are on
// by default for backwards-compatible convenience.
#ifndef R2PIPE_USE_SPAWN
#define R2PIPE_USE_SPAWN 1
#endif
#ifndef R2PIPE_USE_FDS
#define R2PIPE_USE_FDS 1
#endif
#ifndef R2PIPE_USE_HTTP
#define R2PIPE_USE_HTTP 1
#endif
#ifndef R2PIPE_USE_JSON
#define R2PIPE_USE_JSON 1
#endif

#include "../text/strbuf.hc"
#if R2PIPE_USE_SPAWN
#include "../io/process.hc"
#endif
#if R2PIPE_USE_FDS
#include "../io/env.hc"
#endif
#if R2PIPE_USE_HTTP
#include "../http/client.hc"
#endif
#if R2PIPE_USE_JSON
#include "../json/decode.hc"
#include "../json/encode.hc"
#endif

#define R2PIPE_NONE 0
#define R2PIPE_SPAWN 1
#define R2PIPE_FDS 2
#define R2PIPE_HTTP 3

class CR2Pipe
{
  I64 transport;
  #if R2PIPE_USE_SPAWN
  CProcess process;
  #endif
  #if R2PIPE_USE_FDS
  I64 input; // readable response FD, borrowed
  I64 output; // writable command FD, borrowed
  #endif
  #if R2PIPE_USE_HTTP
  U8 *url;
  #endif
  U8 *text;
  I64 text_length;
  #if R2PIPE_USE_JSON
  CJsonValue json;
  #endif
  U8 *error;
};

U0 R2PipeSetError(CR2Pipe *r2, U8 *error)
{
  Free(r2->error);
  r2->error = StrNew(error);
}

U0 R2PipeReset(CR2Pipe *r2)
{
  Free(r2->text);
  r2->text = NULL;
  r2->text_length = 0;
  #if R2PIPE_USE_JSON
  MemSet(&r2->json, 0, sizeof(CJsonValue));
  #endif
  Free(r2->error);
  r2->error = NULL;
}

U0 R2PipeInit(CR2Pipe *r2)
{
  MemSet(r2, 0, sizeof(CR2Pipe));
  #if R2PIPE_USE_FDS
  r2->input = -1;
  r2->output = -1;
  #endif
}

#if R2PIPE_USE_HTTP
Bool R2PipeHttp(U8 *target)
{
  return HttpStartsWithInsensitive(target, "http://") ||
    HttpStartsWithInsensitive(target, "https://");
}
#endif

#if R2PIPE_USE_SPAWN
// A complete command is available through R2PipeSpawn when custom r2 flags
// are needed. Open only quotes one file/URI argument.
U8 *R2PipeQuote(U8 *text)
{
  CStrBuf buffer;
  U8 *p;

  if (!text)
    return NULL;
  #ifdef IS_WINDOWS
  return MStrPrint("\"%s\"", text);
  #else
  StrBufInit(&buffer);
  StrBufPutC(&buffer, '\'');
  for (p = text; *p; p++) {
    if (*p == '\'')
      StrBufPutS(&buffer, "'\\\"'\\\"'");
    else
      StrBufPutC(&buffer, *p);
  }
  StrBufPutC(&buffer, '\'');
  return StrBufTake(&buffer);
  #endif
}

Bool R2PipeSpawn(CR2Pipe *r2, U8 *command)
{
  U8 hello;

  R2PipeInit(r2);
  if (!command || !*command || !ProcessOpen(&r2->process, command)) {
    R2PipeSetError(r2, "cannot spawn radare2");
    return FALSE;
  }
  r2->transport = R2PIPE_SPAWN;
  if (ProcessRead(&r2->process, &hello, 1) != 1 || hello) {
    R2PipeSetError(r2, "radare2 did not start an r2pipe session");
    ProcessClose(&r2->process);
    return FALSE;
  }
  return TRUE;
}
#endif

Bool R2PipeOpen(CR2Pipe *r2, U8 *target=NULL)
{
  #if R2PIPE_USE_SPAWN
  U8 *quoted, *command;
  Bool ok;
  #endif

  R2PipeInit(r2);
  #if R2PIPE_USE_HTTP
  if (target && R2PipeHttp(target)) {
    r2->transport = R2PIPE_HTTP;
    r2->url = StrNew(target);
    return TRUE;
  }
  #endif
  #if R2PIPE_USE_SPAWN
  if (!target)
    target = "-";
  quoted = R2PipeQuote(target);
  command = MStrPrint("radare2 -q0 %s", quoted);
  Free(quoted);
  ok = R2PipeSpawn(r2, command);
  Free(command);
  return ok;
  #else
  R2PipeSetError(r2, "r2pipe spawn support is disabled");
  return FALSE;
  #endif
}

#if R2PIPE_USE_FDS
#ifdef IS_UNIX
extern I64 read(I64 fd, U8 *buffer, I64 count);
extern I64 write(I64 fd, U8 *buffer, I64 count);
Bool R2PipeFdNumber(U8 *text, I64 *result)
{
  I64 value = 0;

  if (!text || !*text || !result)
    return FALSE;
  while (*text) {
    if (*text < '0' || *text > '9' || value > (I64_MAX - 9) / 10)
      return FALSE;
    value = value * 10 + *text++ - '0';
  }
  *result = value;
  return TRUE;
}

Bool R2PipeOpenFds(CR2Pipe *r2, I64 input, I64 output)
{
  R2PipeInit(r2);
  if (input < 0 || output < 0) {
    R2PipeSetError(r2, "invalid r2pipe file descriptor");
    return FALSE;
  }
  r2->transport = R2PIPE_FDS;
  r2->input = input;
  r2->output = output;
  return TRUE;
}

Bool R2PipeOpenEnv(CR2Pipe *r2)
{
  U8 *in = EnvGet("R2PIPE_IN");
  U8 *out = EnvGet("R2PIPE_OUT");
  I64 input, output;
  Bool ok = R2PipeFdNumber(in, &input) && R2PipeFdNumber(out, &output) &&
    R2PipeOpenFds(r2, input, output);

  Free(in);
  Free(out);
  if (!ok) {
    R2PipeInit(r2);
    R2PipeSetError(r2, "R2PIPE_IN and R2PIPE_OUT are required");
  }
  return ok;
}
#else
Bool R2PipeOpenFds(CR2Pipe *r2, I64 input, I64 output)
{
  R2PipeInit(r2);
  R2PipeSetError(r2, "r2pipe file descriptors require Unix");
  return FALSE;
}

Bool R2PipeOpenEnv(CR2Pipe *r2)
{
  return R2PipeOpenFds(r2, -1, -1);
}
#endif
#endif

Bool R2PipeRead(CR2Pipe *r2)
{
  CStrBuf reply;
  U8 bytes[4096];
  I64 size, i;

  StrBufInit(&reply);
  while (TRUE) {
    size = -1;
    #if R2PIPE_USE_SPAWN
    if (r2->transport == R2PIPE_SPAWN)
      size = ProcessRead(&r2->process, bytes, sizeof(bytes));
    #endif
    #if R2PIPE_USE_FDS && defined(IS_UNIX)
    if (r2->transport == R2PIPE_FDS)
      size = read(r2->input, bytes, sizeof(bytes));
    #endif
    if (size <= 0) {
      StrBufFini(&reply);
      R2PipeSetError(r2, "r2pipe read failed");
      return FALSE;
    }
    for (i = 0; i < size && bytes[i]; i++)
      ;
    if (!StrBufPutN(&reply, bytes, i)) {
      StrBufFini(&reply);
      R2PipeSetError(r2, "r2pipe response is too large");
      return FALSE;
    }
    if (i != size) {
      r2->text = StrBufTake(&reply, &r2->text_length);
      if (!r2->text)
        R2PipeSetError(r2, "out of memory");
      return r2->text != NULL;
    }
  }
}

Bool R2PipeWrite(CR2Pipe *r2, U8 *command)
{
  I64 size, written;

  if (!command || !*command)
    return FALSE;
  size = StrLen(command);
  #if R2PIPE_USE_SPAWN
  if (r2->transport == R2PIPE_SPAWN)
    return ProcessWrite(&r2->process, command, size) &&
      ProcessWrite(&r2->process, "\n", 1);
  #endif
  #if R2PIPE_USE_FDS && defined(IS_UNIX)
  if (r2->transport == R2PIPE_FDS) {
    while (size > 0) {
      written = write(r2->output, command, size);
      if (written <= 0)
        return FALSE;
      command += written;
      size -= written;
    }
    return TRUE;
  }
  #endif
  return FALSE;
}

#if R2PIPE_USE_HTTP
Bool R2PipeHttpCmd(CR2Pipe *r2, U8 *command)
{
  U8 *url;
  CHttpResponse *response;
  I64 length;

  length = StrLen(r2->url);
  if (r2->url[length - 1] == '/')
    url = MStrPrint("%scmd", r2->url);
  else
    url = MStrPrint("%s/cmd", r2->url);
  response = HttpPost(url, command, StrLen(command), "text/plain");
  Free(url);
  if (response->error) {
    R2PipeSetError(r2, response->error);
    HttpResponseFree(response);
    return FALSE;
  }
  if (response->status < 200 || response->status >= 300) {
    R2PipeSetError(r2, "r2 HTTP command failed");
    HttpResponseFree(response);
    return FALSE;
  }
  r2->text = MAlloc(response->body_length + 1);
  if (!r2->text) {
    R2PipeSetError(r2, "out of memory");
    HttpResponseFree(response);
    return FALSE;
  }
  MemCpy(r2->text, response->body, response->body_length);
  r2->text[response->body_length] = 0;
  r2->text_length = response->body_length;
  HttpResponseFree(response);
  return TRUE;
}
#endif

U8 *R2PipeCmd(CR2Pipe *r2, U8 *command)
{
  if (!r2)
    return NULL;
  R2PipeReset(r2);
  #if R2PIPE_USE_HTTP
  if (r2->transport == R2PIPE_HTTP) {
    if (!R2PipeHttpCmd(r2, command))
      return NULL;
  } else
  #endif
  if (!R2PipeWrite(r2, command) || !R2PipeRead(r2)) {
    if (!r2->error)
      R2PipeSetError(r2, "r2pipe write failed");
    return NULL;
  }
  return r2->text;
}

#if R2PIPE_USE_JSON
Bool R2PipeCmdJ(CR2Pipe *r2, U8 *command)
{
  CJsonDecoder decoder;

  if (!R2PipeCmd(r2, command))
    return FALSE;
  JsonDecoderInit(&decoder, r2->text, r2->text_length);
  if (!JsonDecode(&decoder, &r2->json)) {
    R2PipeSetError(r2, "r2 command did not return valid JSON");
    return FALSE;
  }
  return TRUE;
}

// r2pipe2 is carried by r2's quote command. Call takes a complete request.
U8 *R2PipeCall(CR2Pipe *r2, U8 *request)
{
  U8 *command;
  U8 *result;

  if (!request)
    return NULL;
  command = MStrPrint("'%s", request);
  result = R2PipeCmd(r2, command);
  Free(command);
  return result;
}

Bool R2PipeCallJ(CR2Pipe *r2, U8 *request)
{
  U8 *command;
  Bool ok;

  if (!request)
    return FALSE;
  command = MStrPrint("'%s", request);
  ok = R2PipeCmdJ(r2, command);
  Free(command);
  return ok;
}

U8 *R2PipeCmd2Request(U8 *command, Bool json)
{
  CJsonEncoder encoder;
  U8 *request;

  if (!command)
    return NULL;
  JsonEncoderInit(&encoder, NULL);
  JsonEncodeObjectStart(&encoder);
  JsonEncodeKey(&encoder, "cmd");
  JsonEncodeString(&encoder, command);
  if (json) {
    JsonEncodeKey(&encoder, "json");
    JsonEncodeBool(&encoder, TRUE);
  }
  JsonEncodeObjectEnd(&encoder);
  JsonEncoderFinish(&encoder);
  request = MAlloc(encoder.length + 1);
  if (!request)
    return NULL;
  JsonEncoderInit(&encoder, request, encoder.length + 1);
  JsonEncodeObjectStart(&encoder);
  JsonEncodeKey(&encoder, "cmd");
  JsonEncodeString(&encoder, command);
  if (json) {
    JsonEncodeKey(&encoder, "json");
    JsonEncodeBool(&encoder, TRUE);
  }
  JsonEncodeObjectEnd(&encoder);
  if (JsonEncoderFinish(&encoder) < 0) {
    Free(request);
    return NULL;
  }
  return request;
}

U8 *R2PipeCmd2(CR2Pipe *r2, U8 *command)
{
  U8 *request = R2PipeCmd2Request(command, FALSE);
  U8 *result = R2PipeCall(r2, request);
  Free(request);
  return result;
}

Bool R2PipeCmd2J(CR2Pipe *r2, U8 *command)
{
  U8 *request = R2PipeCmd2Request(command, TRUE);
  Bool ok = R2PipeCallJ(r2, request);
  Free(request);
  return ok;
}
#endif

U0 R2PipeClose(CR2Pipe *r2)
{
  if (!r2)
    return;
  #if R2PIPE_USE_SPAWN
  if (r2->transport == R2PIPE_SPAWN)
    ProcessClose(&r2->process);
  #endif
  #if R2PIPE_USE_HTTP
  Free(r2->url);
  #endif
  R2PipeReset(r2);
  R2PipeInit(r2);
}

#endif
