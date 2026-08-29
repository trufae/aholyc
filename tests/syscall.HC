#include "../lib/syscall/syscall.hc"

I64 written;
I64 page;

#ifdef IS_DARWIN
#define TEST_MAP_FLAGS 0x1002
#else
#define TEST_MAP_FLAGS 0x22
#endif

written = Syscall3(SYS_write, 1, "syscall\n", 8);
if (written != 8 || Syscall0(SYS_getpid) <= 0 || Syscall(SYS_getpid) <= 0)
  return 1;
if (Syscall1(SYS_close, -1) != -9)
  return 2;
if (Syscall4(SYS_getpid, 0, 0, 0, 0) <= 0 ||
  Syscall5(SYS_getpid, 0, 0, 0, 0, 0) <= 0)
  return 3;
page = Syscall6(SYS_mmap, 0, 4096, 0, TEST_MAP_FLAGS, -1, 0);
if (page < 0 || Syscall2(SYS_munmap, page, 4096))
  return 4;
if (Syscall(SYS_getpid, 0, 0, 0, 0, 0, 0, 0) !=
  SYSCALL_ERROR_ARGUMENTS)
  return 5;
"ok\n";
