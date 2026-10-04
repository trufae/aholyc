

#define GOOD_TARGET 0
#ifdef IS_ARM_64
#ifdef IS_LINUX
#ifdef HAS_ASM

#undef GOOD_TARGET
#define GOOD_TARGET 1
#endif
#endif
#endif

#if GOOD_TARGET
#define SYS_WRITE 64

asm {
_RAW_WRITE::
  mov x8, SYS_WRITE
  svc #0
  ret
};
// assuming calling convention is the same as the syscall. wtf?
public _extern _RAW_WRITE I64 RawWrite(I64 fd, U8 *buf, I64 len);
RawWrite(1, "arm64 syscall\n", 14);

#else
"arm64 syscall\n";
#endif
