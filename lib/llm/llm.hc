#ifndef AHOLYC_LIB_LLM_HC
#define AHOLYC_LIB_LLM_HC

// Minimal client for OpenAI-compatible Chat Completions and Responses APIs
// over lib/net/http.hc. The conversation is kept as JSON built with
// lib/json/pj.hc, so a CLlm owns everything and the caller only frees the
// strings LlmSend and LlmAsk return.
//
//   CLlm llm;
//   LlmInit(&llm, "http://127.0.0.1:11434/v1/chat/completions", "gpt-oss");
//   LlmSystem(&llm, "Answer briefly.");
//   U8 *answer = LlmAsk(&llm, "Why is the sky blue?");
//   if (answer)
//     "%s\n", answer;
//   else
//     "error: %s\n", llm.error;
//   Free(answer);
//   LlmFini(&llm);
//
// Public functions are the ones documented in README.md; helpers named
// LlmParseText, LlmSetError and LlmReset are internal.

#include "../json/query.hc"
#include "../json/pj.hc"
#include "../http/client.hc"

class CLlm
{
  U8 *url;
  U8 *model;
  Bool responses;          // Responses API: url ends with "/responses"
  U8 *headers;             // Authorization and extra request headers
  U8 *system;              // system prompt
  CPj *messages;           // history: comma separated JSON message objects
  CPj *parts;              // attachments queued for the next message
  CPj *fields;             // extra request fields: "key":value pairs
  CHttpResponse *response; // last HTTP exchange, valid until the next send
  CJsonValue json;         // decoded body of the last response
  I64 input_tokens;
  I64 output_tokens;
  U8 *error;               // NULL after a successful call
};

U0 LlmSetError(CLlm *llm, U8 *message)
{
  Free(llm->error);
  llm->error = StrNew(message);
}

U0 LlmReset(CLlm *llm)
{
  HttpResponseFree(llm->response);
  llm->response = NULL;
  MemSet(&llm->json, 0, sizeof(CJsonValue));
  llm->input_tokens = -1;
  llm->output_tokens = -1;
  Free(llm->error);
  llm->error = NULL;
}

// api_key may be NULL for local servers. headers holds optional extra
// "Name: value\r\n" lines. The Responses API is selected by the URL.
Bool LlmInit(CLlm *llm, U8 *url, U8 *model, U8 *api_key=NULL,
  U8 *headers=NULL)
{
  CStrBuf all;
  I64 length;

  MemSet(llm, 0, sizeof(CLlm));
  llm->messages = PjNew;
  llm->parts = PjNew;
  llm->fields = PjNew;
  llm->input_tokens = -1;
  llm->output_tokens = -1;
  if (!url || !*url || !model || !*model)
    return FALSE;
  llm->url = url;
  llm->model = model;
  length = StrLen(url);
  llm->responses = length >= 10 && !StrCmp(url + length - 10, "/responses");
  StrBufInit(&all);
  if (api_key && *api_key)
    StrBufPrintf(&all, "Authorization: Bearer %s\r\n", api_key);
  if (headers)
    StrBufPutS(&all, headers);
  if (StrsLen(&all))
    llm->headers = StrBufTake(&all);
  return TRUE;
}

U0 LlmFini(CLlm *llm)
{
  LlmReset(llm);
  PjFree(llm->messages);
  PjFree(llm->parts);
  PjFree(llm->fields);
  Free(llm->system);
  Free(llm->headers);
  llm->messages = NULL;
  llm->parts = NULL;
  llm->fields = NULL;
  llm->system = NULL;
  llm->headers = NULL;
}

U0 LlmSystem(CLlm *llm, U8 *prompt)
{
  Free(llm->system);
  llm->system = NULL;
  if (prompt && *prompt)
    llm->system = StrNew(prompt);
}

