#ifndef AHOLYC_LIB_SYSCALL_NUMBERS_HC
#define AHOLYC_LIB_SYSCALL_NUMBERS_HC

// Select exactly the table matching the target kernel ABI. Linux AArch64
// and RV64 both use the kernel's 64-bit asm-generic numbering.
#ifdef IS_LINUX
#ifdef IS_X86_64
#include "linux_x86_64.hc"
#else
#ifdef IS_ARM_64
#include "linux_arm64_riscv64.hc"
#else
#ifdef IS_RISCV
#include "linux_arm64_riscv64.hc"
#else
#error lib/syscall supports Linux x86-64, arm64, and riscv64
#endif
#endif
#endif
#else
#ifdef IS_DARWIN
#ifdef IS_X86_64
#include "darwin.hc"
#else
#ifdef IS_ARM_64
#include "darwin.hc"
#else
#error lib/syscall supports Darwin x86-64 and arm64
#endif
#endif
#else
#error lib/syscall supports Linux and Darwin
#endif
#endif

#endif
