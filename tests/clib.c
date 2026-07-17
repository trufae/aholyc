/* a plain C library, callable from HolyC via extern (see tests/uselib.HC) */
long long Quad(long long x) {
	return 4 * x;
}

long long clib_counter = 7;
