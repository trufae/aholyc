#define SYS_WRITE 1

#ifdef IS_X86_64
#ifdef IS_LINUX
#ifdef HAS_ASM
asm {
_RAW_WRITE::
  MOVQ RAX, SYS_WRITE
  SYSCALL
  RET
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

RawWrite(1, "x86-64 syscall\n", 15);
#endif
#endif
