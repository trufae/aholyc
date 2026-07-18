/* ahc lexer + token-level preprocessor (#include, #define, #ifdef) */
#include "ahc.h"

typedef struct IncDir IncDir;
struct IncDir { IncDir *next; const char *dir; };
static IncDir *inc_dirs;

typedef struct Macro Macro;
struct Macro { Macro *next; char *name; Token *body; bool expanding; };
static Macro *macros;

static const char *cur_file;
static int cur_line;

void lex_add_include_dir(const char *dir) {
	IncDir *d = xmalloc(sizeof(*d));
	d->dir = xstrdup(dir);
	d->next = inc_dirs;
	inc_dirs = d;
}

static Macro *find_macro(const char *name) {
	for (Macro *m = macros; m; m = m->next) {
		if (!strcmp(m->name, name)) {
			return m;
		}
	}
	return NULL;
}

static Token *new_token(TokenKind kind) {
	Token *t = xcalloc(1, sizeof(Token));
	t->kind = kind;
	t->file = (char *)cur_file;
	t->line = cur_line;
	return t;
}

static bool ident_start(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; }
static bool ident_cont(int c) { return ident_start (c) || (c >= '0' && c <= '9'); }

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

static const char *puncts[] = {
	"<<=", ">>=", "...",
	"==", "!=", "<=", ">=", "&&", "||", "^^", "<<", ">>",
	"+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "++", "--", "->", "$$",
	"+", "-", "*", "/", "%", "&", "|", "^", "~", "!", "<", ">", "=",
	"(", ")", "{", "}", "[", "]", ",", ";", ":", ".", "`", "#", "?",
	NULL
};

/* Tokenize a NUL-terminated buffer into a raw token list (directives kept). */
static Token *tokenize(const char *src, const char *fname) {
	const char *save_file = cur_file;
	int save_line = cur_line;
	cur_file = fname;
	cur_line = 1;

	Token head = {0};
	Token *cur = &head;
	const char *p = src;
	bool bol = true, space = false;

	while (*p) {
		if (*p == '\n') { cur_line++; bol = true; space = false; p++; continue; }
		if (*p == ' ' || *p == '\t' || *p == '\r') { space = true; p++; continue; }
		if (p[0] == '/' && p[1] == '/') {
			while (*p && *p != '\n') p++;
			continue;
		}
		if (p[0] == '/' && p[1] == '*') {
			p += 2;
			while (*p && !(p[0] == '*' && p[1] == '/')) {
				if (*p == '\n') cur_line++;
				p++;
			}
			if (*p) p += 2;
			space = true;
			continue;
		}
		Token *t = NULL;
		if (ident_start (*p)) {
			const char *s = p;
			while (ident_cont (*p)) p++;
			t = new_token (TK_ID);
			t->len = p - s;
			t->str = xmalloc (t->len + 1);
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
				t = new_token (TK_NUM);
				t->ival = (int64_t)v;
			} else if (p[0] == '0' && (p[1] == 'b' || p[1] == 'B')) {
				uint64_t v = 0;
				p += 2;
				while (*p == '0' || *p == '1' || *p == '_') {
					if (*p != '_') v = v * 2 + (*p - '0');
					p++;
				}
				t = new_token (TK_NUM);
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
					t = new_token (TK_FNUM);
					t->fval = strtod (s, NULL);
				} else {
					t = new_token (TK_NUM);
					t->ival = (int64_t)strtoull (s, NULL, 10);
				}
			}
		} else if (*p == '"') {
			/* string literal; adjacent strings are concatenated later */
			p++;
			char *buf = xmalloc (strlen (p) + 1);
			int n = 0;
			while (*p && *p != '"') {
				if (*p == '\\') {
					p++;
					buf[n++] = (char)read_escape (&p);
				} else {
					if (*p == '\n') cur_line++;
					buf[n++] = *p++;
				}
			}
			if (*p != '"') {
				error ("%s:%d: unterminated string", fname, cur_line);
			}
			p++;
			buf[n] = 0; /* NUL-terminate: #include and #exe read str as C string */
			t = new_token (TK_STR);
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
				error ("%s:%d: unterminated char constant", fname, cur_line);
			}
			p++;
			t = new_token (TK_CHR);
			t->ival = (int64_t)v;
			t->len = n; /* 0 for the magic '' */
		} else {
			for (int i = 0; puncts[i]; i++) {
				size_t l = strlen (puncts[i]);
				if (!strncmp (p, puncts[i], l)) {
					t = new_token (TK_PUNCT);
					t->str = (char *)puncts[i];
					t->len = l;
					p += l;
					break;
				}
			}
			if (!t) {
				error ("%s:%d: stray character '%c' (0x%02x)", fname, cur_line, *p, (unsigned char)*p);
			}
		}
		t->at_bol = bol;
		t->has_space = space;
		bol = false;
		space = false;
		cur->next = t;
		cur = t;
	}
	Token *eof = new_token (TK_EOF);
	eof->at_bol = true;
	cur->next = eof;
	cur_file = save_file;
	cur_line = save_line;
	return head.next;
}

static bool tok_is(Token *t, const char *s) {
	return (t->kind == TK_ID || t->kind == TK_PUNCT) && t->str && !strcmp (t->str, s);
}

