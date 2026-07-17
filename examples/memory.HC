// Pointers, MAlloc/Free, arrays, pointer arithmetic (scaled, like C).
I64 *v = MAlloc(10 * sizeof(I64));
I64 i;
for (i = 0; i < 10; i++)
  v[i] = i * i;
"%d %d %d\n", v[0], v[3], v[9];

I64 *p = v + 3;
"%d\n", *p;

U8 buf[16] = "HolyC";
"%s has %d chars\n", buf, StrLen(buf);

U8 *dup = StrNew("temple");
"%s\n", dup;
Free(dup);
Free(v);

// multi-char constants pack little-endian
"%c\n", 'Holy';
'OK!\n';
