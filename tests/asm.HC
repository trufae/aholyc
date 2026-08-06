#define ASM_RETURN_VALUE 42

#ifdef IS_X86_64
asm {
_ASM_RETURN::
  MOVQ RAX, ASM_RETURN_VALUE
  RET
};

/* @inline */
I64 ExerciseInlineAsm(I64 input)
{
  I64 noreg value = input;
  asm {
    MOVQ R10, 2
  @@again:
    SUBQ R10, 1
    JNZ @@again
    MOVQ RAX, &value[RBP]
    ADDQ RAX, 1
    MOVQ &value[RBP], RAX
  };
  return value;
}
#endif

#ifdef IS_ARM_64
asm {
_ASM_RETURN::
  MOV X0, ASM_RETURN_VALUE
  RET
};

/* @inline */
I64 ExerciseInlineAsm(I64 input)
{
  asm {
    MOV X9, 2
  @@again:
    SUBS X9, X9, 1
    B.NE @@again
  };
  return input + 1;
}
#endif

#ifdef IS_RISCV
asm {
_ASM_RETURN::
  li a0, ASM_RETURN_VALUE
  ret
};

/* @inline */
I64 ExerciseInlineAsm(I64 input)
{
  asm {
    li t0, 2
  @@again:
    addi t0, t0, -1
    bnez t0, @@again
  };
  return input + 1;
}
#endif

#ifdef IS_MIPS
asm {
_ASM_RETURN::
  li $2, ASM_RETURN_VALUE
  jr $31
  nop
};

/* @inline */
I64 ExerciseInlineAsm(I64 input)
{
  asm {
    li $8, 2
  @@again:
    addiu $8, $8, -1
    bnez $8, @@again
    nop
  };
  return input + 1;
}
#endif

#ifdef IS_S390
asm {
_ASM_RETURN::
  lghi %r2, ASM_RETURN_VALUE
  br %r14
};

/* @inline */
I64 ExerciseInlineAsm(I64 input)
{
  I64 noreg value = input;
  asm {
    lghi %r0, 2
  @@again:
    brctg %r0, @@again
    lg %r0, 0(&value)
    aghi %r0, 1
    stg %r0, 0(&value)
  };
  return value;
}
#endif

public _extern _ASM_RETURN I64 AsmReturn();

"asm=%d inline=%d\n", AsmReturn, ExerciseInlineAsm(41);
