/* aholyc lexer + token-level preprocessor (#include, #define, #ifdef) */
#include "aholyc.h"
#include <unistd.h>
#include <sys/stat.h>

struct AholyIncDir { AholyIncDir *next; char *dir; };

struct AholyMacro { AholyMacro *next; char *name; Token *body; };

typedef struct {
	Aholyc *cc;
	const char *file;
	int line;
} Tokenizer;

static void clear_config(Aholyc *cc) {
	aholyc_i_xfree_to (cc, NULL);
	cc->inc_dirs = NULL;
	cc->macros = NULL;
	cc->cwd = NULL;
	cc->nccflags = 0;
}

void aholyc_i_lex_reset(Aholyc *cc) {
	clear_config (cc);
	cc->verbose = cc->keep = false;
	cc->use_hints = true;
	char *cwd = getcwd (NULL, 0);
	if (cwd) aholyc_i_cleanup_push (cc, free, cwd);
	cc->cwd = aholyc_i_xstrdup (cc, cwd? cwd: ".");
	if (cwd) aholyc_i_cleanup_pop (cc);
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
	return path[0] == '/'? aholyc_i_xstrdup (cc, path):
		aholyc_i_xasprintf (cc, "%s/%s", cc->cwd, path);
}

bool aholyc_i_lex_set_cwd(Aholyc *cc, const char *path) {
	char *dir = from_cwd (cc, path);
	struct stat st;
	if (stat (dir, &st) || !S_ISDIR (st.st_mode)) {
		return false;
	}
	cc->cwd = dir;
	return true;
}

void aholyc_i_lex_add_include_dir(Aholyc *cc, const char *dir) {
	AholyIncDir *d = aholyc_i_xmalloc (cc, sizeof(*d));
	d->dir = from_cwd (cc, dir);
	d->next = cc->inc_dirs;
	cc->inc_dirs = d;
}

static AholyMacro *find_macro(Aholyc *cc, const char *name) {
	for (AholyMacro *m = cc->macros; m; m = m->next) {
		if (!strcmp(m->name, name)) {
			return m;
		}
	}
	return NULL;
}

static Token *new_token(Tokenizer *tz, TokenKind kind) {
	Token *t = aholyc_i_xcalloc (tz->cc, 1, sizeof(Token));
	t->kind = kind;
	t->cc = tz->cc;
	t->file = (char *)tz->file;
	t->line = tz->line;
	return t;
}