static char *search_include(const char *name, const char *from_file) {
	/* relative to including file first */
	const char *slash = from_file? strrchr (from_file, '/'): NULL;
	if (slash) {
		char *dir = xstrdup (from_file);
		dir[slash - from_file] = 0;
		char *path = xasprintf ("%s/%s", dir, name);
		free (dir);
		FILE *f = fopen (path, "r");
		if (f) {
			fclose (f);
			return path;
		}
		free (path);
	}
	FILE *f = fopen (name, "r");
	if (f) {
		fclose (f);
		return xstrdup (name);
	}
	for (IncDir *d = inc_dirs; d; d = d->next) {
		char *path = xasprintf ("%s/%s", d->dir, name);
		f = fopen (path, "r");
		if (f) {
			fclose (f);
			return path;
		}
		free (path);
	}
	return NULL;
}

static Token *copy_token(Token *t) {
	Token *n = xmalloc (sizeof(Token));
	*n = *t;
	n->next = NULL;
	return n;
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
static Token *preprocess(Token *tok) {
	Token head = {0};
	Token *cur = &head;
	int cond_depth = 0;

	while (tok && tok->kind != TK_EOF) {
		if (tok->at_bol && tok_is (tok, "#")) {
			Token *d = tok->next;
			int dline = tok->line;
			if (d->kind != TK_ID) {
				error_tok (tok, "invalid preprocessor directive");
			}
			if (!strcmp (d->str, "include")) {
				Token *f = d->next;
				if (f->kind != TK_STR) {
					error_tok (f, "#include expects \"file\" (HolyC has no <>)");
				}
				char *path = search_include (f->str, f->file);
				if (!path) {
					error_tok (f, "cannot find include file \"%s\"", f->str);
				}
				char *src = read_source (path);
				if (!src) {
					error_tok (f, "cannot read \"%s\"", path);
				}
				Token *inc = tokenize (src, path);
				free (src);
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
					error_tok (n, "#define expects a name");
				}
				Macro *m = find_macro (n->str);
				if (!m) {
					m = xcalloc (1, sizeof(*m));
					m->name = xstrdup (n->str);
					m->next = macros;
					macros = m;
				}
				m->body = NULL;
				Token *b = n->next;
				Token bh = {0};
				Token *bc = &bh;
				while (b->kind != TK_EOF && !b->at_bol && b->line == dline) {
					bc->next = copy_token (b);
					bc = bc->next;
					b = b->next;
				}
				m->body = bh.next;
				tok = b;
				continue;
			}
			if (!strcmp (d->str, "undef")) {
				Token *n = d->next;
				Macro *m = n->kind == TK_ID? find_macro (n->str): NULL;
				if (m) {
					m->name = (char *)""; /* dead */
				}
				tok = n->next;
				continue;
			}
			if (!strcmp (d->str, "ifdef") || !strcmp (d->str, "ifndef")) {
				Token *n = d->next;
				if (n->kind != TK_ID) {
					error_tok (n, "%s expects a name", d->str);
				}
				bool defined = find_macro (n->str) != NULL;
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
					error_tok (d, "#else without #ifdef");
				}
				bool has_else;
				tok = skip_cond (d->next, &has_else);
				cond_depth--;
				continue;
			}
			if (!strcmp (d->str, "endif")) {
				if (cond_depth <= 0) {
					error_tok (d, "#endif without #ifdef");
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
					error_tok (b, "#exe expects '{'");
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
					error_tok (b, "unterminated #exe{}");
				}
				Token *rest = q->next;
				prev->next = new_token (TK_EOF);
				Token *body = prev == b? prev->next: b->next;
				/* per-block location macros, TempleOS style */
				lex_define ("__FILE__", xasprintf ("\"%s\"", d->file));
				char *dir = xstrdup (d->file);
				char *sl = strrchr (dir, '/');
				if (sl) {
					*sl = 0;
				} else {
					strcpy (dir, ".");
				}
				lex_define ("__DIR__", xasprintf ("\"%s\"", dir));
				free (dir);
				char *out = exe_run (body, &rest);
				Token *inj = tokenize (out, "<exe>");
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
			error_tok (d, "unknown directive #%s", d->str);
		}
		if (tok->kind == TK_ID && !tok->no_expand) {
			Macro *m = find_macro (tok->str);
			if (m) {
				if (!m->body) {
					tok = tok->next;
					continue;
				}
				/* splice a copy of the body; guard self-reference */
				Token bh = {0};
				Token *bc = &bh;
				for (Token *b = m->body; b; b = b->next) {
					bc->next = copy_token (b);
					bc->next->file = tok->file;
					bc->next->line = tok->line;
					if (b->kind == TK_ID && !strcmp (b->str, m->name)) {
						bc->next->no_expand = true;
					}
					bc = bc->next;
				}
				bc->next = tok->next;
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
	cur->next = tok? tok: new_token (TK_EOF);
	return head.next;
}

void lex_define(const char *name, const char *value) {
	Macro *m = xcalloc (1, sizeof(*m));
	m->name = xstrdup (name);
	if (value && *value) {
		cur_file = "<cmdline>";
		cur_line = 1;
		Token *t = tokenize (value, "<cmdline>");
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
	m->next = macros;
	macros = m;
}

Token *lex_file(const char *path) {
	char *src = read_source (path);
	if (!src) {
		error ("cannot open '%s'", path);
	}
	Token *t = tokenize (src, xstrdup (path));
	free (src);
	return preprocess (t);
}

/* Tokenize an in-memory buffer (prelude); chain_after appended at EOF. */
Token *lex_string(const char *src, const char *fake_name, Token *chain_after) {
	Token *t = tokenize (src, fake_name);
	Token *pre = preprocess (t);
	return chain_after? token_join (pre, chain_after): pre;
}

/* Preprocess an already-tokenized list (exe.c: #exe block bodies are
 * expanded only after the exe API macros have been defined). */
Token *lex_preprocess(Token *raw) {
	return preprocess (raw);
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
