// Direct Linux/Darwin syscalls with fixed and variadic argument counts.
//
//   ./aholyc run examples/syscalls.hc

#include "../lib/syscall/syscall.hc"

#define EXAMPLE_MAP_PRIVATE 0x2
#ifdef IS_DARWIN
#define EXAMPLE_MAP_ANONYMOUS 0x1000
#else
#define EXAMPLE_MAP_ANONYMOUS 0x20
#endif


// Fixed-arity forms load only the argument registers they need.
I64 written = Syscall3(SYS_write, 1, "direct syscall\n", 15);
I64 pid = Syscall0(SYS_getpid);
I64 close_error = Syscall1(SYS_close, -1); // raw -EBADF, normally -9

// The original variadic form remains useful when the call shape is dynamic.
I64 parent_pid = Syscall(SYS_getppid);

// mmap uses all six syscall argument registers; munmap uses two.
I64 page = Syscall6(SYS_mmap, 0, 4096, 3,
  EXAMPLE_MAP_PRIVATE | EXAMPLE_MAP_ANONYMOUS, -1, 0);
I64 unmap_result = -1;
if (page >= 0)
  unmap_result = Syscall2(SYS_munmap, page, 4096);

"write=%d pid=%d ppid=%d close_error=%d mapped=%d unmap=%d\n",
  written, pid, parent_pid, close_error, page >= 0, unmap_result;
