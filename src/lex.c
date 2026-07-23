/* aholyc lexer: tokenizer, comment/hint scanning, include-path search, and
 * the compiler-instance lifecycle. The token-level preprocessor lives in
 * lexpp.c (which shares tokenize and search_include from here). */
#include "aholyc.h"
#include <unistd.h>
#include <sys/stat.h>

struct AholyIncDir { AholyIncDir *next; char *dir; };

typedef struct {
	Aholyc *cc;
	const char *file;
	int line;
} Tokenizer;

static void clear_config(Aholyc *cc) {
	xfree_to (cc, NULL);
	cc->inc_dirs = NULL;
	cc->macros = NULL;
	cc->cwd = NULL;
	cc->ccflags = (Argv){ 0 };
}

void lex_reset(Aholyc *cc) {
	clear_config (cc);
	cc->verbose = cc->keep = false;
	cc->use_hints = true;
	char *cwd = getcwd (NULL, 0);
	if (cwd) cleanup_push (cc, free, cwd);
	cc->cwd = xstrdup (cc, cwd? cwd: ".");
	if (cwd) cleanup_pop (cc);
	free (cwd);
}

Aholyc *aholyc_init(void) {
	Aholyc *cc = calloc (1, sizeof(*cc));
	if (cc) cc->diagnostics = stderr;
	return cc;
}

void aholyc_fini(Aholyc *cc) {
	if (!cc) return;
	clear_config (cc);
	free (cc);
}

static char *from_cwd(Aholyc *cc, const char *path) {
	return path[0] == '/'? xstrdup (cc, path):
		xasprintf (cc, "%s/%s", cc->cwd, path);
}

bool lex_set_cwd(Aholyc *cc, const char *path) {
	char *dir = from_cwd (cc, path);
	struct stat st;
	if (stat (dir, &st) || !S_ISDIR (st.st_mode)) {
		return false;
	}
	cc->cwd = dir;
	return true;
}

void lex_add_include_dir(Aholyc *cc, const char *dir) {
	AholyIncDir *d = xmalloc (cc, sizeof(*d));
	d->dir = from_cwd (cc, dir);
	d->next = cc->inc_dirs;
	cc->inc_dirs = d;
}

static Token *new_token(Tokenizer *tz, TokenKind kind) {
	Token *t = xcalloc (tz->cc, 1, sizeof(Token));
	t->kind = kind;
	t->cc = tz->cc;
	t->file = (char *)tz->file;
	t->line = tz->line;
	return t;
}

static bool ident_start(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; }
static bool ident_cont(int c) { return ident_start (c) || (c >= '0' && c <= '9'); }

bool lex_is_identifier(const char *s) {
	if (!s || !ident_start ((unsigned char)*s)) {
		return false;
	}
	while (ident_cont ((unsigned char)*++s)) {
	}
	return !*s;
}

static bool comment_space(int c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; }
static bool hint_is(const char *p, int n, const char *name) {
	return n == (int)strlen (name) && !strncmp (p, name, n);
}
static const char *skip_comment_space(const char *p, const char *end) {
	while (p < end && comment_space ((unsigned char)*p)) p++;
	return p;
}

/* Extract supported source hints from a comment.  Unknown @names remain
 * ordinary comment text. */
static void scan_comment_hint(Aholyc *cc, const char *start, const char *end,
                              const char *fname, int line,
                              int *pending_bits, int *pending_align,
                              unsigned *pending_hints) {
	if (!cc->use_hints) {
		return;
	}
	for (const char *p = start; p < end; p++) {
		if (*p != '@') {
			continue;
		}
		const char *q = p + 1;
		while (q < end && ident_cont ((unsigned char)*q)) {
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
					if (a <= 1048576) a = a * 10 + *q - '0';
					q++;
				}
				if (a < 1 || a > 1048576 || (a & (a - 1))) {
					error (cc, "%s:%d: @align must be a power of two", fname, line);
				}
				if (q < end && !comment_space ((unsigned char)*q) && *q != '@') {
					error (cc, "%s:%d: malformed @align hint", fname, line);
				}
			}
			if (*pending_align) {
				error (cc, "%s:%d: duplicate @align hint before declaration", fname, line);
			}
			*pending_align = a;
			p = q - 1;
			continue;
		}
		unsigned hint = hint_is (p + 1, n, "inline")? HINT_INLINE:
			hint_is (p + 1, n, "noinline")? HINT_NOINLINE: 0;
		if (hint) {
			if (*pending_hints) {
					error (cc, "%s:%d: duplicate hint before declaration", fname, line);
			}
			*pending_hints |= hint;
			p = q - 1;
			continue;
		}
		bool pkg = hint_is (p + 1, n, "pkgconfig");
		if (pkg || hint_is (p + 1, n, "cflags") || hint_is (p + 1, n, "ldflags")) {
			/* build-flag hints: the rest of the line joins the
			 * toolchain command, on the same stream as -I/-L/-l */
			q = skip_comment_space (q, end);
			if (q == end || *q != '=') {
				error (cc, "%s:%d: malformed @%.*s hint (expected =%s)",
					fname, line, n, p + 1, pkg? "name": "flags");
			}
			const char *w = ++q;
			while (q < end && *q != '\n' && *q != '\r') q++;
			char *rest = xasprintf (cc, "%.*s", (int)(q - w), w);
			if (pkg) pkgconfig_push (cc, rest);
			else arg_push_words (cc, &cc->ccflags, rest);
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
		if (*pending_bits) {
			error (cc, "%s:%d: duplicate @bits hint before declaration", fname, line);
		}
		*pending_bits = width;
		p = q - 1;
	}
}

