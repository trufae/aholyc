# Direct syscalls

`lib/syscall/syscall.hc` provides header-only, always-inline syscall functions
and selects syscall numbers for the current OS and architecture:

- Linux x86-64
- Linux arm64
- Linux riscv64
- Darwin x86-64
- Darwin arm64 (macOS, iOS/iPadOS, tvOS, watchOS, and visionOS targets)

```holyc
#include "lib/syscall/syscall.hc"

I64 pid = Syscall0(SYS_getpid);
I64 written = Syscall3(SYS_write, 1, "hello\n", 6);
```

`Syscall0(number)` through `Syscall6(number, arg0, ..., arg5)` have fixed
signatures and separate inline-assembly blocks that load only the declared
argument registers. They should be preferred when the arity is known. The
compatible variadic `Syscall(number, ...)` form accepts zero through six
integer- or pointer-shaped arguments; passing more than six returns
`SYSCALL_ERROR_ARGUMENTS` (`-22`) without entering the kernel. All forms return
the raw result and do not set libc `errno`; failures are normalized to
`-errno` on both Linux and Darwin.

The public `SYS_*` values are the unmodified numbers listed by each kernel.
On Darwin x86-64 the implementation adds `SYSCALL_CLASS_UNIX` internally, so
callers use the same Darwin table on Intel and Apple Silicon.

This module requires a native backend with assembly enabled. It intentionally
does not fall back to libc under the JavaScript backend or `-fno-asm`.
Direct Darwin syscalls are a private kernel ABI; prefer public platform APIs
for long-lived applications.

The Linux tables track the kernel's x86-64 and 64-bit asm-generic tables.
The Darwin table tracks Apple's `sys/syscall.h`; availability still depends
on the running kernel, its configuration, and sandbox policy.
