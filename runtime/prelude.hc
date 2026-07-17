// mhc prelude: compiled before user code. Declares the runtime API.
#define TRUE 1
#define FALSE 0
#define NULL 0
#define ON 1
#define OFF 0
#define Bool U8
#define I64_MAX 0x7FFFFFFFFFFFFFFF
#define I64_MIN (-0x7FFFFFFFFFFFFFFF-1)
#define U8_MAX 0xFF
#define U16_MAX 0xFFFF
#define U32_MAX 0xFFFFFFFF

class CTask
{
  I64 except_ch;
  I64 catch_except;
};
extern CTask *Fs;

// console
extern U0 Print(U8 *fmt,...);
extern U0 PutChars(I64 ch);
extern U0 PutS(U8 *s);
extern I64 GetChar();
extern U8 *GetStr(U8 *prompt=NULL);

// memory
extern U8 *MAlloc(I64 size);
extern U8 *CAlloc(I64 size);
extern U0 Free(U8 *p);
extern I64 MSize(U8 *p);
extern U8 *MemCpy(U8 *dst,U8 *src,I64 n);
extern U8 *MemSet(U8 *dst,I64 val,I64 n);
extern I64 MemCmp(U8 *a,U8 *b,I64 n);

// strings
extern I64 StrLen(U8 *s);
extern U8 *StrCpy(U8 *dst,U8 *src);
extern U8 *StrCat(U8 *dst,U8 *src);
extern I64 StrCmp(U8 *a,U8 *b);
extern U8 *StrNew(U8 *s);
extern U8 *StrPrint(U8 *dst,U8 *fmt,...);
extern U8 *MStrPrint(U8 *fmt,...);

// math
extern F64 Sqrt(F64 x);
extern F64 Sin(F64 x);
extern F64 Cos(F64 x);
extern F64 Tan(F64 x);
extern F64 ASin(F64 x);
extern F64 ACos(F64 x);
extern F64 ATan(F64 x);
extern F64 Exp(F64 x);
extern F64 Ln(F64 x);
extern F64 Log10(F64 x);
extern F64 Log2(F64 x);
extern F64 Ceil(F64 x);
extern F64 Floor(F64 x);
extern F64 Abs(F64 x);
extern I64 AbsI64(I64 x);
extern I64 Round(F64 x);
extern I64 ToI64(F64 x);
extern F64 ToF64(I64 x);
extern I64 ToBool(I64 x);
extern I64 MinI64(I64 a,I64 b);
extern I64 MaxI64(I64 a,I64 b);
extern U0 Seed(I64 seed=0);
extern I64 RandI64();
extern F64 Rand();

// exceptions
extern U0 throw(I64 ch=0);
extern U0 PutExcept(Bool catch_it=TRUE);

// misc
extern U0 Exit(I64 code=0);
