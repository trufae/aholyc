#include "aholyc.h"

/* Grow modestly beyond the request to amortize appends without keeping the
 * large excess capacity produced by repeated doubling. */
static size_t growcap(size_t cap, size_t need) {
	size_t grown = cap <= SIZE_MAX - (cap >> 3)? cap + (cap >> 3): need;
	if (grown < need) {
		grown = need <= SIZE_MAX - (need >> 3)? need + (need >> 3): need;
	}
	size_t slack = grown < 1024? 64: grown >> 4;
	return grown <= SIZE_MAX - slack? grown + slack: grown;
}

static void reserve(StrBuf *sb, size_t n) {
	if (n > SIZE_MAX - sb->len - 1) {
		error ("string buffer overflow");
	}
	size_t need = sb->len + n + 1;
	if (need <= sb->cap) {
		return;
	}
	size_t cap = growcap (sb->cap, need);
	if (sb->data == sb->buf) {
		sb->data = xmalloc (cap);
		memcpy (sb->data, sb->buf, sb->len + 1);
	} else {
		char *p = realloc (sb->data, cap);
		if (!p) {
			error ("out of memory");
		}
		sb->data = p;
	}
	sb->cap = cap;
}

void sb_init(StrBuf *sb) {
	sb->data = sb->buf;
	sb->len = 0;
	sb->cap = sizeof(sb->buf);
	sb->buf[0] = 0;
}

void sb_reset(StrBuf *sb) {
	sb->len = 0;
	sb->data[0] = 0;
}

void sb_free(StrBuf *sb) {
	if (sb->data != sb->buf) {
		free (sb->data);
	}
	sb_init (sb);
}

void sb_putn(StrBuf *sb, const char *s, size_t n) {
	if (!n) {
		return;
	}
	reserve (sb, n);
	memcpy (sb->data + sb->len, s, n);
	sb->len += n;
	sb->data[sb->len] = 0;
}

void sb_puts(StrBuf *sb, const char *s) {
	sb_putn (sb, s, strlen (s));
}

void sb_putc(StrBuf *sb, int c) {
	reserve (sb, 1);
	sb->data[sb->len++] = (char)c;
	sb->data[sb->len] = 0;
}

void sb_printf(StrBuf *sb, const char *fmt, ...) {
	va_list ap, aq;
	va_start (ap, fmt);
	va_copy (aq, ap);
	size_t avail = sb->cap - sb->len;
	int n = vsnprintf (sb->data + sb->len, avail, fmt, ap);
	va_end (ap);
	if (n < 0) {
		va_end (aq);
		error ("string formatting failed");
	}
	if ((size_t)n >= avail) {
		reserve (sb, (size_t)n);
		int written = vsnprintf (sb->data + sb->len, (size_t)n + 1, fmt, aq);
		if (written != n) {
			va_end (aq);
			error ("string formatting failed");
		}
	}
	va_end (aq);
	sb->len += (size_t)n;
}

char *sb_take(StrBuf *sb) {
	char *s;
	if (sb->data == sb->buf) {
		s = xmalloc (sb->len + 1);
		memcpy (s, sb->buf, sb->len + 1);
	} else {
		s = sb->data;
	}
	sb_init (sb);
	return s;
}
