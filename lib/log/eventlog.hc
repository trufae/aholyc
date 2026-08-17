// Windows Event Log system backend.  Messages are reported through
// RegisterEventSourceA/ReportEventA under the LogInit name (they land in
// the Application log; without a registered message file the viewer shows
// the raw text, which is what we want) and mirrored to OutputDebugStringA
// so an attached debugger sees them too.
//
// Levels map to event types: FATAL, CRITICAL and ERROR -> ERROR,
// WARN -> WARNING, INFO, DEBUG and TRACE -> INFORMATION.
// @ldflags=-ladvapi32

extern U8 *RegisterEventSourceA(U8 *server, U8 *source);
extern I64 ReportEventA(U8 *source, U16 type, U16 category, U32 event_id,
  U8 *sid, U16 count, U32 data_size, U8 **strings, U8 *data);
extern I64 DeregisterEventSource(U8 *source);
extern U0 OutputDebugStringA(U8 *text);

#define LOG_EVENT_ERROR       1
#define LOG_EVENT_WARNING     2
#define LOG_EVENT_INFORMATION 4

I64 log_event_type[LOG_LEVELS] = { 1, 1, 1, 2, 4, 4, 4 };
U8 *log_event_source;

Bool LogNativeOpen(U8 *name)
{
  log_event_source = RegisterEventSourceA(NULL, name);
  return TRUE;
}

U0 LogNativeWrite(I64 level, U8 *msg)
{
  U8 *strings[1];
  U8 *line = MStrPrint("%s: %s\n", log_level_names[level], msg);

  OutputDebugStringA(line);
  Free(line);
  if (log_event_source) {
    strings[0] = msg;
    ReportEventA(log_event_source, log_event_type[level], 0, 0, NULL, 1, 0,
      strings, NULL);
  }
}

U0 LogNativeClose()
{
  if (log_event_source)
    DeregisterEventSource(log_event_source);
  log_event_source = NULL;
}
