// Pseudo console backend for the terminal control on Windows 10+: ConPTY
// (CreatePseudoConsole) with %COMSPEC% (cmd.exe) attached through pipes.
// int-returning Win32 calls are narrowed with (I32).

extern I64 CreatePipe(I64 *read_end, I64 *write_end, U8 *security, U32 size);
extern I64 CreatePseudoConsole(I64 size, I64 input, I64 output, U32 flags,
  I64 *console);
extern I64 ResizePseudoConsole(I64 console, I64 size);
extern U0 ClosePseudoConsole(I64 console);
extern I64 InitializeProcThreadAttributeList(U8 *list, U32 count, U32 flags,
  I64 *size);
extern I64 UpdateProcThreadAttribute(U8 *list, U32 flags, I64 attribute,
  U8 *value, I64 size, U8 *previous, I64 *returned);
extern I64 CreateProcessA(U8 *application, U8 *command_line, U8 *pattr,
  U8 *tattr, I64 inherit, U32 flags, U8 *environment, U8 *directory,
  U8 *startup, U8 *process_information);
extern I64 PeekNamedPipe(I64 pipe, U8 *buffer, U32 size, U32 *read,
  U32 *available, U32 *left);
extern I64 ReadFile(I64 handle, U8 *buffer, U32 count, U32 *read,
  U8 *overlapped);
extern I64 WriteFile(I64 handle, U8 *data, U32 count, U32 *written,
  U8 *overlapped);
extern U32 WaitForSingleObject(U8 *handle, U32 milliseconds);  // as lib/term
extern I64 TerminateProcess(I64 handle, U32 code);
extern I64 CloseHandle(U8 *handle);

#define HTK_PTY_ATTR_PSEUDOCONSOLE 0x20016
#define HTK_PTY_EXTENDED_STARTUPINFO 0x80000

I64 HtkPtyCoord(I64 cols, I64 rows)
{
  return cols & 0xFFFF | rows << 16;  // COORD {X, Y} passed by value
}

Bool HtkPtySpawn(CHtkTerm *t, I64 cols, I64 rows)
{
  I64 in_read, in_write, out_read, out_write;
  I64 size = 0;
  U8 *shell = getenv("COMSPEC");
  U8 *list;
  U8 startup[112];      // STARTUPINFOEXA: STARTUPINFOA(104) + lpAttributeList
  U8 info[24];          // PROCESS_INFORMATION
  I64 *q;

  if (!CreatePipe(&in_read, &in_write, NULL, 0)(I32) ||
    !CreatePipe(&out_read, &out_write, NULL, 0)(I32))
    return FALSE;
  if (CreatePseudoConsole(HtkPtyCoord(cols, rows), in_read, out_write, 0,
      &t->hpc)(I32))
    return FALSE;
  CloseHandle(in_read(U8 *));
  CloseHandle(out_write(U8 *));
  InitializeProcThreadAttributeList(NULL, 1, 0, &size);
  list = MAlloc(size);
  if (!InitializeProcThreadAttributeList(list, 1, 0, &size)(I32) ||
    !UpdateProcThreadAttribute(list, 0, HTK_PTY_ATTR_PSEUDOCONSOLE, &t->hpc,
      sizeof(I64), NULL, NULL)(I32)) {
        Free(list);
        return FALSE;
      }
  MemSet(startup, 0, sizeof(startup));
  q = startup;
  q[0] = 112;           // cb
  q[13] = list;         // lpAttributeList at offset 104
  if (!shell || !*shell)
    shell = "cmd.exe";
  if (!CreateProcessA(NULL, shell, NULL, NULL, 0, HTK_PTY_EXTENDED_STARTUPINFO,
      NULL, NULL, startup, info)(I32)) {
        Free(list);
        return FALSE;
      }
  q = info;
  t->hproc = q[0];
  CloseHandle(q[1](U8 *));  // thread handle
  t->hin = in_write;
  t->hout = out_read;
  t->fd = 1;            // "open" marker for the portable code
  Free(list);
  return TRUE;
}

I64 HtkPtyRead(CHtkTerm *t, U8 *buffer, I64 capacity)
{
  U32 available = 0, got = 0;

  if (t->fd < 0 || !PeekNamedPipe(t->hout, NULL, 0, NULL, &available,
      NULL)(I32) || !available)
    return 0;
  if (available < capacity)
    capacity = available;
  if (!ReadFile(t->hout, buffer, capacity, &got, NULL)(I32))
    return 0;
  return got;
}

U0 HtkPtyWrite(CHtkTerm *t, U8 *bytes, I64 count)
{
  U32 written = 0;

  if (t->fd >= 0)
    WriteFile(t->hin, bytes, count, &written, NULL);
}

U0 HtkPtyResize(CHtkTerm *t, I64 cols, I64 rows)
{
  if (t->fd >= 0)
    ResizePseudoConsole(t->hpc, HtkPtyCoord(cols, rows));
}

Bool HtkPtyAlive(CHtkTerm *t)
{
  if (t->fd < 0)
    return FALSE;
  return WaitForSingleObject(t->hproc(U8 *), 0) != 0;  // WAIT_OBJECT_0
}

U0 HtkPtyClose(CHtkTerm *t)
{
  if (t->fd < 0)
    return;
  if (!t->exited)
    TerminateProcess(t->hproc, 0);
  ClosePseudoConsole(t->hpc);
  CloseHandle(t->hin(U8 *));
  CloseHandle(t->hout(U8 *));
  CloseHandle(t->hproc(U8 *));
  t->fd = -1;
}