// Add a top-level request field, e.g. LlmSet(&llm, "temperature", "0.2") or
// a "tools" array. The value must be valid JSON text.
Bool LlmSet(CLlm *llm, U8 *key, U8 *json)
{
  if (!key || !JsonValid(json))
    return FALSE;
  PjKj(llm->fields, key, json);
  return TRUE;
}

// Attach an image (http(s) or data: URL) to the next message.
U0 LlmImage(CLlm *llm, U8 *url, U8 *detail=NULL)
{
  CPj *pj = llm->parts;

  PjO(pj);
  if (llm->responses) {
    PjKs(pj, "type", "input_image");
    PjKs(pj, "image_url", url);
  } else {
    PjKs(pj, "type", "image_url");
    PjKo(pj, "image_url");
    PjKs(pj, "url", url);
  }
  if (detail)
    PjKs(pj, "detail", detail);
  if (!llm->responses)
    PjEnd(pj);
  PjEnd(pj);
}

// Attach a document to the next message: an uploaded file id, or inline
// data (filename plus a complete data: URL, see lib/text/base64.hc).
U0 LlmFile(CLlm *llm, U8 *file_id, U8 *filename=NULL, U8 *data_url=NULL)
{
  CPj *pj = llm->parts;

  PjO(pj);
  if (llm->responses) {
    PjKs(pj, "type", "input_file");
  } else {
    PjKs(pj, "type", "file");
    PjKo(pj, "file");
  }
  if (filename && data_url) {
    PjKs(pj, "filename", filename);
    PjKs(pj, "file_data", data_url);
  } else {
    PjKs(pj, "file_id", file_id);
  }
  if (!llm->responses)
    PjEnd(pj);
  PjEnd(pj);
}

// Append a complete JSON message object, for tool results or anything the
// helpers do not cover.
Bool LlmRaw(CLlm *llm, U8 *json)
{
  if (!JsonValid(json, JSON_TYPE_OBJECT))
    return FALSE;
  PjJ(llm->messages, json);
  return TRUE;
}

// Append a message and any queued attachments to the conversation.
Bool LlmMessage(CLlm *llm, U8 *role, U8 *text)
{
  CPj *pj = llm->messages;

  if (!role || !text)
    return FALSE;
  PjO(pj);
  PjKs(pj, "role", role);
  if (StrsLen(&llm->parts->sb)) {
    PjKa(pj, "content");
    PjO(pj);
    if (llm->responses)
      PjKs(pj, "type", "input_text");
    else
      PjKs(pj, "type", "text");
    PjKs(pj, "text", text);
    PjEnd(pj);
    PjJ(pj, PjString(llm->parts));
    PjEnd(pj);
    PjReset(llm->parts);
  } else {
    PjKs(pj, "content", text);
  }
  PjEnd(pj);
  return TRUE;
}

// Build the request body. Caller frees the result.
U8 *LlmRequest(CLlm *llm)
{
  CPj *pj = PjNew;

  PjO(pj);
  PjKs(pj, "model", llm->model);
  if (llm->responses) {
    if (llm->system)
      PjKs(pj, "instructions", llm->system);
    PjKa(pj, "input");
  } else {
    PjKa(pj, "messages");
    if (llm->system) {
      PjO(pj);
      PjKs(pj, "role", "system");
      PjKs(pj, "content", llm->system);
      PjEnd(pj);
    }
  }
  PjJ(pj, PjString(llm->messages));
  PjEnd(pj);
  PjJ(pj, PjString(llm->fields));
  PjEnd(pj);
  return PjDrain(pj);
}

// Find the first text in a string, a content array, or a message object.
Bool LlmParseText(CJsonValue *value, CJsonValue *text)
{
  CJsonValue item;
  I64 i;

  if (value->type == JSON_TYPE_STRING) {
    *text = *value;
    return TRUE;
  }
  if (value->type == JSON_TYPE_ARRAY) {
    for (i = 0; JsonArrayGet(value, i, &item); i++) {
      if (LlmParseText(&item, text))
        return TRUE;
    }
    return FALSE;
  }
  if (value->type != JSON_TYPE_OBJECT)
    return FALSE;
  if (JsonObjectGet(value, "text", text) && text->type == JSON_TYPE_STRING)
    return TRUE;
  return JsonObjectGet(value, "content", &item) && LlmParseText(&item, text);
}

