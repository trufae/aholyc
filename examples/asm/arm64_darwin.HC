#define SYS_WRITE 4

#ifdef IS_ARM_64
#ifdef IS_MACOS
/* @inline */
I64 RawWrite(I64 fd, U8 *buf, I64 len)
{
  I64 result;
  asm {
    ldr x0, [&fd]
    ldr x1, [&buf]
    ldr x2, [&len]
    mov x16, SYS_WRITE
    svc 0x80
    str x0, [&result]
  };
  return result;
}

RawWrite(1, "arm64 darwin syscall\n", 21);
#endif
#endif
