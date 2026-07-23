/* C side of the variadic FFI test (tests/varargs.HC): calls back into
 * the public HolyC variadic HcSum using its (argc, I64 *argv) contract */
#include <stdint.h>

extern int64_t HcSum(int64_t argc, int64_t *argv);

int64_t CallHcSum(void) {
	int64_t args[3] = { 10, 20, 12 };
	return HcSum(3, args);
}
