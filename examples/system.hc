// A hosted System() implemented without libc's system().
//
// aholyc's preprocessor does not import the C compiler's predefined macros,
// so pass -D_WIN32 when building this example for Windows.  Linux and macOS
// use the POSIX path by default.

#ifdef _WIN32

#define SYSTEM_INFINITE    0xFFFFFFFF
#define SYSTEM_WAIT_FAILED 0xFFFFFFFF

// Win64 STARTUPINFOA layout.  HolyC classes are packed, so the explicit
// cursor moves reproduce the padding in the Windows SDK structure.
class CSystemStartupInfoA
{
  U32 cb;
  $$ = 8;
  U8 *lp_reserved;
  U8 *lp_desktop;
  U8 *lp_title;
  U32 x;
  U32 y;
  U32 x_size;
  U32 y_size;
  U32 x_count_chars;
  U32 y_count_chars;
  U32 fill_attribute;
  U32 flags;
  U16 show_window;
  U16 cb_reserved2;
  $$ = 72;
  U8 *lp_reserved2;
  U8 *std_input;
  U8 *std_output;
  U8 *std_error;
};

class CSystemProcessInformation
{
  U8 *process;
  U8 *thread;
  U32 process_id;
  U32 thread_id;
};

extern I64 CreateProcessA(U8 *application_name, U8 *command_line,
  U0 *process_attributes, U0 *thread_attributes,
  I64 inherit_handles, I64 creation_flags,
  U0 *environment, U8 *current_directory,
  CSystemStartupInfoA *startup_info,
  CSystemProcessInformation *process_information);
extern I64 WaitForSingleObject(U8 *handle, U32 milliseconds);
extern I64 GetExitCodeProcess(U8 *process, U32 *exit_code);
extern I64 CloseHandle(U8 *handle);
extern I64 GetEnvironmentVariableA(U8 *name, U8 *value, U32 size);

public I64 System(U8 *command)
{
  CSystemStartupInfoA startup;
  CSystemProcessInformation process;
  U8 *shell, *command_line;
  U32 length, wait_result, exit_code = 0;
  U32 ok;

  if (!command)
    return -1;

  // CreateProcess does not run shell syntax itself.  Run the command through
  // COMSPEC so pipes, redirections, &&, and built-in commands keep working.
  shell = MAlloc(32768);
  length = GetEnvironmentVariableA("COMSPEC", shell, 32768);
  if (!length || length >= 32768)
    StrCpy(shell, "cmd.exe");
  command_line = MStrPrint("cmd.exe /D /S /C %s", command);

  startup.cb = sizeof(CSystemStartupInfoA);
  ok = CreateProcessA(shell, command_line, NULL, NULL, TRUE, 0, NULL, NULL,
    &startup, &process);
  Free(command_line);
  Free(shell);
  if (!ok)
    return -1;

  wait_result = WaitForSingleObject(process.process, SYSTEM_INFINITE);
  ok = wait_result != SYSTEM_WAIT_FAILED &&
    GetExitCodeProcess(process.process, &exit_code);
  CloseHandle(process.thread);
  CloseHandle(process.process);
  if (!ok)
    return -1;
  return exit_code;
}

#else

extern U8 **environ;
extern I64 posix_spawn(I32 *pid, U8 *path, U0 *file_actions, U0 *attributes,
  U8 **argv, U8 **envp);
extern I64 waitpid(I32 pid, I32 *status, I32 options);

public I64 System(U8 *command)
{
  U8 *shell_argv[4];
  I32 pid = 0, status = 0;
  I32 result;

  if (!command)
    return -1;

  shell_argv[0] = "sh";
  shell_argv[1] = "-c";
  shell_argv[2] = command;
  shell_argv[3] = NULL;

  result = posix_spawn(&pid, "/bin/sh", NULL, NULL, shell_argv, environ);
  if (result)
    return -1;
  result = waitpid(pid, &status, 0);
  if (result < 0)
    return -1;

  // Return the shell's exit code instead of exposing waitpid's encoded word.
  if (!(status & 0x7F))
    return status >> 8 & 0xFF;
  if ((status & 0x7F) != 0x7F)
    return 128 + (status & 0x7F);
  return -1;
}

#endif

System("uname -a");
