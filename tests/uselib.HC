// calling into a plain C library: declare with extern, link with -L/-l
extern I64 Quad(I64 x);
extern I64 clib_counter;

"quad(%d)=%d\n", clib_counter, Quad(clib_counter);
