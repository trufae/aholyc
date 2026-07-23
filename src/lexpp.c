/* aholyc token-level preprocessor: directives (#include, #define, #undef,
 * #if/#ifdef/#ifndef/#else/#endif, #exe), object-macro expansion, and #if
 * constant-expression evaluation. Split out of lex.c; it shares the
 * tokenizer (tokenize) and include-path search (search_include). */
#include "aholyc.h"

struct AholyMacro { AholyMacro *next; char *name; Token *body; };

static AholyMacro *find_macro(Aholyc *cc, const char *name) {
	for (AholyMacro *m = cc->macros; m; m = m->next) {
		if (!strcmp(m->name, name)) {
			return m;
		}
	}
	return NULL;
}

static bool tok_is(Token *t, const char *s) {
	return (t->kind == TK_ID || t->kind == TK_PUNCT) && t->str && !strcmp (t->str, s);
}

static Token *copy_token(Aholyc *cc, Token *t) {
	Token *n = xmalloc (cc, sizeof(Token));
	*n = *t;
	n->next = NULL;
	return n;
}

static Token *new_eof(Aholyc *cc, Token *near) {
	Token *t = xcalloc (cc, 1, sizeof(*t));
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

/* ---- #if constant-expression evaluation (token-level) ---------------- */

/* Object-macro-expand a line's tokens for #if, resolving defined(X)/defined X
 * (whose operand is never expanded) to 1/0. Returns an EOF-terminated list. */
static Token *pp_expand(Aholyc *cc, Token *w) {
	Token head = {0};
	Token *cur = &head;
	while (w && w->kind != TK_EOF) {
		if (w->kind == TK_ID && !w->no_expand &&
		    !strcmp (w->str, "defined")) {
			Token *a = w->next;
			bool paren = tok_is (a, "(");
			if (paren) a = a->next;
			if (a->kind != TK_ID) {
				error_tok (cc, w, "#if: defined expects a name");
			}
			bool def = find_macro (cc, a->str) != NULL;
			Token *after = a->next;
			if (paren) {
				if (!tok_is (after, ")")) {
					error_tok (cc, w, "#if: defined missing ')'");
				}
				after = after->next;
			}
			Token *nt = copy_token (cc, w);
			nt->kind = TK_NUM;
			nt->ival = def;
			nt->str = NULL;
			cur->next = nt;
			cur = nt;
			w = after;
			continue;
		}
		if (w->kind == TK_ID && !w->no_expand) {
			AholyMacro *m = find_macro (cc, w->str);
			if (m) {
				Token bh = {0};
				Token *bc = &bh;
				for (Token *b = m->body; b; b = b->next) {
					bc->next = copy_token (cc, b);
					if (b->kind == TK_ID && !strcmp (b->str, m->name)) {
						bc->next->no_expand = true;
					}
					bc = bc->next;
				}
				bc->next = w->next;
				w = bh.next? bh.next: w->next;
				continue;
			}
		}
		Token *nx = w->next;
		cur->next = w;
		cur = w;
		cur->next = NULL;
		w = nx;
	}
	cur->next = w? w: new_eof (cc, NULL);
	return head.next;
}

/* Recursive-descent integer evaluator in HolyC precedence (shifts bind
 * tighter than *, which binds tighter than the bitwise ops; doc/language.md).
 * A residual identifier is 0 (C-style). Comparisons are left-associative,
 * i.e. not chained. */
static int64_t pp_or(Aholyc *cc, Token **pp);

static int64_t pp_prim(Aholyc *cc, Token **pp) {
	Token *t = *pp;
	if (tok_is (t, "(")) {
		*pp = t->next;
		int64_t v = pp_or (cc, pp);
		if (!tok_is (*pp, ")")) {
			error_tok (cc, *pp, "#if: expected ')'");
		}
		*pp = (*pp)->next;
		return v;
	}
	if (t->kind == TK_NUM || t->kind == TK_CHR) {
		*pp = t->next;
		return t->ival;
	}
	if (t->kind == TK_ID) {   /* undefined name */
		*pp = t->next;
		return 0;
	}
	error_tok (cc, t, "#if: malformed expression");
	return 0;
}

static int64_t pp_unary(Aholyc *cc, Token **pp) {
	if (tok_is (*pp, "!")) { *pp = (*pp)->next; return !pp_unary (cc, pp); }
	if (tok_is (*pp, "~")) { *pp = (*pp)->next; return ~pp_unary (cc, pp); }
	if (tok_is (*pp, "-")) { *pp = (*pp)->next; return -pp_unary (cc, pp); }
	if (tok_is (*pp, "+")) { *pp = (*pp)->next; return pp_unary (cc, pp); }
	return pp_prim (cc, pp);
}

static int64_t pp_shift(Aholyc *cc, Token **pp) {
	int64_t v = pp_unary (cc, pp);
	for (;;) {
		if (tok_is (*pp, "<<")) { *pp = (*pp)->next; v <<= pp_unary (cc, pp); }
		else if (tok_is (*pp, ">>")) { *pp = (*pp)->next; v >>= pp_unary (cc, pp); }
		else return v;
	}
}

static int64_t pp_mul(Aholyc *cc, Token **pp) {
	int64_t v = pp_shift (cc, pp);
	for (;;) {
		if (tok_is (*pp, "*")) { *pp = (*pp)->next; v *= pp_shift (cc, pp); }
		else if (tok_is (*pp, "/")) {
			*pp = (*pp)->next;
			int64_t d = pp_shift (cc, pp);
			if (!d) error_tok (cc, *pp, "#if: division by zero");
			v /= d;
		} else if (tok_is (*pp, "%")) {
			*pp = (*pp)->next;
			int64_t d = pp_shift (cc, pp);
			if (!d) error_tok (cc, *pp, "#if: division by zero");
			v %= d;
		} else return v;
	}
}

static int64_t pp_band(Aholyc *cc, Token **pp) {
	int64_t v = pp_mul (cc, pp);
	while (tok_is (*pp, "&")) { *pp = (*pp)->next; v &= pp_mul (cc, pp); }
	return v;
}

static int64_t pp_bxor(Aholyc *cc, Token **pp) {
	int64_t v = pp_band (cc, pp);
	while (tok_is (*pp, "^")) { *pp = (*pp)->next; v ^= pp_band (cc, pp); }
	return v;
}

static int64_t pp_bor(Aholyc *cc, Token **pp) {
	int64_t v = pp_bxor (cc, pp);
	while (tok_is (*pp, "|")) { *pp = (*pp)->next; v |= pp_bxor (cc, pp); }
	return v;
}

static int64_t pp_addsub(Aholyc *cc, Token **pp) {
	int64_t v = pp_bor (cc, pp);
	for (;;) {
		if (tok_is (*pp, "+")) { *pp = (*pp)->next; v += pp_bor (cc, pp); }
		else if (tok_is (*pp, "-")) { *pp = (*pp)->next; v -= pp_bor (cc, pp); }
		else return v;
	}
}

static int64_t pp_rel(Aholyc *cc, Token **pp) {
	int64_t v = pp_addsub (cc, pp);
	for (;;) {
		if (tok_is (*pp, "<")) { *pp = (*pp)->next; v = v < pp_addsub (cc, pp); }
		else if (tok_is (*pp, ">")) { *pp = (*pp)->next; v = v > pp_addsub (cc, pp); }
		else if (tok_is (*pp, "<=")) { *pp = (*pp)->next; v = v <= pp_addsub (cc, pp); }
		else if (tok_is (*pp, ">=")) { *pp = (*pp)->next; v = v >= pp_addsub (cc, pp); }
		else return v;
	}
}

static int64_t pp_eq(Aholyc *cc, Token **pp) {
	int64_t v = pp_rel (cc, pp);
	for (;;) {
		if (tok_is (*pp, "==")) { *pp = (*pp)->next; v = v == pp_rel (cc, pp); }
		else if (tok_is (*pp, "!=")) { *pp = (*pp)->next; v = v != pp_rel (cc, pp); }
		else return v;
	}
}

static int64_t pp_logand(Aholyc *cc, Token **pp) {
	int64_t v = pp_eq (cc, pp);
	while (tok_is (*pp, "&&")) { *pp = (*pp)->next; int64_t r = pp_eq (cc, pp); v = v && r; }
	return v;
}

static int64_t pp_logxor(Aholyc *cc, Token **pp) {
	int64_t v = pp_logand (cc, pp);
	while (tok_is (*pp, "^^")) { *pp = (*pp)->next; int64_t r = pp_logand (cc, pp); v = !v != !r; }
	return v;
}

static int64_t pp_or(Aholyc *cc, Token **pp) {
	int64_t v = pp_logxor (cc, pp);
	while (tok_is (*pp, "||")) { *pp = (*pp)->next; int64_t r = pp_logxor (cc, pp); v = v || r; }
	return v;
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
Token *lex_preprocess(Aholyc *cc, Token *tok) {
	Token head = {0};
	Token *cur = &head;
	int cond_depth = 0;

	while (tok && tok->kind != TK_EOF) {
		if (tok->at_bol && tok_is (tok, "#")) {
			Token *d = tok->next;
			int dline = tok->line;
			if (d->kind != TK_ID) {
				error_tok (cc, tok, "invalid preprocessor directive");
			}
			if (!strcmp (d->str, "include")) {
				Token *f = d->next;
				if (f->kind != TK_STR) {
					error_tok (cc, f, "#include expects \"file\" (HolyC has no <>)");
				}
				char *path = search_include (cc, f->str, f->file);
				if (!path) {
					error_tok (cc, f, "cannot find include file \"%s\"", f->str);
				}
				char *src = read_source (cc, path);
				if (!src) {
					error_tok (cc, f, "cannot read \"%s\"", path);
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
					error_tok (cc, n, "#define expects a name");
				}
				AholyMacro *m = find_macro (cc, n->str);
				if (!m) {
					m = xcalloc (cc, 1, sizeof(*m));
					m->name = xstrdup (cc, n->str);
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
			if (!strcmp (d->str, "if")) {
				/* collect the expression (rest of the line), expand and
				 * evaluate it as a constant; nonzero keeps the branch */
				Token lh = {0};
				Token *lc = &lh;
				Token *b = d->next;
				while (b->kind != TK_EOF && !b->at_bol && b->line == dline) {
					lc->next = copy_token (cc, b);
					lc = lc->next;
					b = b->next;
				}
				if (!lh.next) {
					error_tok (cc, d, "#if expects an expression");
				}
				lc->next = new_eof (cc, d);
				Token *ex = pp_expand (cc, lh.next);
				int64_t val = pp_or (cc, &ex);
				if (ex->kind != TK_EOF) {
					error_tok (cc, ex, "#if: unexpected token in expression");
				}
				if (val) {
					cond_depth++;
					tok = b;
				} else {
					bool has_else;
					tok = skip_cond (b, &has_else);
					if (has_else) {
						cond_depth++;
					}
				}
				continue;
			}
			if (!strcmp (d->str, "ifdef") || !strcmp (d->str, "ifndef")) {
				Token *n = d->next;
				if (n->kind != TK_ID) {
					error_tok (cc, n, "%s expects a name", d->str);
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
					error_tok (cc, d, "#else without #ifdef");
				}
				bool has_else;
				tok = skip_cond (d->next, &has_else);
				cond_depth--;
				continue;
			}
			if (!strcmp (d->str, "endif")) {
				if (cond_depth <= 0) {
					error_tok (cc, d, "#endif without #ifdef");
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
					error_tok (cc, b, "#exe expects '{'");
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
					error_tok (cc, b, "unterminated #exe{}");
				}
				Token *rest = q->next;
				prev->next = new_eof (cc, prev);
				Token *body = prev == b? prev->next: b->next;
				/* per-block location macros, TempleOS style */
				lex_define (cc, "__FILE__", xasprintf (cc, "\"%s\"", d->file));
				char *dir = xstrdup (cc, d->file);
				char *sl = strrchr (dir, '/');
				if (sl) {
					*sl = 0;
				} else {
					strcpy (dir, ".");
				}
				lex_define (cc, "__DIR__", xasprintf (cc, "\"%s\"", dir));
				char *out = exe_run (cc, body, &rest);
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
			error_tok (cc, d, "unknown directive #%s", d->str);
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

void lex_define(Aholyc *cc, const char *name, const char *value) {
	/* reuse a live entry so redefinition replaces instead of stacking
	 * (#undef kills one entry; stacking would resurrect the old one) */
	AholyMacro *m = find_macro (cc, name);
	if (!m) {
		m = xcalloc (cc, 1, sizeof(*m));
		m->name = xstrdup (cc, name);
		m->next = cc->macros;
		cc->macros = m;
	}
	m->body = NULL;
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
}
