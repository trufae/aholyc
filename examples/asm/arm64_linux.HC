#define SYS_WRITE 64

#ifdef IS_ARM_64
#ifdef IS_LINUX
asm {
_RAW_WRITE::
  mov x8, SYS_WRITE
  svc #0
  ret
};

public _extern _RAW_WRITE I64 RawWrite(I64 fd, U8 *buf, I64 len);

RawWrite(1, "arm64 syscall\n", 14);
#endif
#endif
