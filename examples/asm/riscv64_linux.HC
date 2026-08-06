#define SYS_WRITE 64

#ifdef IS_RISCV
#ifdef IS_LINUX
#ifdef HAS_ASM
asm {
_RAW_WRITE::
  li a7, SYS_WRITE
  ecall
  ret
};

public _extern _RAW_WRITE I64 RawWrite(I64 fd, U8 *buf, I64 len);
#else
I64 RawWrite(I64 fd, U8 *buf, I64 len)
{
  I64 i;
  if (fd != 1)
    return -1;
  for (i = 0; i < len; i++)
    PutChars(buf[i]);
  return len;
}
#endif

RawWrite(1, "riscv syscall\n", 14);
#endif
#endif
