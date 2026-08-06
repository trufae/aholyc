asm {
  IMPORT _ASM_UNUSED_A, _ASM_UNUSED_B;
_ASM_DATA:
  LIST
  DU8 "A", 0;
  DU16 2 DUP(0x1234);
  DU32 0x12345678;
  DU64 0x0123456789ABCDEF;
  ALIGN 8, 0

_NATIVE_ASM_DATA:
  .byte 0x42
  .string "C"
#ifdef IS_ARM_64
  .dword 0x89ABCDEF
#endif
  NOLIST
};

"assembly data directives built\n";
