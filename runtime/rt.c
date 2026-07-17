/* mhc HolyC runtime — portable C, no dependencies beyond libc/libm.
 * Variadic HolyC functions receive (named args..., i64 argc, i64 *argv):
 * every vararg is one 8-byte slot; F64 values are bit-copied into slots.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <setjmp.h>
#include <math.h>

typedef int64_t hc_i64;
typedef uint64_t hc_u64;
typedef double hc_f64;

/* ------------------------------------------------------------------ task */

typedef struct { hc_i64 except_ch; hc_i64 catch_except; } HcTask;
static HcTask hc_task0;
HcTask *Fs = &hc_task0;

/* ------------------------------------------------------------ exceptions */

#define HC_TRY_MAX 256
static jmp_buf hc_frames[HC_TRY_MAX];
static int hc_ntry;

void *__hc_try_push(void) {
	if (hc_ntry >= HC_TRY_MAX) {
		fprintf (stderr, "mhc-rt: try nesting too deep\n");
		exit (1);
	}
	return hc_frames[hc_ntry++];
}

void __hc_try_pop(void) {
	hc_ntry--;
}

void throw(hc_i64 ch) {
	Fs->except_ch = ch;
	Fs->catch_except = 0;
	if (hc_ntry > 0) {
		hc_ntry--;
#ifdef __APPLE__
		_longjmp (hc_frames[hc_ntry], 1);
#else
		longjmp (hc_frames[hc_ntry], 1);
#endif
	}
	char buf[9] = {0};
	memcpy (buf, &ch, 8);
	fprintf (stderr, "Unhandled Exception '%s'\n", buf);
	exit (1);
}

void PutExcept(hc_i64 catch_it) {
	char buf[9] = {0};
	memcpy (buf, &Fs->except_ch, 8);
	printf ("Except:%s\n", buf);
	Fs->catch_except = catch_it;
}

/* ---------------------------------------------------------------- memory */

/* MAlloc keeps the size in a 16-byte header so MSize works */
void *MAlloc(hc_i64 size) {
	if (size < 0) {
		size = 0;
	}
	char *p = malloc ((size_t)size + 16);
	if (!p) {
		throw (0x4D454D4F4E); /* 'NOMEM' little-endian */
	}
	*(hc_i64 *)p = size;
	return p + 16;
}

void *CAlloc(hc_i64 size) {
	void *p = MAlloc (size);
	memset (p, 0, (size_t)size);
	return p;
}

void Free(void *p) {
	if (p) {
		free ((char *)p - 16);
	}
}

hc_i64 MSize(void *p) {
	return p? *(hc_i64 *)((char *)p - 16): 0;
}

void *MemCpy(void *dst, void *src, hc_i64 n) {
	return memcpy (dst, src, (size_t)n);
}

void *MemSet(void *dst, hc_i64 val, hc_i64 n) {
	return memset (dst, (int)val, (size_t)n);
}

hc_i64 MemCmp(void *a, void *b, hc_i64 n) {
	return memcmp (a, b, (size_t)n);
}

/* --------------------------------------------------------------- strings */

hc_i64 StrLen(char *s) {
	return s? (hc_i64)strlen (s): 0;
}

char *StrCpy(char *dst, char *src) {
	return strcpy (dst, src? src: "");
}

char *StrCat(char *dst, char *src) {
	return strcat (dst, src? src: "");
}

hc_i64 StrCmp(char *a, char *b) {
	return strcmp (a? a: "", b? b: "");
}

char *StrNew(char *s) {
	if (!s) {
		s = "";
	}
	hc_i64 n = (hc_i64)strlen (s) + 1;
	char *p = MAlloc (n);
	memcpy (p, s, (size_t)n);
	return p;
}

/* ----------------------------------------------------------- Print core */

typedef struct {
	char *buf;      /* NULL: write to stdout */
	size_t len, cap;
} HcOut;

static void hc_emit(HcOut *o, const char *s, size_t n) {
	if (!o->buf) {
		fwrite (s, 1, n, stdout);
		return;
	}
	while (o->len + n + 1 > o->cap) {
		o->cap *= 2;
		o->buf = realloc (o->buf, o->cap);
	}
	memcpy (o->buf + o->len, s, n);
	o->len += n;
	o->buf[o->len] = 0;
}

static void hc_format(HcOut *o, char *fmt, hc_i64 argc, hc_i64 *argv) {
	int ai = 0;
	char spec[32], out[512];
	if (!fmt) {
		return;
	}
	for (char *p = fmt; *p; p++) {
		if (*p != '%') {
			char *q = p;
			while (*q && *q != '%') q++;
			hc_emit (o, p, q - p);
			p = q - 1;
			continue;
		}
		p++;
		if (*p == '%') {
			hc_emit (o, "%", 1);
			continue;
		}
		/* collect flags/width/precision */
		int si = 0;
		spec[si++] = '%';
		while (*p == '-' || *p == '0' || *p == '+' || *p == ' ') {
			if (si < 20) spec[si++] = *p;
			p++;
		}
		while (*p >= '0' && *p <= '9') {
			if (si < 20) spec[si++] = *p;
			p++;
		}
		if (*p == '.') {
			if (si < 20) spec[si++] = *p;
			p++;
			while (*p >= '0' && *p <= '9') {
				if (si < 20) spec[si++] = *p;
				p++;
			}
		}
		hc_i64 a = ai < argc? argv[ai]: 0;
		ai++;
		switch (*p) {
		case 'd':
		case 'i':
			spec[si] = 0;
			strcat (spec, "lld");
			snprintf (out, sizeof(out), spec, (long long)a);
			break;
		case 'u':
			spec[si] = 0;
			strcat (spec, "llu");
			snprintf (out, sizeof(out), spec, (unsigned long long)a);
			break;
		case 'x':
		case 'X':
		case 'o':
			spec[si] = 0;
			strcat (spec, *p == 'o'? "llo": (*p == 'x'? "llx": "llX"));
			snprintf (out, sizeof(out), spec, (unsigned long long)a);
			break;
		case 'p':
		case 'P':
			snprintf (out, sizeof(out), "%016llX", (unsigned long long)a);
			break;
		case 'c': {
			/* HolyC %c prints all packed chars (up to 8) */
			int n = 0;
			hc_u64 v = (hc_u64)a;
			while (v && n < 8) {
				out[n++] = (char)(v & 0xff);
				v >>= 8;
			}
			if (n == 0) {
				out[n++] = 0;
			}
			out[n] = 0;
			break;
		}
		case 's': {
			char *s = (char *)(intptr_t)a;
			spec[si] = 0;
			strcat (spec, "s");
			snprintf (out, sizeof(out), spec, s? s: "(null)");
			break;
		}
		case 'f':
		case 'e':
		case 'g': {
			hc_f64 d;
			memcpy (&d, &a, 8);
			spec[si] = 0;
			char cc[2] = { *p, 0 };
			strcat (spec, cc);
			snprintf (out, sizeof(out), spec, d);
			break;
		}
		case 0:
			return;
		default:
			out[0] = '%';
			out[1] = *p;
			out[2] = 0;
			break;
		}
		hc_emit (o, out, strlen (out));
	}
}

