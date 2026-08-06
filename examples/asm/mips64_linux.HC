#define SYS_WRITE 5001

#ifdef IS_MIPS
#ifdef IS_LINUX
#ifdef HAS_ASM
asm {
_RAW_WRITE::
  li $2, SYS_WRITE
  syscall
  jr $31
  nop
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

RawWrite(1, "mips64 syscall\n", 15);
#endif
#endif
