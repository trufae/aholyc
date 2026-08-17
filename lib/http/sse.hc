#ifndef AHOLYC_LIB_HTTP_SSE_HC
#define AHOLYC_LIB_HTTP_SSE_HC

// Server-Sent Events (text/event-stream) parser over an in-memory buffer,
// such as the body of a CHttpResponse. Each SseNext fills sse->event,
// sse->id and sse->data (data lines joined with '\n'); the strings are owned
// by the parser and stay valid until the next SseNext or SseFini.
//
//   CSse sse;
//   SseInit(&sse, response->body, response->body_length);
//   while (SseNext(&sse))
//     "%s: %s\n", sse.event, sse.data;
//   SseFini(&sse);
//
// Lines end with \n, \r\n or \r; ':' lines are comments; an event is
// dispatched by a blank line, or at the end of the buffer when it carries
// data (lenient towards servers that close the stream early).

#include "../text/strbuf.hc"

class CSse
{
  U8 *text;
  I64 length;
  I64 offset;
  U8 *event;   // event name, "message" when absent
  U8 *id;      // last id field or NULL
  U8 *data;    // joined data lines
};

U0 SseInit(CSse *sse, U8 *text, I64 length=-1)
{
  MemSet(sse, 0, sizeof(CSse));
  sse->text = text;
  if (text && length < 0)
    length = StrLen(text);
  if (!text)
    length = 0;
  sse->length = length;
}

U0 SseFini(CSse *sse)
{
  Free(sse->event);
  Free(sse->id);
  Free(sse->data);
  sse->event = NULL;
  sse->id = NULL;
  sse->data = NULL;
}

// Copy a field value, skipping one optional space after the colon.
U8 *SseFieldValue(U8 *line, I64 start, I64 finish)
{
  U8 *value;

  if (start < finish && line[start] == ' ')
    start++;
  value = MAlloc(finish - start + 1);
  if (finish > start)
    MemCpy(value, line + start, finish - start);
  value[finish - start] = 0;
  return value;
}

Bool SseNext(CSse *sse)
{
  CStrBuf data;
  U8 *event = NULL;
  U8 *id = NULL;
  U8 *value;
  U8 *line;
  I64 start;
  I64 finish;
  I64 colon;
  Bool have_data = FALSE;

  SseFini(sse);
  StrBufInit(&data);
  while (sse->offset < sse->length) {
    line = sse->text + sse->offset;
    finish = 0;
    while (sse->offset + finish < sse->length &&
      line[finish] != '\n' && line[finish] != '\r')
      finish++;
    start = sse->offset + finish;
    if (start < sse->length && line[finish] == '\r' &&
      start + 1 < sse->length && line[finish + 1] == '\n')
      start++;
    sse->offset = start + 1;
    if (!finish) {
      if (have_data)
        break;
      Free(event);  // a blank line without data resets the event
      event = NULL;
    } else if (line[0] != ':') {
      colon = 0;
      while (colon < finish && line[colon] != ':')
        colon++;
      if (colon < finish)
        value = SseFieldValue(line, colon + 1, finish);
      else
        value = StrNew("");  // a field without a colon has an empty value
      if (colon == 4 && !MemCmp(line, "data", 4)) {
        if (have_data)
          StrBufPutC(&data, '\n');
        StrBufPutS(&data, value);
        have_data = TRUE;
        Free(value);
      } else if (colon == 5 && !MemCmp(line, "event", 5)) {
        Free(event);
        event = value;
      } else if (colon == 2 && !MemCmp(line, "id", 2)) {
        Free(id);
        id = value;
      } else {
        Free(value);  // retry and unknown fields are ignored
      }
    }
  }
  if (!have_data) {
    Free(event);
    Free(id);
    StrBufFini(&data);
    return FALSE;
  }
  if (!event)
    event = StrNew("message");
  sse->event = event;
  sse->id = id;
  sse->data = StrBufTake(&data);
  return TRUE;
}

#endif
