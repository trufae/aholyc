/* aholyc lexer: tokenizer, include-path search, and compiler-instance
 * lifecycle. Comment hints and the token-level preprocessor live in
 * lexhints.c and lexpp.c, respectively. */
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
	/* expose HolyC platform names, rather than the compiler's C macros */
#if defined(__x86_64__) || defined(_M_X64)
	lex_define (cc, "IS_X86_64", "1");
#elif defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
	lex_define (cc, "IS_ARM_64", "1");
#elif defined(__powerpc__) || defined(__powerpc64__) || defined(__ppc__) || \
	defined(__ppc64__) || defined(_ARCH_PPC) || defined(_ARCH_PPC64)
	lex_define (cc, "IS_POWERPC", "1");
#elif defined(__riscv)
	lex_define (cc, "IS_RISCV", "1");
#elif defined(__mips__) || defined(__mips) || defined(_MIPS_ARCH)
	lex_define (cc, "IS_MIPS", "1");
#elif defined(__arm__) || defined(__thumb__) || defined(_M_ARM)
	lex_define (cc, "IS_ARM_32", "1");
#endif
#ifdef __APPLE__
	lex_define (cc, "IS_MACOS", "1");
#elif defined(__linux__)
	lex_define (cc, "IS_LINUX", "1");
#elif defined(__NetBSD__)
	lex_define (cc, "IS_NETBSD", "1");
#elif defined(__OpenBSD__)
	lex_define (cc, "IS_OPENBSD", "1");
#elif defined(__FreeBSD__)
	lex_define (cc, "IS_FREEBSD", "1");
#endif
#if defined(__unix__) || defined(__unix) || defined(__APPLE__) || defined(__linux__) || \
	defined(__NetBSD__) || defined(__OpenBSD__) || defined(__FreeBSD__)
	lex_define (cc, "IS_UNIX", "1");
#endif
#ifdef _WIN32
	lex_define (cc, "IS_WINDOWS", "1");
#endif
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
	LexHints pending = {0};

	while (*p) {
		if (*p == '\n') { tz.line++; bol = true; space = false; p++; continue; }
		if (*p == ' ' || *p == '\t' || *p == '\r') { space = true; p++; continue; }
		if (p[0] == '/' && p[1] == '/') {
			int line = tz.line;
			const char *start = p + 2;
			p = start;
			while (*p && *p != '\n') p++;
			lex_hints_scan_comment (cc, &pending, start, p, fname, line);
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
			lex_hints_scan_comment (cc, &pending, start, p, fname, line);
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
		lex_hints_apply (&pending, t);
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
