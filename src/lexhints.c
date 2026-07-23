/* aholyc comment hints: parse annotations, attach them to tokens, and
 * preserve them while the preprocessor expands macros. */
#include "aholyc.h"
#include <ctype.h>

static bool comment_space(int c) {
	return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

static bool hint_ident_cont(int c) {
	return c == '_' || isalnum (c);
}

static bool hint_is(const char *p, int n, const char *name) {
	return n == (int)strlen (name) && !strncmp (p, name, n);
}

static const char *skip_comment_space(const char *p, const char *end) {
	while (p < end && comment_space ((unsigned char)*p)) {
		p++;
	}
	return p;
}

/* Extract supported source hints from a comment. Unknown @names remain
 * ordinary comment text. */
void lex_hints_scan_comment(Aholyc *cc, LexHints *pending,
		const char *start, const char *end, const char *fname, int line) {
	if (!cc->use_hints) {
		return;
	}
	for (const char *p = start; p < end; p++) {
		if (*p != '@') {
			continue;
		}
		const char *q = p + 1;
		while (q < end && hint_ident_cont ((unsigned char)*q)) {
			q++;
		}
		int n = q - p - 1;
		if (hint_is (p + 1, n, "align")) {
			q = skip_comment_space (q, end);
			int a = -1;
			if (q < end && *q == '=') {
				q++;
				q = skip_comment_space (q, end);
				a = 0;
				while (q < end && *q >= '0' && *q <= '9') {
					if (a <= 0x100000) {
						a = a * 10 + *q - '0';
					}
					q++;
				}
				if (a < 1 || a > 0x100000 || (a & (a - 1))) {
					error (cc, "%s:%d: @align must be a power of two", fname, line);
				}
				if (q < end && !comment_space ((unsigned char)*q) && *q != '@') {
					error (cc, "%s:%d: malformed @align hint", fname, line);
				}
			}
			if (pending->align) {
				error (cc, "%s:%d: duplicate @align hint before declaration", fname, line);
			}
			pending->align = a;
			p = q - 1;
			continue;
		}
		unsigned hint = hint_is (p + 1, n, "inline")? HINT_INLINE:
			hint_is (p + 1, n, "noinline")? HINT_NOINLINE: 0;
		if (hint) {
			if (pending->attrs) {
				error (cc, "%s:%d: duplicate hint before declaration", fname, line);
			}
			pending->attrs |= hint;
			p = q - 1;
			continue;
		}
		bool pkg = hint_is (p + 1, n, "pkgconfig");
		if (pkg || hint_is (p + 1, n, "cflags") ||
				hint_is (p + 1, n, "ldflags")) {
			/* Build-flag hints join the toolchain command on the same
			 * stream as -I/-L/-l. */
			q = skip_comment_space (q, end);
			if (q == end || *q != '=') {
				error (cc, "%s:%d: malformed @%.*s hint (expected =%s)",
					fname, line, n, p + 1, pkg? "name": "flags");
			}
			const char *w = ++q;
			while (q < end && *q != '\n' && *q != '\r') {
				q++;
			}
			char *rest = xasprintf (cc, "%.*s", (int)(q - w), w);
			if (pkg) {
				pkgconfig_push (cc, rest);
			} else {
				arg_push_words (cc, &cc->ccflags, rest);
			}
			p = q - 1;
			continue;
		}
		if (!hint_is (p + 1, n, "bits")) {
			continue;
		}
		q = skip_comment_space (q, end);
		if (q == end || *q++ != '=') {
			error (cc, "%s:%d: malformed @bits hint (expected @bits=N)", fname, line);
		}
		q = skip_comment_space (q, end);
		if (q == end || *q < '0' || *q > '9') {
			error (cc, "%s:%d: malformed @bits hint (expected @bits=N)", fname, line);
		}
		int width = 0;
		while (q < end && *q >= '0' && *q <= '9') {
			if (width <= 128) {
				width = width * 10 + (*q - '0');
			}
			q++;
		}
		if (q < end && !comment_space ((unsigned char)*q) && *q != '@') {
			error (cc, "%s:%d: malformed @bits hint (expected @bits=N)", fname, line);
		}
		if (width < 1 || width > 128) {
			error (cc, "%s:%d: @bits width must be between 1 and 128", fname, line);
		}
		if (pending->bits) {
			error (cc, "%s:%d: duplicate @bits hint before declaration", fname, line);
		}
		pending->bits = width;
		p = q - 1;
	}
}

void lex_hints_apply(LexHints *pending, Token *tok) {
	if (pending->bits) {
		tok->hint_bits = pending->bits;
		pending->bits = 0;
	}
	if (pending->align) {
		tok->hint_align = pending->align;
		pending->align = 0;
	}
	if (pending->attrs) {
		tok->hints = pending->attrs;
		pending->attrs = 0;
	}
}

void lex_hints_inherit(Aholyc *cc, Token *src, Token *dst) {
	if (!dst) {
		return;
	}
	if (src->hint_bits) {
		if (dst->hint_bits) {
			error_tok (cc, src, "duplicate @bits hint on declaration");
		}
		dst->hint_bits = src->hint_bits;
	}
	if (src->hint_align) {
		if (dst->hint_align) {
			error_tok (cc, src, "duplicate @align hint on declaration");
		}
		dst->hint_align = src->hint_align;
	}
	if (src->hints) {
		unsigned funcs = HINT_INLINE | HINT_NOINLINE;
		if (src->hints & funcs && dst->hints & funcs) {
			error_tok (cc, src, "duplicate hint on declaration");
		}
		dst->hints |= src->hints;
	}
}
