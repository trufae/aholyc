asm {
  IMPORT _ASM_IMPORT_A,
    _ASM_IMPORT_B;
_ASM_DIRECTIVES:
  LIST
  DU8 "AB",
    0;
  DU16 2 DUP(0x1234);
  DU32 0x12345678;
  DU64 0x0123456789ABCDEF;
#ifdef IS_X86_64
  ALIGN 16, OC_NOP
  USE16
  USE32
  USE64
  MOV RAX, I64 [RBP]
#else
  ALIGN 16, 0
#endif
  ORG 64
  BINFILE "not-read-while-emitting-source.bin";
  .byte 1
  .string "z"
#ifdef IS_ARM_64
  .dword 0x89ABCDEF
#endif
  NOLIST
};
