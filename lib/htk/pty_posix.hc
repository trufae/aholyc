// Pseudo terminal backend for the terminal control on Unix: posix_openpt,
// a forked $SHELL on the slave side, non-blocking reads on the master.

extern I64 posix_openpt(I64 flags);
extern I64 grantpt(I64 fd);
extern I64 unlockpt(I64 fd);
extern U8 *ptsname(I64 fd);
// open and fcntl are variadic in libc: on arm64 Darwin variadic arguments
// travel on the stack, so a fixed prototype loses the third one.
extern I64 open(U8 *path, I64 flags, ...);
extern I64 close(I64 fd);
extern I64 fork();
extern I64 setsid();
extern I64 dup2(I64 from, I64 to);
extern I64 execv(U8 *path, U8 **argv);
extern I64 waitpid(I64 pid, I64 *status, I64 options);
extern I64 kill(I64 pid, I64 signal);
extern I64 fcntl(I64 fd, I64 command, ...);
extern I64 setenv(U8 *name, U8 *value, I64 overwrite);
extern U0 _exit(I64 code);

#ifdef IS_MACOS
#define HTK_PTY_O_NOCTTY   0x20000
#define HTK_PTY_O_NONBLOCK 4
#define HTK_PTY_TIOCSCTTY  0x20007461
#define HTK_PTY_TIOCSWINSZ 0x80087467
#else
#define HTK_PTY_O_NOCTTY   0x100
#define HTK_PTY_O_NONBLOCK 0x800
#define HTK_PTY_TIOCSCTTY  0x540E
#define HTK_PTY_TIOCSWINSZ 0x5414
#endif
#define HTK_PTY_O_RDWR   2
#define HTK_PTY_F_GETFL  3
#define HTK_PTY_F_SETFL  4
#define HTK_PTY_WNOHANG  1
#define HTK_PTY_SIGHUP   1

Bool HtkPtySpawn(CHtkTerm *t, I64 cols, I64 rows)
{
  U8 *shell = getenv("SHELL");
  U8 *argv[2];
  I64 master = posix_openpt(HTK_PTY_O_RDWR | HTK_PTY_O_NOCTTY)(I32);
  I64 slave, pid;

  if (master < 0)
    return FALSE;
  if (grantpt(master)(I32) || unlockpt(master)(I32))
    return FALSE;
  slave = open(ptsname(master), HTK_PTY_O_RDWR, 0)(I32);
  if (slave < 0)
    return FALSE;
  if (!shell || !*shell)
    shell = "/bin/sh";
  pid = fork()(I32);
  if (pid < 0)
    return FALSE;
  if (!pid) {  // child: new session on the slave, then the shell
    close(master);
    setsid;
    ioctl(slave, HTK_PTY_TIOCSCTTY, NULL);
    dup2(slave, 0);
    dup2(slave, 1);
    dup2(slave, 2);
    if (slave > 2)
      close(slave);
    setenv("TERM", "xterm-256color", 1);
    argv[0] = shell;
    argv[1] = NULL;
    execv(shell, argv);
    _exit(127);
  }
  close(slave);
  fcntl(master, HTK_PTY_F_SETFL,
    fcntl(master, HTK_PTY_F_GETFL, 0)(I32) | HTK_PTY_O_NONBLOCK);
  t->fd = master;
  t->pid = pid;
  HtkPtyResize(t, cols, rows);
  return TRUE;
}

// Bytes read, 0 when nothing is pending or the shell is gone.
I64 HtkPtyRead(CHtkTerm *t, U8 *buffer, I64 capacity)
{
  I64 n;

  if (t->fd < 0)
    return 0;
  n = read(t->fd, buffer, capacity);
  if (n < 0)
    return 0;
  return n;
}

U0 HtkPtyWrite(CHtkTerm *t, U8 *bytes, I64 count)
{
  if (t->fd >= 0)
    write(t->fd, bytes, count);
}

U0 HtkPtyResize(CHtkTerm *t, I64 cols, I64 rows)
{
  U16 winsize[4];

  if (t->fd < 0)
    return;
  winsize[0] = rows;
  winsize[1] = cols;
  winsize[2] = 0;
  winsize[3] = 0;
  ioctl(t->fd, HTK_PTY_TIOCSWINSZ, winsize);
}

Bool HtkPtyAlive(CHtkTerm *t)
{
  I64 status;

  if (t->fd < 0)
    return FALSE;
  return waitpid(t->pid, &status, HTK_PTY_WNOHANG)(I32) != t->pid;
}

U0 HtkPtyClose(CHtkTerm *t)
{
  I64 status;

  if (t->fd < 0)
    return;
  if (!t->exited) {
    kill(t->pid, HTK_PTY_SIGHUP);
    waitpid(t->pid, &status, 0);
  }
  close(t->fd);
  t->fd = -1;
}
