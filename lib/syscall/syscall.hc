#ifndef AHOLYC_LIB_SYSCALL_HC
#define AHOLYC_LIB_SYSCALL_HC

#include "numbers.hc"

#define SYSCALL_MAX_ARGS 6
#define SYSCALL_ERROR_ARGUMENTS (-22)

#ifdef IS_DARWIN
// x86-64 Darwin encodes the BSD syscall class in the high byte. arm64
// selects the same class through svc 0x80 and keeps the number unclassed.
#define SYSCALL_CLASS_UNIX 0x02000000
#endif

#ifndef HAS_ASM
#error lib/syscall requires a native asm backend (do not use -fno-asm)
#endif

// Every fixed-arity entry point owns an asm block and loads only its declared
// syscall arguments. The return is raw and errno-free: failures are returned
// as -errno on every supported target. Darwin's carry/positive-errno
// convention is normalized here to match Linux.
/* @inline */
I64 Syscall6(I64 number, I64 argument0, I64 argument1, I64 argument2,
  I64 argument3, I64 argument4, I64 argument5)
{
  I64 result;
  I64 arguments[SYSCALL_MAX_ARGS] = {
    argument0, argument1, argument2, argument3, argument4, argument5
  };

  #ifdef IS_X86_64
  asm {
    MOVQ RAX, [&number]
  #ifdef IS_DARWIN
    ORQ RAX, SYSCALL_CLASS_UNIX
  #endif
    MOVQ R11, &arguments
    MOVQ RDI, [R11]
    MOVQ RSI, [R11+8]
    MOVQ RDX, [R11+16]
    MOVQ R10, [R11+24]
    MOVQ R8, [R11+32]
    MOVQ R9, [R11+40]
    SYSCALL
  #ifdef IS_DARWIN
    SBBQ R11, R11
    XORQ RAX, R11
    SUBQ RAX, R11
  #endif
    MOVQ [&result], RAX
  };
  #else
  #ifdef IS_ARM_64
  asm {
    MOV X9, &arguments
    LDR X0, [X9]
    LDR X1, [X9, #8]
    LDR X2, [X9, #16]
    LDR X3, [X9, #24]
    LDR X4, [X9, #32]
    LDR X5, [X9, #40]
  #ifdef IS_DARWIN
    LDR X16, [&number]
    SVC 0x80
    CNEG X0, X0, CS
  #else
    LDR X8, [&number]
    SVC #0
  #endif
    STR X0, [&result]
  };
  #else
  #ifdef IS_RISCV
  asm {
    MV T0, &arguments
    LD A0, 0(T0)
    LD A1, 8(T0)
    LD A2, 16(T0)
    LD A3, 24(T0)
    LD A4, 32(T0)
    LD A5, 40(T0)
    LD A7, 0(&number)
    ECALL
    SD A0, 0(&result)
  };
  #endif
  #endif
  #endif

  return result;
}

/* @inline */
I64 Syscall0(I64 number)
{
  I64 result;

  #ifdef IS_X86_64
  asm {
    MOVQ RAX, [&number]
  #ifdef IS_DARWIN
    ORQ RAX, SYSCALL_CLASS_UNIX
  #endif
    SYSCALL
  #ifdef IS_DARWIN
    SBBQ R11, R11
    XORQ RAX, R11
    SUBQ RAX, R11
  #endif
    MOVQ [&result], RAX
  };
  #else
  #ifdef IS_ARM_64
  asm {
  #ifdef IS_DARWIN
    LDR X16, [&number]
    SVC 0x80
    CNEG X0, X0, CS
  #else
    LDR X8, [&number]
    SVC #0
  #endif
    STR X0, [&result]
  };
  #else
  #ifdef IS_RISCV
  asm {
    LD A7, 0(&number)
    ECALL
    SD A0, 0(&result)
  };
  #endif
  #endif
  #endif

  return result;
}

/* @inline */
I64 Syscall1(I64 number, I64 argument0)
{
  I64 result;
  I64 arguments[1] = {argument0};

  #ifdef IS_X86_64
  asm {
    MOVQ RAX, [&number]
  #ifdef IS_DARWIN
    ORQ RAX, SYSCALL_CLASS_UNIX
  #endif
    MOVQ R11, &arguments
    MOVQ RDI, [R11]
    SYSCALL
  #ifdef IS_DARWIN
    SBBQ R11, R11
    XORQ RAX, R11
    SUBQ RAX, R11
  #endif
    MOVQ [&result], RAX
  };
  #else
  #ifdef IS_ARM_64
  asm {
    MOV X9, &arguments
    LDR X0, [X9]
  #ifdef IS_DARWIN
    LDR X16, [&number]
    SVC 0x80
    CNEG X0, X0, CS
  #else
    LDR X8, [&number]
    SVC #0
  #endif
    STR X0, [&result]
  };
  #else
  #ifdef IS_RISCV
  asm {
    MV T0, &arguments
    LD A0, 0(T0)
    LD A7, 0(&number)
    ECALL
    SD A0, 0(&result)
  };
  #endif
  #endif
  #endif

  return result;
}

/* @inline */
I64 Syscall2(I64 number, I64 argument0, I64 argument1)
{
  I64 result;
  I64 arguments[2] = {argument0, argument1};

  #ifdef IS_X86_64
  asm {
    MOVQ RAX, [&number]
  #ifdef IS_DARWIN
    ORQ RAX, SYSCALL_CLASS_UNIX
  #endif
    MOVQ R11, &arguments
    MOVQ RDI, [R11]
    MOVQ RSI, [R11+8]
    SYSCALL
  #ifdef IS_DARWIN
    SBBQ R11, R11
    XORQ RAX, R11
    SUBQ RAX, R11
  #endif
    MOVQ [&result], RAX
  };
  #else
  #ifdef IS_ARM_64
  asm {
    MOV X9, &arguments
    LDR X0, [X9]
    LDR X1, [X9, #8]
  #ifdef IS_DARWIN
    LDR X16, [&number]
    SVC 0x80
    CNEG X0, X0, CS
  #else
    LDR X8, [&number]
    SVC #0
  #endif
    STR X0, [&result]
  };
  #else
  #ifdef IS_RISCV
  asm {
    MV T0, &arguments
    LD A0, 0(T0)
    LD A1, 8(T0)
    LD A7, 0(&number)
    ECALL
    SD A0, 0(&result)
  };
  #endif
  #endif
  #endif

  return result;
}

/* @inline */
I64 Syscall3(I64 number, I64 argument0, I64 argument1, I64 argument2)
{
  I64 result;
  I64 arguments[3] = {argument0, argument1, argument2};

  #ifdef IS_X86_64
  asm {
    MOVQ RAX, [&number]
  #ifdef IS_DARWIN
    ORQ RAX, SYSCALL_CLASS_UNIX
  #endif
    MOVQ R11, &arguments
    MOVQ RDI, [R11]
    MOVQ RSI, [R11+8]
    MOVQ RDX, [R11+16]
    SYSCALL
  #ifdef IS_DARWIN
    SBBQ R11, R11
    XORQ RAX, R11
    SUBQ RAX, R11
  #endif
    MOVQ [&result], RAX
  };
  #else
  #ifdef IS_ARM_64
  asm {
    MOV X9, &arguments
    LDR X0, [X9]
    LDR X1, [X9, #8]
    LDR X2, [X9, #16]
  #ifdef IS_DARWIN
    LDR X16, [&number]
    SVC 0x80
    CNEG X0, X0, CS
  #else
    LDR X8, [&number]
    SVC #0
  #endif
    STR X0, [&result]
  };
  #else
  #ifdef IS_RISCV
  asm {
    MV T0, &arguments
    LD A0, 0(T0)
    LD A1, 8(T0)
    LD A2, 16(T0)
    LD A7, 0(&number)
    ECALL
    SD A0, 0(&result)
  };
  #endif
  #endif
  #endif

  return result;
}

/* @inline */
I64 Syscall4(I64 number, I64 argument0, I64 argument1, I64 argument2, I64 argument3)
{
  I64 result;
  I64 arguments[4] = {argument0, argument1, argument2, argument3};

  #ifdef IS_X86_64
  asm {
    MOVQ RAX, [&number]
  #ifdef IS_DARWIN
    ORQ RAX, SYSCALL_CLASS_UNIX
  #endif
    MOVQ R11, &arguments
    MOVQ RDI, [R11]
    MOVQ RSI, [R11+8]
    MOVQ RDX, [R11+16]
    MOVQ R10, [R11+24]
    SYSCALL
  #ifdef IS_DARWIN
    SBBQ R11, R11
    XORQ RAX, R11
    SUBQ RAX, R11
  #endif
    MOVQ [&result], RAX
  };
  #else
  #ifdef IS_ARM_64
  asm {
    MOV X9, &arguments
    LDR X0, [X9]
    LDR X1, [X9, #8]
    LDR X2, [X9, #16]
    LDR X3, [X9, #24]
  #ifdef IS_DARWIN
    LDR X16, [&number]
    SVC 0x80
    CNEG X0, X0, CS
  #else
    LDR X8, [&number]
    SVC #0
  #endif
    STR X0, [&result]
  };
  #else
  #ifdef IS_RISCV
  asm {
    MV T0, &arguments
    LD A0, 0(T0)
    LD A1, 8(T0)
    LD A2, 16(T0)
    LD A3, 24(T0)
    LD A7, 0(&number)
    ECALL
    SD A0, 0(&result)
  };
  #endif
  #endif
  #endif

  return result;
}

/* @inline */
I64 Syscall5(I64 number, I64 argument0, I64 argument1, I64 argument2, I64 argument3, I64 argument4)
{
  I64 result;
  I64 arguments[5] = {argument0, argument1, argument2, argument3, argument4};

  #ifdef IS_X86_64
  asm {
    MOVQ RAX, [&number]
  #ifdef IS_DARWIN
    ORQ RAX, SYSCALL_CLASS_UNIX
  #endif
    MOVQ R11, &arguments
    MOVQ RDI, [R11]
    MOVQ RSI, [R11+8]
    MOVQ RDX, [R11+16]
    MOVQ R10, [R11+24]
    MOVQ R8, [R11+32]
    SYSCALL
  #ifdef IS_DARWIN
    SBBQ R11, R11
    XORQ RAX, R11
    SUBQ RAX, R11
  #endif
    MOVQ [&result], RAX
  };
  #else
  #ifdef IS_ARM_64
  asm {
    MOV X9, &arguments
    LDR X0, [X9]
    LDR X1, [X9, #8]
    LDR X2, [X9, #16]
    LDR X3, [X9, #24]
    LDR X4, [X9, #32]
  #ifdef IS_DARWIN
    LDR X16, [&number]
    SVC 0x80
    CNEG X0, X0, CS
  #else
    LDR X8, [&number]
    SVC #0
  #endif
    STR X0, [&result]
  };
  #else
  #ifdef IS_RISCV
  asm {
    MV T0, &arguments
    LD A0, 0(T0)
    LD A1, 8(T0)
    LD A2, 16(T0)
    LD A3, 24(T0)
    LD A4, 32(T0)
    LD A7, 0(&number)
    ECALL
    SD A0, 0(&result)
  };
  #endif
  #endif
  #endif

  return result;
}

// Variadic form retained for dynamic call sites. Prefer Syscall0 through
// Syscall6 when the arity is known so the fixed signature can inline better.
/* @inline */
I64 Syscall(I64 number, ...)
{
  I64 result = SYSCALL_ERROR_ARGUMENTS;
  I64 arguments[SYSCALL_MAX_ARGS] = {0, 0, 0, 0, 0, 0};
  I64 index;

  if (argc < 0 || argc > SYSCALL_MAX_ARGS)
    return result;
  for (index = 0; index < argc; index++)
    arguments[index] = argv[index];

  #ifdef IS_X86_64
  asm {
    MOVQ RAX, [&number]
  #ifdef IS_DARWIN
    ORQ RAX, SYSCALL_CLASS_UNIX
  #endif
    MOVQ R11, &arguments
    MOVQ RDI, [R11]
    MOVQ RSI, [R11+8]
    MOVQ RDX, [R11+16]
    MOVQ R10, [R11+24]
    MOVQ R8, [R11+32]
    MOVQ R9, [R11+40]
    SYSCALL
  #ifdef IS_DARWIN
    SBBQ R11, R11
    XORQ RAX, R11
    SUBQ RAX, R11
  #endif
    MOVQ [&result], RAX
  };
  #else
  #ifdef IS_ARM_64
  asm {
    MOV X9, &arguments
    LDR X0, [X9]
    LDR X1, [X9, #8]
    LDR X2, [X9, #16]
    LDR X3, [X9, #24]
    LDR X4, [X9, #32]
    LDR X5, [X9, #40]
  #ifdef IS_DARWIN
    LDR X16, [&number]
    SVC 0x80
    CNEG X0, X0, CS
  #else
    LDR X8, [&number]
    SVC #0
  #endif
    STR X0, [&result]
  };
  #else
  #ifdef IS_RISCV
  asm {
    MV T0, &arguments
    LD A0, 0(T0)
    LD A1, 8(T0)
    LD A2, 16(T0)
    LD A3, 24(T0)
    LD A4, 32(T0)
    LD A5, 40(T0)
    LD A7, 0(&number)
    ECALL
    SD A0, 0(&result)
  };
  #endif
  #endif
  #endif

  return result;
}

#endif
