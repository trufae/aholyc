#include "aholyc.h"

static void reserve(StrBuf *sb, size_t n) {
	if (n > SIZE_MAX - sb->len - 1) {
		error (sb->cc, "string buffer overflow");
	}
	size_t need = sb->len + n + 1;
	if (need <= sb->cap) {
		return;
	}
	size_t cap = sb->cap <= SIZE_MAX / 2? sb->cap * 2: need;
	if (cap < need) cap = need;
	char *data = xmalloc (sb->cc, cap);
	memcpy (data, sb->data, sb->len + 1);
	sb->data = data;
	sb->cap = cap;
}

void sb_init(StrBuf *sb, Aholyc *cc) {
	sb->cc = cc;
	sb->data = sb->buf;
	sb->len = 0;
	sb->cap = sizeof(sb->buf);
	sb->buf[0] = 0;
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
		error (sb->cc, "string formatting failed");
	}
	if ((size_t)n >= avail) {
		reserve (sb, (size_t)n);
		int written = vsnprintf (sb->data + sb->len, (size_t)n + 1, fmt, aq);
		if (written != n) {
			va_end (aq);
			error (sb->cc, "string formatting failed");
		}
	}
	va_end (aq);
	sb->len += (size_t)n;
}

char *sb_take(StrBuf *sb) {
	char *s;
	if (sb->data == sb->buf) {
		s = xmalloc (sb->cc, sb->len + 1);
		memcpy (s, sb->buf, sb->len + 1);
	} else {
		s = sb->data;
	}
	sb_init (sb, sb->cc);
	return s;
}