static int hexval(int c) {
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

/* decode one escape sequence, p points after backslash; returns value, advances *pp */
static int read_escape(const char **pp) {
	const char *p = *pp;
	int c = *p++;
	int v;
	switch (c) {
	case 'n': v = '\n'; break;
	case 't': v = '\t'; break;
	case 'r': v = '\r'; break;
	case 'a': v = '\a'; break;
	case 'b': v = '\b'; break;
	case 'f': v = '\f'; break;
	case 'v': v = '\v'; break;
	case '0': v = 0; break;
	case 'x': {
		v = 0;
		while (hexval (*p) >= 0) {
			v = v * 16 + hexval (*p++);
		}
		break;
	}
	default: v = c; break;
	}
	*pp = p;
	return v;
}

static const char *const puncts[] = {
	"<<=", ">>=", "...",
	"==", "!=", "<=", ">=", "&&", "||", "^^", "<<", ">>",
	"+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "++", "--", "->", "$$",
	"+", "-", "*", "/", "%", "&", "|", "^", "~", "!", "<", ">", "=",
	"(", ")", "{", "}", "[", "]", ",", ";", ":", ".", "`", "#", "?",
	NULL
};

/* Tokenize a NUL-terminated buffer into a raw token list (directives kept). */
Token *tokenize(Aholyc *cc, const char *src, const char *fname) {
	Tokenizer tz = { cc, fname, 1 };

	Token head = {0};
	Token *cur = &head;
	const char *p = src;
	bool bol = true, space = false;
	int pending_bits = 0;
	int pending_align = 0;
	unsigned pending_hints = 0;

	while (*p) {
		if (*p == '\n') { tz.line++; bol = true; space = false; p++; continue; }
		if (*p == ' ' || *p == '\t' || *p == '\r') { space = true; p++; continue; }
		if (p[0] == '/' && p[1] == '/') {
			int line = tz.line;
			const char *start = p + 2;
			p = start;
			while (*p && *p != '\n') p++;
			scan_comment_hint (cc, start, p, fname, line, &pending_bits, &pending_align, &pending_hints);
			continue;
		}
		if (p[0] == '/' && p[1] == '*') {
			int line = tz.line;
			const char *start = p + 2;
			p = start;
			while (*p && !(p[0] == '*' && p[1] == '/')) {
				if (*p == '\n') tz.line++;
				p++;
			}
			scan_comment_hint (cc, start, p, fname, line, &pending_bits, &pending_align, &pending_hints);
			if (*p) p += 2;
			space = true;
			continue;
		}
		Token *t = NULL;
		if (ident_start (*p)) {
			const char *s = p;
			while (ident_cont (*p)) p++;
			t = new_token (&tz, TK_ID);
			t->len = p - s;
			t->str = xmalloc (cc, t->len + 1);
			memcpy (t->str, s, t->len);
			t->str[t->len] = 0;
		} else if ((*p >= '0' && *p <= '9') ||
		           (*p == '.' && p[1] >= '0' && p[1] <= '9')) {
			/* number: hex, binary, decimal int or float */
			if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
				uint64_t v = 0;
				p += 2;
				while (hexval (*p) >= 0 || *p == '_') {
					if (*p != '_') v = v * 16 + hexval (*p);
					p++;
				}
				t = new_token (&tz, TK_NUM);
				t->ival = (int64_t)v;
			} else if (p[0] == '0' && (p[1] == 'b' || p[1] == 'B')) {
				uint64_t v = 0;
				p += 2;
				while (*p == '0' || *p == '1' || *p == '_') {
					if (*p != '_') v = v * 2 + (*p - '0');
					p++;
				}
				t = new_token (&tz, TK_NUM);
				t->ival = (int64_t)v;
			} else {
				const char *s = p;
				while (*p >= '0' && *p <= '9') p++;
				bool isf = false;
				if (*p == '.' && p[1] >= '0' && p[1] <= '9') {
					isf = true;
					p++;
					while (*p >= '0' && *p <= '9') p++;
				}
				if (*p == 'e' || *p == 'E') {
					const char *q = p + 1;
					if (*q == '+' || *q == '-') q++;
					if (*q >= '0' && *q <= '9') {
						isf = true;
						p = q;
						while (*p >= '0' && *p <= '9') p++;
					}
				}
				if (isf) {
					t = new_token (&tz, TK_FNUM);
					t->fval = strtod (s, NULL);
				} else {
					t = new_token (&tz, TK_NUM);
					t->ival = (int64_t)strtoull (s, NULL, 10);
				}
			}
		} else if (*p == '"') {
			/* string literal; adjacent strings are concatenated later */
			p++;
			char *buf = xmalloc (cc, strlen (p) + 1);
			int n = 0;
			while (*p && *p != '"') {
				if (*p == '\\') {
					p++;
					buf[n++] = (char)read_escape (&p);
				} else {
					if (*p == '\n') tz.line++;
					buf[n++] = *p++;
				}
			}
			if (*p != '"') {
				error (cc, "%s:%d: unterminated string", fname, tz.line);
			}
			p++;
			buf[n] = 0; /* NUL-terminate: #include and #exe read str as C string */
			t = new_token (&tz, TK_STR);
			t->str = buf;
			t->len = n;
		} else if (*p == '\'') {
			/* char const, may pack up to 8 chars little-endian; '' is empty */
			p++;
			uint64_t v = 0;
			int n = 0;
			while (*p && *p != '\'') {
				int c;
				if (*p == '\\') {
					p++;
					c = read_escape (&p);
				} else {
					c = (unsigned char)*p++;
				}
				if (n < 8) v |= (uint64_t)(c & 0xff) << (8 * n);
				n++;
			}
			if (*p != '\'') {
				error (cc, "%s:%d: unterminated char constant", fname, tz.line);
			}
			p++;
			t = new_token (&tz, TK_CHR);
			t->ival = (int64_t)v;
			t->len = n; /* 0 for the magic '' */
		} else {
			for (int i = 0; puncts[i]; i++) {
				size_t l = strlen (puncts[i]);
				if (!strncmp (p, puncts[i], l)) {
					t = new_token (&tz, TK_PUNCT);
					t->str = (char *)puncts[i];
					t->len = l;
					p += l;
					break;
				}
			}
			if (!t) {
				error (cc, "%s:%d: stray character '%c' (0x%02x)",
					fname, tz.line, *p, (unsigned char)*p);
			}
		}
		if (pending_bits) {
			t->hint_bits = pending_bits;
			pending_bits = 0;
		}
		if (pending_align) {
			t->hint_align = pending_align;
			pending_align = 0;
		}
		if (pending_hints) {
			t->hints = pending_hints;
			pending_hints = 0;
		}
		t->at_bol = bol;
		t->has_space = space;
		bol = false;
		space = false;
		cur->next = t;
		cur = t;
	}
	Token *eof = new_token (&tz, TK_EOF);
	eof->at_bol = true;
	cur->next = eof;
	return head.next;
}

