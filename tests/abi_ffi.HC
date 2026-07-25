extern I8 AbiRetI8();
extern U8 AbiRetU8();
extern I32 AbiRetI32();
extern U32 AbiRetU32();
extern I32 AbiPromoteI8(I8 value);
extern U32 AbiPromoteU8(U8 value);
extern I32 AbiPromoteI16(I16 value);
extern U32 AbiPromoteU16(U16 value);
extern I32 AbiNarrow(I8 a, U8 b, I16 c, U16 d, I32 e, U32 f);
extern U8 *AbiPointer(U8 *value);
extern U8 *AbiGlobal;
extern I32 AbiGlobalMatches(U8 *value);
extern I32 AbiCheckCallback(U8 *callback, U8 *value);
extern I32 AbiCallHcI8();
extern I32 AbiSizeMax(USZ value);
extern I32 AbiUIntPtrMax(USZ value);
extern I32 AbiIntPtrMin(ISZ value);

#ifdef IS_32BIT
#define ABI_NATIVE_BYTES 4
#else
#define ABI_NATIVE_BYTES 8
#endif

public U8 *AbiCallback(U8 *value)
{
  return value;
}

public I8 HcRetI8(I8 value)
{
  return value;
}

U8 value = 7;
U8 *pointer = &value;
I32 (*ret_i32)() = &AbiRetI32;
I32 (*narrow)(I8, U8, I16, U16, I32, U32) = &AbiNarrow;

"returns=%d,%d,%d,%d\n",
  AbiRetI8 == -5,
  AbiRetU8 == 250,
  AbiRetI32 == -1234567,
  AbiRetU32 == 4000000000;
"promote=%d,%d,%d,%d\n",
  AbiPromoteI8(-5) == -5,
  AbiPromoteU8(250) == 250,
  AbiPromoteI16(-12345) == -12345,
  AbiPromoteU16(54321) == 54321;
"narrow=%d\n", AbiNarrow(-1, 255, -2, 65535, -3, 4000000000);
"indirect=%d,%d\n",
  ret_i32() == -1234567,
  narrow(-1, 255, -2, 65535, -3, 4000000000);
AbiGlobal = pointer;
"pointers=%d,%d,%d\n",
  AbiPointer(pointer) == pointer,
  AbiGlobalMatches(pointer),
  AbiCheckCallback(&AbiCallback, pointer);
"callback-int=%d\n", AbiCallHcI8;
"native-size=%d,%d,%d,%d\n",
  sizeof(ISZ) == ABI_NATIVE_BYTES && sizeof(USZ) == ABI_NATIVE_BYTES,
  AbiSizeMax(USZ_MAX),
  AbiUIntPtrMax(USZ_MAX),
  AbiIntPtrMin(ISZ_MIN);
