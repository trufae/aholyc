#include <stdint.h>
#include <stddef.h>

void *AbiGlobal;
extern int8_t HcRetI8(int8_t value);

int8_t AbiRetI8(void) {
	return -5;
}

uint8_t AbiRetU8(void) {
	return 250;
}

int32_t AbiRetI32(void) {
	return -1234567;
}

uint32_t AbiRetU32(void) {
	return UINT32_C(4000000000);
}

int32_t AbiPromoteI8(int8_t value) {
	return value;
}

uint32_t AbiPromoteU8(uint8_t value) {
	return value;
}

int32_t AbiPromoteI16(int16_t value) {
	return value;
}

uint32_t AbiPromoteU16(uint16_t value) {
	return value;
}

int32_t AbiNarrow(int8_t a, uint8_t b, int16_t c, uint16_t d,
		int32_t e, uint32_t f) {
	return a == -1 && b == 255 && c == -2 && d == 65535 &&
		e == -3 && f == UINT32_C(4000000000);
}

void *AbiPointer(void *value) {
	return value;
}

int32_t AbiGlobalMatches(void *value) {
	return AbiGlobal == value;
}

int32_t AbiCheckCallback(void *(*callback)(void *), void *value) {
	return callback(value) == value;
}

int32_t AbiCallHcI8(void) {
	return HcRetI8(-5) == -5;
}

int32_t AbiSizeMax(size_t value) {
	return value == SIZE_MAX;
}

int32_t AbiUIntPtrMax(uintptr_t value) {
	return value == UINTPTR_MAX;
}

int32_t AbiIntPtrMin(intptr_t value) {
	return value == INTPTR_MIN;
}
