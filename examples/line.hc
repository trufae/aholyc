// A tiny REPL built on lib/line: line editing, history (Up/Down and ^R),
// and Tab completion that understands which argument the cursor is on.
// Type exit, or press ^D on an empty line, to leave.
#include "../lib/line/defaults.hc"

CLineBuf demo_line;
CLineHistoryBuf demo_history;

U0 DemoComplete(CLine *line, CStrs *text, I64 cursor, U8 *user)
{
  if (!LineCompArg(line)) {  // first word: commands
    LineCompAdd(line, "help");
    LineCompAdd(line, "hello");
    LineCompAdd(line, "history");
    LineCompAdd(line, "echo");
    LineCompAdd(line, "open");
    LineCompAdd(line, "exit");
  } else if (StrsStartsWithS(text, "open ")) {  // arguments of open: files
    LineCompAdd(line, "notes.txt");
    LineCompAdd(line, "notes.md");
    LineCompAdd(line, "todo.md");
  } else {  // anywhere else: words worth repeating
    LineCompAdd(line, "world");
    LineCompAdd(line, "wide");
  }
}

U0 Main()
{
  U8 *line;

  LineBufInit(&demo_line);
  LineHistoryBufInit(&demo_history);
  LineHistoryAttach(&demo_line, &demo_history);
  LineSetCompletion(&demo_line, &DemoComplete);
  LineHistoryLoad(&demo_history, ".line_history");
  while (TRUE) {
    line = LineRead(&demo_line, "\x1B[1;32mdemo>\x1B[0m ");
    if (!line)
      break;
    if (!StrCmp(line, "exit"))
      break;
    LineHistoryAdd(&demo_history, line);
    if (*line)
      "%s\n", line;
  }
  LineHistorySave(&demo_history, ".line_history");
  LineFini;
}

Main;
