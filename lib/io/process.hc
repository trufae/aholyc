#ifndef AHOLYC_LIB_IO_PROCESS_HC
#define AHOLYC_LIB_IO_PROCESS_HC

// Blocking child-process pipes backed by posix_spawn or CreateProcess.
// Commands run through the platform shell and inherit the parent's stderr.

#define PROCESS_INVALID -1

class CProcess
{
  I64 pid;       // POSIX process ID
  U8 *handle;    // Windows process handle
  I64 input;     // writable stdin or PROCESS_INVALID
  I64 output;    // readable stdout or PROCESS_INVALID
  I64 exit_code; // set by ProcessClose; -1 if unknown
};

#ifdef IS_WINDOWS

#define PROCESS_STARTF_USESTDHANDLES 0x100
#define PROCESS_HANDLE_FLAG_INHERIT  1
#define PROCESS_STD_ERROR_HANDLE     -12
#define PROCESS_INFINITE             0xFFFFFFFF
#define PROCESS_WAIT_OBJECT_0        0
#define PROCESS_MAX_IO_SIZE          0x7FFFFFFF
#define PROCESS_SHELL_CAPACITY       32768

// Minimal Win64 layouts; explicit cursors preserve SDK offsets and sizes.
class CProcessSecurityAttributes
{
  U32 length;
  $$ = 16;
  I32 inherit;
  $$ = 24;
};

class CProcessStartupInfoA
{
  U32 cb;
  $$ = 60;
  U32 flags;
  $$ = 80;
  U8 *std_input;
  U8 *std_output;
  U8 *std_error;
};

class CProcessInformation
{
  U8 *process;
  U8 *thread;
  $$ = 24;
};

extern I64 CreatePipe(U8 **read_end, U8 **write_end,
  CProcessSecurityAttributes *attributes, U32 size);
extern I64 SetHandleInformation(U8 *handle, U32 mask, U32 flags);
extern U8 *GetStdHandle(I64 which);
extern I64 CreateProcessA(U8 *application_name, U8 *command_line,
  U0 *process_attributes, U0 *thread_attributes,
  I64 inherit_handles, I64 creation_flags,
  U0 *environment, U8 *current_directory,
  CProcessStartupInfoA *startup_info,
  CProcessInformation *process_information);
extern I64 ReadFile(U8 *handle, U8 *data, U32 size, U32 *read, U0 *overlapped);
extern I64 WriteFile(U8 *handle, U8 *data, U32 size, U32 *written,
  U8 *overlapped);
extern U32 WaitForSingleObject(U8 *handle, U32 milliseconds);
extern I64 TerminateProcess(U8 *handle, U32 exit_code);
extern I64 GetExitCodeProcess(U8 *process, U32 *exit_code);
_extern CloseHandle I64 ProcessWinCloseHandle(U8 *handle);
extern I64 GetEnvironmentVariableA(U8 *name, U8 *value, U32 size);