static bool ident_start(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; }
static bool ident_cont(int c) { return ident_start (c) || (c >= '0' && c <= '9'); }
static bool comment_space(int c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; }
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
		if (n == 5 && !strncmp (p + 1, "align", 5)) {
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
					aholyc_i_error (cc, "%s:%d: @align must be a power of two", fname, line);
				}
				if (q < end && !comment_space ((unsigned char)*q) && *q != '@') {
					aholyc_i_error (cc, "%s:%d: malformed @align hint", fname, line);
				}
			}
			if (*pending_align) {
				aholyc_i_error (cc, "%s:%d: duplicate @align hint before declaration", fname, line);
			}
			*pending_align = a;
			p = q - 1;
			continue;
		}
		unsigned hint = n == 6 && !strncmp (p + 1, "inline", 6)? HINT_INLINE:
			n == 8 && !strncmp (p + 1, "noinline", 8)? HINT_NOINLINE: 0;
		if (hint) {
			if (*pending_hints) {
					aholyc_i_error (cc, "%s:%d: duplicate hint before declaration", fname, line);
			}
			*pending_hints |= hint;
			p = q - 1;
			continue;
		}
		if (n != 4 || strncmp (p + 1, "bits", 4)) {
			continue;
		}
		q = skip_comment_space (q, end);
		if (q == end || *q++ != '=') {
			aholyc_i_error (cc, "%s:%d: malformed @bits hint (expected @bits=N)", fname, line);
		}
		q = skip_comment_space (q, end);
		if (q == end || *q < '0' || *q > '9') {
			aholyc_i_error (cc, "%s:%d: malformed @bits hint (expected @bits=N)", fname, line);
		}
		int width = 0;
		while (q < end && *q >= '0' && *q <= '9') {
			if (width <= 128) {
				width = width * 10 + (*q - '0');
			}
			q++;
		}
		if (q < end && !comment_space ((unsigned char)*q) && *q != '@') {
			aholyc_i_error (cc, "%s:%d: malformed @bits hint (expected @bits=N)", fname, line);
		}
		if (width < 1 || width > 128) {
			aholyc_i_error (cc, "%s:%d: @bits width must be between 1 and 128", fname, line);
		}
		if (*pending_bits) {
			aholyc_i_error (cc, "%s:%d: duplicate @bits hint before declaration", fname, line);
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
static Token *tokenize(Aholyc *cc, const char *src, const char *fname) {
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
			t->str = aholyc_i_xmalloc (cc, t->len + 1);
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
			char *buf = aholyc_i_xmalloc (cc, strlen (p) + 1);
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
				aholyc_i_error (cc, "%s:%d: unterminated string", fname, tz.line);
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
				aholyc_i_error (cc, "%s:%d: unterminated char constant", fname, tz.line);
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
				aholyc_i_error (cc, "%s:%d: stray character '%c' (0x%02x)",
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

static bool tok_is(Token *t, const char *s) {
	return (t->kind == TK_ID || t->kind == TK_PUNCT) && t->str && !strcmp (t->str, s);
}

static char *search_include(Aholyc *cc, const char *name,
		const char *from_file) {
	/* relative to including file first */
	const char *slash = from_file? strrchr (from_file, '/'): NULL;
	if (slash) {
		char *dir = aholyc_i_xstrdup (cc, from_file);
		dir[slash - from_file] = 0;
		char *path = aholyc_i_xasprintf (cc, "%s/%s", dir, name);
		FILE *f = fopen (path, "r");
		if (f) {
			fclose (f);
			return path;
		}
	}
	char *local = name[0] == '/'? aholyc_i_xstrdup (cc, name):
		aholyc_i_xasprintf (cc, "%s/%s", cc->cwd, name);
	FILE *f = fopen (local, "r");
	if (f) {
		fclose (f);
		return local;
	}
	for (AholyIncDir *d = cc->inc_dirs; d; d = d->next) {
		char *path = aholyc_i_xasprintf (cc, "%s/%s", d->dir, name);
		f = fopen (path, "r");
		if (f) {
			fclose (f);
			return path;
		}
	}
	return NULL;
}

static Token *copy_token(Aholyc *cc, Token *t) {
	Token *n = aholyc_i_xmalloc (cc, sizeof(Token));
	*n = *t;
	n->next = NULL;
	return n;
}

static Token *new_eof(Aholyc *cc, Token *near) {
	Token *t = aholyc_i_xcalloc (cc, 1, sizeof(*t));
	t->kind = TK_EOF;
	t->cc = cc;
	if (near) {
		t->file = near->file;
		t->line = near->line;
	}
	return t;
}

static void inherit_hint(Aholyc *cc, Token *src, Token *dst) {
	if (!dst) {
		return;
	}
	if (src->hint_bits) {
		if (dst->hint_bits) {
			aholyc_i_error_tok (cc, src, "duplicate @bits hint on declaration");
		}
		dst->hint_bits = src->hint_bits;
	}
	if (src->hint_align) {
		if (dst->hint_align) {
			aholyc_i_error_tok (cc, src, "duplicate @align hint on declaration");
		}
		dst->hint_align = src->hint_align;
	}
	if (src->hints) {
		unsigned funcs = HINT_INLINE | HINT_NOINLINE;
		if (src->hints & funcs && dst->hints & funcs) {
			aholyc_i_error_tok (cc, src, "duplicate hint on declaration");
		}
		dst->hints |= src->hints;
	}
}

/* skip tokens until matching #else/#endif; nest counts inner #if* */
static Token *skip_cond(Token *t, bool *hit_else) {
	int depth = 0;
	while (t->kind != TK_EOF) {
		if (t->at_bol && tok_is (t, "#")) {
			Token *d = t->next;
			if (d->kind == TK_ID) {
				if (!strncmp (d->str, "if", 2)) {
					depth++;
				} else if (!strcmp (d->str, "endif")) {
					if (depth == 0) {
						*hit_else = false;
						return d->next;
					}
					depth--;
				} else if (!strcmp (d->str, "else") && depth == 0) {
					*hit_else = true;
					return d->next;
				}
			}
		}
		t = t->next;
	}
	return t;
}

/* Resolve directives and expand macros. Consumes raw list, returns clean list. */
Token *aholyc_i_lex_preprocess(Aholyc *cc, Token *tok) {
	Token head = {0};
	Token *cur = &head;
	int cond_depth = 0;

	while (tok && tok->kind != TK_EOF) {
		if (tok->at_bol && tok_is (tok, "#")) {
			Token *d = tok->next;
			int dline = tok->line;
			if (d->kind != TK_ID) {
				aholyc_i_error_tok (cc, tok, "invalid preprocessor directive");
			}
			if (!strcmp (d->str, "include")) {
				Token *f = d->next;
				if (f->kind != TK_STR) {
					aholyc_i_error_tok (cc, f, "#include expects \"file\" (HolyC has no <>)");
				}
				char *path = search_include (cc, f->str, f->file);
				if (!path) {
					aholyc_i_error_tok (cc, f, "cannot find include file \"%s\"", f->str);
				}
				char *src = aholyc_i_read_source (cc, path);
				if (!src) {
					aholyc_i_error_tok (cc, f, "cannot read \"%s\"", path);
				}
				Token *inc = tokenize (cc, src, path);
				/* splice: inc-list (minus EOF) then rest */
				Token *rest = f->next;
				Token *q = inc;
				if (q->kind == TK_EOF) {
					tok = rest;
					continue;
				}
				while (q->next && q->next->kind != TK_EOF) q = q->next;
				q->next = rest;
				tok = inc;
				continue;
			}
			if (!strcmp (d->str, "define")) {
				Token *n = d->next;
				if (n->kind != TK_ID) {
					aholyc_i_error_tok (cc, n, "#define expects a name");
				}
				AholyMacro *m = find_macro (cc, n->str);
				if (!m) {
					m = aholyc_i_xcalloc (cc, 1, sizeof(*m));
					m->name = aholyc_i_xstrdup (cc, n->str);
					m->next = cc->macros;
					cc->macros = m;
				}
				m->body = NULL;
				Token *b = n->next;
				Token bh = {0};
				Token *bc = &bh;
				while (b->kind != TK_EOF && !b->at_bol && b->line == dline) {
					bc->next = copy_token (cc, b);
					bc = bc->next;
					b = b->next;
				}
				m->body = bh.next;
				tok = b;
				continue;
			}
			if (!strcmp (d->str, "undef")) {
				Token *n = d->next;
				AholyMacro *m = n->kind == TK_ID? find_macro (cc, n->str): NULL;
				if (m) {
					*m->name = 0; /* dead */
				}
				tok = n->next;
				continue;
			}
			if (!strcmp (d->str, "ifdef") || !strcmp (d->str, "ifndef")) {
				Token *n = d->next;
				if (n->kind != TK_ID) {
					aholyc_i_error_tok (cc, n, "%s expects a name", d->str);
				}
				bool defined = find_macro (cc, n->str) != NULL;
				bool live = strcmp (d->str, "ifdef")? !defined: defined;
				if (live) {
					cond_depth++;
					tok = n->next;
				} else {
					bool has_else;
					tok = skip_cond (n->next, &has_else);
					if (has_else) {
						cond_depth++;
					}
				}
				continue;
			}
			if (!strcmp (d->str, "else")) {
				if (cond_depth <= 0) {
					aholyc_i_error_tok (cc, d, "#else without #ifdef");
				}
				bool has_else;
				tok = skip_cond (d->next, &has_else);
				cond_depth--;
				continue;
			}
			if (!strcmp (d->str, "endif")) {
				if (cond_depth <= 0) {
					aholyc_i_error_tok (cc, d, "#endif without #ifdef");
				}
				cond_depth--;
				tok = d->next;
				continue;
			}
			if (!strcmp (d->str, "exe")) {
				/* compile-time execution: cut the {...} body out,
				 * run it (exe.c), splice its StreamPrint output in */
				Token *b = d->next;
				if (!tok_is (b, "{")) {
					aholyc_i_error_tok (cc, b, "#exe expects '{'");
				}
				Token *prev = b, *q = b->next;
				int depth = 1;
				while (q->kind != TK_EOF) {
					if (tok_is (q, "{")) {
						depth++;
					} else if (tok_is (q, "}") && --depth == 0) {
						break;
					}
					prev = q;
					q = q->next;
				}
				if (q->kind == TK_EOF) {
					aholyc_i_error_tok (cc, b, "unterminated #exe{}");
				}
				Token *rest = q->next;
				prev->next = new_eof (cc, prev);
				Token *body = prev == b? prev->next: b->next;
				/* per-block location macros, TempleOS style */
				aholyc_i_lex_define (cc, "__FILE__", aholyc_i_xasprintf (cc, "\"%s\"", d->file));
				char *dir = aholyc_i_xstrdup (cc, d->file);
				char *sl = strrchr (dir, '/');
				if (sl) {
					*sl = 0;
				} else {
					strcpy (dir, ".");
				}
				aholyc_i_lex_define (cc, "__DIR__", aholyc_i_xasprintf (cc, "\"%s\"", dir));
				char *out = aholyc_i_exe_run (cc, body, &rest);
				Token *inj = tokenize (cc, out, "<exe>");
				if (inj->kind == TK_EOF) {
					tok = rest;
				} else {
					Token *e = inj;
					while (e->next && e->next->kind != TK_EOF) {
						e = e->next;
					}
					e->next = rest;
					tok = inj;
				}
				continue;
			}
			/* TempleOS doc directives: ignore rest of line */
			if (!strcmp (d->str, "help_index") || !strcmp (d->str, "help_file")) {
				Token *b = d->next;
				while (b->kind != TK_EOF && b->line == dline && !b->at_bol) b = b->next;
				tok = b;
				continue;
			}
			aholyc_i_error_tok (cc, d, "unknown directive #%s", d->str);
		}
		if (tok->kind == TK_ID && !tok->no_expand) {
			AholyMacro *m = find_macro (cc, tok->str);
			if (m) {
				if (!m->body) {
					inherit_hint (cc, tok, tok->next);
					tok = tok->next;
					continue;
				}
				/* splice a copy of the body; guard self-reference */
				Token bh = {0};
				Token *bc = &bh;
				for (Token *b = m->body; b; b = b->next) {
					bc->next = copy_token (cc, b);
					bc->next->file = tok->file;
					bc->next->line = tok->line;
					if (b->kind == TK_ID && !strcmp (b->str, m->name)) {
						bc->next->no_expand = true;
					}
					bc = bc->next;
				}
				bc->next = tok->next;
				inherit_hint (cc, tok, bh.next);
				tok = bh.next;
				continue;
			}
		}
		cur->next = tok;
		cur = tok;
		Token *nx = tok->next;
		cur->next = NULL;
		tok = nx;
	}
	cur->next = tok? tok: new_eof (cc, cur == &head? NULL: cur);
	return head.next;
}

void aholyc_i_lex_define(Aholyc *cc, const char *name, const char *value) {
	AholyMacro *m = aholyc_i_xcalloc (cc, 1, sizeof(*m));
	m->name = aholyc_i_xstrdup (cc, name);
	if (value && *value) {
		Token *t = tokenize (cc, value, "<cmdline>");
		/* drop EOF */
		if (t->kind == TK_EOF) {
			t = NULL;
		} else {
			Token *q = t;
			while (q->next && q->next->kind != TK_EOF) q = q->next;
			q->next = NULL;
		}
		m->body = t;
	}
	m->next = cc->macros;
	cc->macros = m;
}

Token *aholyc_i_lex_file(Aholyc *cc, const char *path) {
	char *src = aholyc_i_read_source (cc, path);
	if (!src) {
		aholyc_i_error (cc, "cannot open '%s'", path);
	}
	Token *t = tokenize (cc, src, aholyc_i_xstrdup (cc, path));
	return aholyc_i_lex_preprocess (cc, t);
}

/* Tokenize an in-memory buffer (prelude); chain_after appended at EOF. */
Token *aholyc_i_lex_string(Aholyc *cc, const char *src, const char *fake_name,
		Token *chain_after) {
	Token *pre = aholyc_i_lex_preprocess (cc, tokenize (cc, src, fake_name));
	return chain_after? aholyc_i_token_join (pre, chain_after): pre;
}

/* append list b after a, dropping a's EOF */
Token *aholyc_i_token_join(Token *a, Token *b) {
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