char *search_include(Aholyc *cc, const char *name,
		const char *from_file) {
	/* relative to including file first */
	const char *slash = from_file? strrchr (from_file, '/'): NULL;
	if (slash) {
		char *dir = xstrdup (cc, from_file);
		dir[slash - from_file] = 0;
		char *path = xasprintf (cc, "%s/%s", dir, name);
		FILE *f = fopen (path, "r");
		if (f) {
			fclose (f);
			return path;
		}
	}
	char *local = name[0] == '/'? xstrdup (cc, name):
		xasprintf (cc, "%s/%s", cc->cwd, name);
	FILE *f = fopen (local, "r");
	if (f) {
		fclose (f);
		return local;
	}
	for (AholyIncDir *d = cc->inc_dirs; d; d = d->next) {
		char *path = xasprintf (cc, "%s/%s", d->dir, name);
		f = fopen (path, "r");
		if (f) {
			fclose (f);
			return path;
		}
	}
	return NULL;
}

Token *lex_file(Aholyc *cc, const char *path) {
	char *src = read_source (cc, path);
	if (!src) {
		error (cc, "cannot open '%s'", path);
	}
	Token *t = tokenize (cc, src, xstrdup (cc, path));
	return lex_preprocess (cc, t);
}

/* Tokenize an in-memory buffer (prelude); chain_after appended at EOF. */
Token *lex_string(Aholyc *cc, const char *src, const char *fake_name,
		Token *chain_after) {
	Token *pre = lex_preprocess (cc, tokenize (cc, src, fake_name));
	return chain_after? token_join (pre, chain_after): pre;
}

/* append list b after a, dropping a's EOF */
Token *token_join(Token *a, Token *b) {
	if (!a || a->kind == TK_EOF) {
		return b;
	}
	Token *q = a;
	while (q->next && q->next->kind != TK_EOF) {
		q = q->next;
	}
	q->next = b;
	return a;
}