void Print(char *fmt, hc_i64 argc, hc_i64 *argv) {
	HcOut o = {0};
	hc_format (&o, fmt, argc, argv);
	fflush (stdout);
}

char *StrPrint(char *dst, char *fmt, hc_i64 argc, hc_i64 *argv) {
	HcOut o = { dst, 0, (size_t)-1 };
	if (dst) {
		dst[0] = 0;
	}
	hc_format (&o, fmt, argc, argv);
	return dst;
}

char *MStrPrint(char *fmt, hc_i64 argc, hc_i64 *argv) {
	HcOut o = {0};
	o.cap = 64;
	o.buf = malloc (o.cap);
	o.buf[0] = 0;
	hc_format (&o, fmt, argc, argv);
	char *res = StrNew (o.buf);
	free (o.buf);
	return res;
}

void PutChars(hc_i64 ch) {
	char out[9];
	int n = 0;
	hc_u64 v = (hc_u64)ch;
	while (v && n < 8) {
		out[n++] = (char)(v & 0xff);
		v >>= 8;
	}
	fwrite (out, 1, n, stdout);
	fflush (stdout);
}

void PutS(char *s) {
	if (s) {
		fputs (s, stdout);
		fflush (stdout);
	}
}

/* ------------------------------------------------------------------- io */

hc_i64 GetChar(void) {
	return getchar ();
}

char *GetStr(char *prompt) {
	if (prompt) {
		Print (prompt, 0, NULL);
	}
	char buf[4096];
	if (!fgets (buf, sizeof(buf), stdin)) {
		buf[0] = 0;
	}
	size_t n = strlen (buf);
	if (n && buf[n - 1] == '\n') {
		buf[n - 1] = 0;
	}
	return StrNew (buf);
}

/* ----------------------------------------------------------------- math */

hc_f64 __hc_pow(hc_f64 a, hc_f64 b) { return pow (a, b); }
hc_f64 Sqrt(hc_f64 x) { return sqrt (x); }
hc_f64 Sin(hc_f64 x) { return sin (x); }
hc_f64 Cos(hc_f64 x) { return cos (x); }
hc_f64 Tan(hc_f64 x) { return tan (x); }
hc_f64 ASin(hc_f64 x) { return asin (x); }
hc_f64 ACos(hc_f64 x) { return acos (x); }
hc_f64 ATan(hc_f64 x) { return atan (x); }
hc_f64 Exp(hc_f64 x) { return exp (x); }
hc_f64 Ln(hc_f64 x) { return log (x); }
hc_f64 Log10(hc_f64 x) { return log10 (x); }
hc_f64 Log2(hc_f64 x) { return log2 (x); }
hc_f64 Ceil(hc_f64 x) { return ceil (x); }
hc_f64 Floor(hc_f64 x) { return floor (x); }
hc_f64 Abs(hc_f64 x) { return fabs (x); }
hc_i64 AbsI64(hc_i64 x) { return x < 0? -x: x; }
hc_i64 Round(hc_f64 x) { return (hc_i64)llround (x); }
hc_i64 ToI64(hc_f64 x) { return (hc_i64)x; }
hc_f64 ToF64(hc_i64 x) { return (hc_f64)x; }
hc_i64 ToBool(hc_i64 x) { return x != 0; }
hc_i64 MinI64(hc_i64 a, hc_i64 b) { return a < b? a: b; }
hc_i64 MaxI64(hc_i64 a, hc_i64 b) { return a > b? a: b; }

static hc_u64 hc_seed = 0x5DEECE66DULL;
void Seed(hc_i64 seed) {
	hc_seed = (hc_u64)seed;
}

hc_i64 RandI64(void) {
	hc_seed = hc_seed * 6364136223846793005ULL + 1442695040888963407ULL;
	return (hc_i64)(hc_seed >> 1);
}

hc_f64 Rand(void) {
	return (hc_f64)((hc_u64)RandI64 () >> 11) / 9007199254740992.0;
}

/* ----------------------------------------------------------------- misc */

void Exit(hc_i64 code) {
	exit ((int)code);
}

/* Whole-program builds define __hc_start; objects built with -c run their
 * top-level code from constructors instead, so the symbol may be absent. */
void __hc_start(void) __attribute__((weak));

int main(void) {
	if (__hc_start) {
		__hc_start ();
	}
	return 0;
}
