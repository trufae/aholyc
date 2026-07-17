// Print format codes and string helpers.
"dec %d hex %X chr %c str %s\n", 255, 255, 'A', "abc";
"pad [%5d] [%-5d] [%05d]\n", 42, 42, 42;
"float %f e %e g %g\n", 3.14, 12345.678, 0.5;

// "" means: the format string is a variable
U8 *fmt = "custom %d\n";
"" fmt, 7;

U8 buf[64];
StrPrint(buf, "%s-%d", "id", 9);
"%s\n", buf;

U8 *m = MStrPrint("%d bottles", 99);
"%s (len %d)\n", m, StrLen(m);
Free(m);
