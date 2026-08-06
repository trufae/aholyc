#ifdef HAS_ASM
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
#else
U8 asm_data_bytes[2] = {0x41, 0};
U16 asm_data_words[2] = {0x1234, 0x1234};
U32 asm_data_long = 0x12345678;
U64 asm_data_quad = 0x0123456789ABCDEF;
U8 native_asm_data[3] = {0x42, 0x43, 0};
#ifdef IS_ARM_64
U64 native_asm_dword = 0x89ABCDEF;
#endif
#endif

"assembly data directives built\n";
