#define SYS_WRITE 5001

#ifdef IS_MIPS
#ifdef IS_LINUX
asm {
_RAW_WRITE::
  li $2, SYS_WRITE
  syscall
  jr $31
  nop
};

public _extern _RAW_WRITE I64 RawWrite(I64 fd, U8 *buf, I64 len);

RawWrite(1, "mips64 syscall\n", 15);
#endif
#endif
