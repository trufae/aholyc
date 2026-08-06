#ifdef IS_X86_64
/* @inline */
I64 AddOneInAsm(I64 input)
{
#ifdef HAS_ASM
  I64 noreg value = input;
  asm {
    MOVQ RAX, &value[RBP]
    ADDQ RAX, 1
    MOVQ &value[RBP], RAX
  };
  return value;
#else
  return input + 1;
#endif
}

"AddOneInAsm(41)=%d\n", AddOneInAsm(41);
#endif