// Decode a response body. Returns the assistant text (caller frees) or NULL
// with llm->error set. llm->json keeps the whole document for JsonPathGet.
U8 *LlmParse(CLlm *llm, U8 *body, I64 length=-1)
{
  CJsonDecoder decoder;
  CJsonValue value;
  CJsonValue text;
  CJsonValue item;
  I64 i;

  MemSet(&llm->json, 0, sizeof(CJsonValue));
  if (body)
    JsonDecoderInit(&decoder, body, length);
  if (!body || !JsonDecode(&decoder, &llm->json) ||
    llm->json.type != JSON_TYPE_OBJECT) {
      LlmSetError(llm, "response is not a JSON object");
      return NULL;
    }
  if (JsonPathGet(&llm->json, "$.usage.prompt_tokens", &value) ||
    JsonPathGet(&llm->json, "$.usage.input_tokens", &value))
    JsonValueAsI64(&value, &llm->input_tokens);
  if (JsonPathGet(&llm->json, "$.usage.completion_tokens", &value) ||
    JsonPathGet(&llm->json, "$.usage.output_tokens", &value))
    JsonValueAsI64(&value, &llm->output_tokens);

  if (JsonPathGet(&llm->json, "$.error.message", &text) ||
    JsonPathGet(&llm->json, "$.error", &text)) {
      Free(llm->error);
      llm->error = JsonValueStringNew(&text);
      if (!llm->error)
        llm->error = StrNew("request failed");
      return NULL;
    }
  if (JsonPathGet(&llm->json, "$.choices[0].message", &value)) {
    if (LlmParseText(&value, &text))
      return JsonValueStringNew(&text);
    if (JsonObjectGet(&value, "refusal", &item) && LlmParseText(&item, &text))
      return JsonValueStringNew(&text);
  }
  if (JsonObjectGet(&llm->json, "output_text", &text) &&
    text.type == JSON_TYPE_STRING)
    return JsonValueStringNew(&text);
  if (JsonObjectGet(&llm->json, "output", &value)) {
    for (i = 0; JsonArrayGet(&value, i, &item); i++) {
      if (JsonObjectGet(&item, "type", &text) &&
        JsonValueStringEquals(&text, "message") &&
        LlmParseText(&item, &text))
        return JsonValueStringNew(&text);
    }
  }
  LlmSetError(llm, "response has no text");
  return NULL;
}

// Send the conversation. On success the reply is appended to the history
// and returned (caller frees); on failure NULL is returned and llm->error
// describes the problem. llm->response keeps the raw HTTP exchange.
U8 *LlmSend(CLlm *llm)
{
  CJsonValue value;
  U8 *request;
  U8 *reply;

  LlmReset(llm);
  request = LlmRequest(llm);
  llm->response = HttpPost(llm->url, request, StrLen(request),
    "application/json", llm->headers);
  Free(request);
  if (llm->response->error) {
    LlmSetError(llm, llm->response->error);
    return NULL;
  }
  reply = LlmParse(llm, llm->response->body, llm->response->body_length);
  if (!reply && llm->response->status >= 400 &&
    !JsonObjectGet(&llm->json, "error", &value)) {
      Free(llm->error);
      llm->error = MStrPrint("HTTP %d", llm->response->status);
    }
  if (reply)
    LlmMessage(llm, "assistant", reply);
  return reply;
}

// One user turn: LlmMessage plus LlmSend.
U8 *LlmAsk(CLlm *llm, U8 *text)
{
  if (!LlmMessage(llm, "user", text))
    return NULL;
  return LlmSend(llm);
}

#endif