Bool ProcessNativeOpen(CProcess *process, U8 *command)
{
  CProcessSecurityAttributes attributes;
  CProcessStartupInfoA startup;
  CProcessInformation information;
  U8 *child_input = NULL, *child_output = NULL;
  U8 *our_input = NULL, *our_output = NULL;

  MemSet(&attributes, 0, sizeof(CProcessSecurityAttributes));
  attributes.length = sizeof(CProcessSecurityAttributes);
  attributes.inherit = TRUE;
  if (!CreatePipe(&child_input, &our_input, &attributes, 0)(I32))
    return FALSE;
  if (!CreatePipe(&our_output, &child_output, &attributes, 0)(I32)) {
    ProcessWinCloseHandle(child_input);
    ProcessWinCloseHandle(our_input);
    return FALSE;
  }
  SetHandleInformation(our_input, PROCESS_HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(our_output, PROCESS_HANDLE_FLAG_INHERIT, 0);

  MemSet(&startup, 0, sizeof(CProcessStartupInfoA));
  startup.cb = sizeof(CProcessStartupInfoA);
  startup.flags = PROCESS_STARTF_USESTDHANDLES;
  startup.std_input = child_input;
  startup.std_output = child_output;
  startup.std_error = GetStdHandle(PROCESS_STD_ERROR_HANDLE);
  MemSet(&information, 0, sizeof(CProcessInformation));

  U8 *shell = MAlloc(PROCESS_SHELL_CAPACITY);
  U32 length = GetEnvironmentVariableA("COMSPEC", shell,
    PROCESS_SHELL_CAPACITY)(U32);
  if (!length || length >= PROCESS_SHELL_CAPACITY)
    StrCpy(shell, "cmd.exe");
  U8 *command_line = MStrPrint("cmd.exe /D /S /C \"%s\"", command);
  Bool ok = CreateProcessA(shell, command_line, NULL, NULL, TRUE, 0, NULL,
    NULL, &startup, &information)(I32) != 0;
  Free(command_line);
  Free(shell);
  ProcessWinCloseHandle(child_input);
  ProcessWinCloseHandle(child_output);
  if (!ok) {
    ProcessWinCloseHandle(our_input);
    ProcessWinCloseHandle(our_output);
    return FALSE;
  }
  ProcessWinCloseHandle(information.thread);
  process->handle = information.process;
  process->input = our_input(I64);
  process->output = our_output(I64);
  return TRUE;
}

I64 ProcessNativeRead(CProcess *process, U8 *data, I64 capacity)
{
  U32 read = 0;

  if (capacity > PROCESS_MAX_IO_SIZE)
    capacity = PROCESS_MAX_IO_SIZE;
  if (!ReadFile(process->output(U8 *), data, capacity, &read, NULL)(I32))
    return 0;  // broken pipe: the child exited
  return read;
}

I64 ProcessNativeWrite(CProcess *process, U8 *data, I64 size)
{
  U32 written = 0;

  if (size > PROCESS_MAX_IO_SIZE)
    size = PROCESS_MAX_IO_SIZE;
  if (!WriteFile(process->input(U8 *), data, size, &written, NULL)(I32))
    return -1;
  return written;
}

U0 ProcessNativeCloseHandle(I64 handle)
{
  ProcessWinCloseHandle(handle(U8 *));
}

I64 ProcessNativeWait(CProcess *process, I64 timeout_ms)
{
  U32 code = 0;

  if (WaitForSingleObject(process->handle, timeout_ms) != PROCESS_WAIT_OBJECT_0)
    return -1;
  if (!GetExitCodeProcess(process->handle, &code)(I32))
    return -1;
  return code;
}

// Windows terminates only the shell; descendants may survive.
U0 ProcessNativeTerminate(CProcess *process, Bool force)
{
  TerminateProcess(process->handle, 1);
  if (force)
    WaitForSingleObject(process->handle, PROCESS_INFINITE);
}

U0 ProcessNativeRelease(CProcess *process)
{
  ProcessWinCloseHandle(process->handle);
  process->handle = NULL;
}

#else
#ifdef IS_UNIX

#define PROCESS_SIGPIPE  13
#define PROCESS_SIGTERM  15
#define PROCESS_SIGKILL  9
#define PROCESS_SIG_IGN  1
#define PROCESS_WNOHANG  1
#define PROCESS_SPAWN_SETPGROUP 2

extern U8 **environ;
extern I64 pipe(I32 *fds);
// Match the shared POSIX declarations in the socket and terminal libraries.
extern I64 close(I64 fd);
extern I64 read(I64 fd, U8 *buffer, I64 count);
extern I64 write(I64 fd, U8 *buffer, I64 count);
extern I64 waitpid(I32 pid, I32 *status, I32 options);
extern I64 kill(I32 pid, I32 signal_number);
extern U8 *signal(I64 number, U8 *handler);
extern I64 usleep(U32 microseconds);
extern I64 posix_spawn(I32 *pid, U8 *path, U0 *file_actions, U0 *attributes,
  U8 **argv, U8 **envp);
extern I64 posix_spawn_file_actions_init(U0 *file_actions);
extern I64 posix_spawn_file_actions_destroy(U0 *file_actions);
extern I64 posix_spawn_file_actions_adddup2(U0 *file_actions, I32 fd,
  I32 new_fd);
extern I64 posix_spawn_file_actions_addclose(U0 *file_actions, I32 fd);
extern I64 posix_spawnattr_init(U0 *attributes);
extern I64 posix_spawnattr_destroy(U0 *attributes);
extern I64 posix_spawnattr_setflags(U0 *attributes, I16 flags);
extern I64 posix_spawnattr_setpgroup(U0 *attributes, I32 pgroup);

Bool ProcessNativeOpen(CProcess *process, U8 *command)
{
  U64 file_actions[32];  // posix_spawn_file_actions_t is <= 80 bytes everywhere
  U64 attributes[64];    // posix_spawnattr_t is <= 336 bytes everywhere
  I32 to_child[2], from_child[2];
  I32 pid = 0;
  U8 *shell_argv[4] = { "sh", "-c", command, NULL };

  if (pipe(to_child)(I32))
    return FALSE;
  if (pipe(from_child)(I32)) {
    close(to_child[0]);
    close(to_child[1]);
    return FALSE;
  }
  signal(PROCESS_SIGPIPE, PROCESS_SIG_IGN(U8 *));

  // Use a process group so shutdown reaches the shell and its descendants.
  posix_spawnattr_init(attributes);
  posix_spawnattr_setflags(attributes, PROCESS_SPAWN_SETPGROUP);
  posix_spawnattr_setpgroup(attributes, 0);
  posix_spawn_file_actions_init(file_actions);
  posix_spawn_file_actions_adddup2(file_actions, to_child[0], 0);
  posix_spawn_file_actions_adddup2(file_actions, from_child[1], 1);
  posix_spawn_file_actions_addclose(file_actions, to_child[0]);
  posix_spawn_file_actions_addclose(file_actions, to_child[1]);
  posix_spawn_file_actions_addclose(file_actions, from_child[0]);
  posix_spawn_file_actions_addclose(file_actions, from_child[1]);
  Bool ok = !posix_spawn(&pid, "/bin/sh", file_actions, attributes,
    shell_argv, environ)(I32);
  posix_spawn_file_actions_destroy(file_actions);
  posix_spawnattr_destroy(attributes);

  close(to_child[0]);
  close(from_child[1]);
  if (!ok) {
    close(to_child[1]);
    close(from_child[0]);
    return FALSE;
  }
  process->pid = pid;
  process->input = to_child[1];
  process->output = from_child[0];
  return TRUE;
}

I64 ProcessNativeRead(CProcess *process, U8 *data, I64 capacity)
{
  return read(process->output, data, capacity);
}

I64 ProcessNativeWrite(CProcess *process, U8 *data, I64 size)
{
  return write(process->input, data, size);
}

U0 ProcessNativeCloseHandle(I64 handle)
{
  close(handle);
}

// Decode a wait status into an exit code like System() does.
I64 ProcessNativeExitCode(I32 status)
{
  if (!(status & 0x7F))
    return status >> 8 & 0xFF;
  if ((status & 0x7F) != 0x7F)
    return 128 + (status & 0x7F);
  return -1;
}

I64 ProcessNativeWait(CProcess *process, I64 timeout_ms)
{
  I32 status = 0;
  I64 waited = 0;

  while (TRUE) {
    I64 result = waitpid(process->pid, &status, PROCESS_WNOHANG)(I32);
    if (result == process->pid)
      return ProcessNativeExitCode(status);
    if (result < 0 || waited >= timeout_ms)
      return -1;
    usleep(10000);
    waited += 10;
  }
}

U0 ProcessNativeTerminate(CProcess *process, Bool force)
{
  if (force) {
    I32 status = 0;
    kill(-process->pid, PROCESS_SIGKILL);
    waitpid(process->pid, &status, 0);
  } else {
    kill(-process->pid, PROCESS_SIGTERM);
  }
}

U0 ProcessNativeRelease(CProcess *process)
{
  process->pid = 0;
}

#else
#error lib/io/process supports Linux, macOS, and Windows native targets
#endif
#endif

// Start a shell command with piped stdin and stdout.
Bool ProcessOpen(CProcess *process, U8 *command)
{
  MemSet(process, 0, sizeof(CProcess));
  process->input = PROCESS_INVALID;
  process->output = PROCESS_INVALID;
  process->exit_code = -1;
  return command && *command && ProcessNativeOpen(process, command);
}

// Write all of size bytes to the child's stdin.
Bool ProcessWrite(CProcess *process, U8 *data, I64 size)
{
  if (process->input == PROCESS_INVALID || size < 0 || size && !data)
    return FALSE;
  while (size > 0) {
    I64 written = ProcessNativeWrite(process, data, size);
    if (written <= 0)
      return FALSE;
    data += written;
    size -= written;
  }
  return TRUE;
}

// Blocking read from the child's stdout: bytes read, 0 at EOF, -1 on error.
I64 ProcessRead(CProcess *process, U8 *data, I64 capacity)
{
  if (process->output == PROCESS_INVALID || capacity <= 0 || !data)
    return -1;
  return ProcessNativeRead(process, data, capacity);
}

// Close the child's stdin so it sees EOF; reading may continue.
U0 ProcessCloseInput(CProcess *process)
{
  if (process->input != PROCESS_INVALID)
    ProcessNativeCloseHandle(process->input);
  process->input = PROCESS_INVALID;
}

// Close pipes, then wait, terminate, and finally kill on timeout.
I64 ProcessClose(CProcess *process, I64 timeout_ms=2000)
{
  ProcessCloseInput(process);
  if (process->output != PROCESS_INVALID)
    ProcessNativeCloseHandle(process->output);
  process->output = PROCESS_INVALID;
  if (process->pid || process->handle) {
    process->exit_code = ProcessNativeWait(process, timeout_ms);
    if (process->exit_code < 0) {
      ProcessNativeTerminate(process, FALSE);
      process->exit_code = ProcessNativeWait(process, timeout_ms);
    }
    if (process->exit_code < 0)
      ProcessNativeTerminate(process, TRUE);
    ProcessNativeRelease(process);
  }
  return process->exit_code;
}

#endif
