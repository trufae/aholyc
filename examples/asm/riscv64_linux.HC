#define SYS_WRITE 64

#ifdef IS_RISCV
#ifdef IS_LINUX
asm {
_RAW_WRITE::
  li a7, SYS_WRITE
  ecall
  ret
};

public _extern _RAW_WRITE I64 RawWrite(I64 fd, U8 *buf, I64 len);

RawWrite(1, "riscv syscall\n", 14);
#endif
#endif
