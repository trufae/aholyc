// This program can also be copied to an Amiga and run as a smoke test.
#ifndef IS_AMIGA
wrong_os;
#endif
#ifndef IS_M68K
wrong_cpu;
#endif
#ifndef IS_BIG_ENDIAN
wrong_byte_order;
#endif
#if defined(IS_MACOS) || defined(IS_LINUX) || defined(IS_WINDOWS) || defined(IS_UNIX)
host_os_leaked;
#endif
#if defined(IS_ARM_64) || defined(IS_X86_64) || defined(IS_LITTLE_ENDIAN) || defined(HAS_ASM)
host_capability_leaked;
#endif

U0 Check(I64 condition)
{
  if (!condition)
    throw('Amiga');
}

class Odd
{
  U8 tag;
  I16 word;
  I32 dword;
  I64 quad;
  F64 real;
  U8 *text;
};

I64 NarrowAddress(I16 value)
{
  return *(&value);
}

// Taking a narrow parameter's address has different offsets on the host
// and target. #exe must still use the host ABI while cross-compiling.
#exe {
  StreamPrint("#define AMIGA_EXE_VALUE %d\n", NarrowAddress(-1234));
}
#if AMIGA_EXE_VALUE != -1234
wrong_compile_time_abi;
#endif

U0 Raised()
{
  throw('Amiga');
}

// Native C int arguments/results must be declared as I32 on Amiga.
extern I32 putchar(I32 ch);
extern U0 *memset(U0 *mem, I32 byte, U32 size);

I64 NativeNarrowAddress(I16 value)
{
  memset(&value, 0x12, 2);
  return *(&value);
}

Odd odd;
odd.tag = 1;
odd.word = -1234;
odd.dword = -1234567;
odd.quad = 0x123456789ABCDEF;
odd.real = 1.25;
odd.text = "packed";
Check(odd.word == -1234 && odd.dword == -1234567);
Check(odd.quad == 0x123456789ABCDEF && odd.real == 1.25);
Check(StrCmp(odd.text, "packed") == 0);
Check(NarrowAddress(-1234) == -1234);
Check(NativeNarrowAddress(-1234) == 0x1212);
Check(sizeof(U8 *) == 8);
Check(argv[argc] == NULL);

I64 q = 0x1122334455667788;
Check(q.u8[0] == 0x11 && q.u8[7] == 0x88);
q.u8[0] = 0x22;
Check(q == 0x2222334455667788);

U8 bits[2];
Check(LBts(bits, 9) == 0 && Bt(bits, 9) == 1);
Check(LBtr(bits, 9) == 1 && Bt(bits, 9) == 0);
Check(LBtc(bits, 9) == 0 && LBtc(bits, 9) == 1);

I64 caught = FALSE;
try {
  Raised;
} catch {
  Check(Fs->except_ch == 'Amiga');
  Fs->catch_except = TRUE;
  caught = TRUE;
}
Check(caught);
Check(putchar('A') == 'A');
"miga checks passed\n";
