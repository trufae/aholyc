/* aholyc JavaScript backend. Native JS is used unless a function needs goto. */
#include "aholyc.h"
#include <unistd.h>
#include <sys/stat.h>

typedef struct {
	StrBuf out;
	bool term;
} Blk;

typedef struct { const char *name; int blk; } LabMap;

/* rt.js is split into chunks by '//@ name dep...' markers; only chunks
 * transitively referenced by the emitted program are shipped. */
typedef struct {
	char text[256];
	char *name;
	char *deps[12];
	int ndeps;
	const char *src;
	size_t len;
	bool inc;
} RtChunk;

typedef struct {
	Aholyc *cc;
	Program *prog;
	FILE *out;
	Blk blocks[1024];
	LabMap lmap[512];
	RtChunk chunks[160];
	long umap[65536];
	long str_addr[65536];
	int nblocks, cur_blk, nlmap, nchunks;
	const char *core_src;
	size_t core_len;
} JsGen;

typedef struct { FILE *file; char **buf; } MemStream;

static void cleanup_memstream(void *arg) {
	MemStream *m = arg;
	if (m->file) fclose (m->file);
	free (*m->buf);
}

static int new_block(JsGen *g) {
	if (g->nblocks >= 1024) {
		aholyc_i_error (g->cc, "js backend: too many blocks");
	}
	memset (&g->blocks[g->nblocks], 0, sizeof(Blk));
	aholyc_i_sb_init (&g->blocks[g->nblocks].out, g->cc);
	return g->nblocks++;
}

#define EMIT(...) aholyc_i_sb_printf (&g->blocks[g->cur_blk].out, __VA_ARGS__)

static void uid_set(JsGen *g, int uid, long val) {
	if (uid < 0 || uid >= 65536) {
		aholyc_i_error (g->cc, "js backend: uid out of range");
	}
	g->umap[uid] = val;
}

static long uid_get(JsGen *g, int uid) {
	if (uid >= 0 && uid < 65536 && g->umap[uid] >= 0) {
		return g->umap[uid];
	}
	aholyc_i_error (g->cc, "js backend: no layout for uid %d", uid);
	return 0;
}

static int label_block(JsGen *g, const char *name) {
	for (int i = 0; i < g->nlmap; i++) {
		if (!strcmp (g->lmap[i].name, name)) {
			return g->lmap[i].blk;
		}
	}
	if (g->nlmap >= 512) {
		aholyc_i_error (g->cc, "js backend: too many labels");
	}
	g->lmap[g->nlmap].name = name;
	g->lmap[g->nlmap].blk = new_block (g);
	return g->lmap[g->nlmap++].blk;
}

static void parse_rt_chunks(JsGen *g) {
	RtChunk *cur = NULL;
	const char *p = aholyc_i_rt_js_src;
	while (*p) {
		const char *eol = strchr (p, '\n');
		size_t n = eol? (size_t)(eol - p) + 1: strlen (p);
		if (!strncmp (p, "//@ ", 4)) {
			if (cur) {
				cur->len = p - cur->src;
			} else {
				g->core_src = aholyc_i_rt_js_src;
				g->core_len = p - aholyc_i_rt_js_src;
			}
			if (g->nchunks >= 160) {
				aholyc_i_error (g->cc, "js backend: too many runtime chunks");
			}
			cur = &g->chunks[g->nchunks++];
			size_t m = n < sizeof(cur->text)? n: sizeof(cur->text) - 1;
			memcpy (cur->text, p + 4, m - 4);
			cur->text[m - 4] = 0;
			char *save = NULL;
			char *t = strtok_r (cur->text, " \t\r\n", &save);
			cur->name = t? t: "?";
			while ((t = strtok_r (NULL, " \t\r\n", &save)) != NULL) {
				if (cur->ndeps < 12) {
					cur->deps[cur->ndeps++] = t;
				}
			}
			cur->src = p + n;
		}
		p += n;
	}
	if (cur) {
		cur->len = p - cur->src;
	} else {
		g->core_src = aholyc_i_rt_js_src;
		g->core_len = p - aholyc_i_rt_js_src;
	}
}

static void mark_chunk(JsGen *g, const char *name) {
	for (int i = 0; i < g->nchunks; i++) {
		if (!strcmp (g->chunks[i].name, name)) {
			if (!g->chunks[i].inc) {
				g->chunks[i].inc = true;
				for (int d = 0; d < g->chunks[i].ndeps; d++) {
					mark_chunk (g, g->chunks[i].deps[d]);
				}
			}
			return;
		}
	}
}

static const char *rt(JsGen *g, const char *name) { mark_chunk (g, name); return name; }
#define RT(name) rt (g, name)
static bool is_agg(Type *ty) { return ty && (ty->kind == TY_CLASS || ty->kind == TY_ARRAY); }
static bool native_var(Obj *v) { return !v->is_extern && !is_agg (v->ty) && !v->address_taken; }

static char *vname(JsGen *g, Obj *v) { return aholyc_i_xasprintf (g->cc, "%c%d_%s", v->is_global? 'g': 'l', v->uid, v->name); }

static int store_size(Obj *v) { return v->is_param? 8: (v->ty->size? v->ty->size: 8); }
static int elem_size(Type *ptrty) {
	return ptrty->base && ptrty->base->size? ptrty->base->size: 1;
}
static const char *extname(Obj *fn) {
	return !strcmp (fn->name, "throw")? "hcThrowFn": fn->name;
}
static char *fname(JsGen *g, Obj *fn) {
	if (fn == g->prog->startup) {
		return aholyc_i_xstrdup (g->cc, "__hc_start");
	}
	if (fn->is_extern) {
		return aholyc_i_xstrdup (g->cc, RT (extname (fn)));
	}
	return aholyc_i_xasprintf (g->cc, "hc_%s", fn->name);
}
static char *var_addr(JsGen *g, Obj *v) {
	if (v->is_extern) {
		return aholyc_i_xasprintf (g->cc, "EXT.%s", v->name);
	}
	if (v->is_global) {
		return aholyc_i_xasprintf (g->cc, "%ld", uid_get (g, v->uid));
	}
	return aholyc_i_xasprintf (g->cc, "(fp+%ld)", uid_get (g, v->uid));
}

static const char *ld_fn(JsGen *g, Type *ty, int size) {
	if (ty->kind == TY_F64) {
		return RT ("ldf");
	}
	switch (size) {
	case 1: return RT (ty->is_unsigned? "ldu1": "lds1");
	case 2: return RT (ty->is_unsigned? "ldu2": "lds2");
	case 4: return RT (ty->is_unsigned? "ldu4": "lds4");
	}
	return RT ("ld8");
}

static const char *st_fn(JsGen *g, Type *ty, int size) {
	if (ty->kind == TY_F64) {
		return RT ("stf");
	}
	switch (size) {
	case 1: return RT ("st1");
	case 2: return RT ("st2");
	case 4: return RT ("st4");
	}
	return RT ("st8");
}

static char *emit_val(JsGen *g, Node *n);

static char *emit_addr(JsGen *g, Node *n) {
	switch (n->kind) {
	case ND_VAR:
		return var_addr (g, n->var);
	case ND_DEREF:
		return emit_val (g, n->lhs);
	case ND_MEMBER: {
		char *b = emit_addr (g, n->lhs);
		if (n->member_ref->offset == 0) {
			return b;
		}
		return aholyc_i_xasprintf (g->cc, "(%s+%d)", b, n->member_ref->offset);
	}
	default:
		aholyc_i_error (g->cc, "js backend: not an lvalue (node kind %d)", n->kind);
		return NULL;
	}
}

static bool is_f(Node *n) { return n->ty && n->ty->kind == TY_F64; }

static Node *append_args(JsGen *g, StrBuf *out, Node *a, int n) {
	for (int i = 0; a && (n < 0 || i < n); i++, a = a->next) {
		if (i) {
			aholyc_i_sb_putc (out, ',');
		}
		char *v = emit_val (g, a);
		aholyc_i_sb_puts (out, v);
	}
	return a;
}

static char *emit_call(JsGen *g, Node *n) {
	StrBuf out;
	aholyc_i_sb_init (&out, g->cc);
	Obj *fn = n->func;
	char *name = fn? fname (g, fn): emit_val (g, n->lhs);
	if (!fn) {
		aholyc_i_sb_printf (&out, "FT[(%s)-1](", name);
		append_args (g, &out, n->args, -1);
		aholyc_i_sb_putc (&out, ')');
	} else if (fn->is_variadic) {
		aholyc_i_sb_printf (&out, "%s(%s,[", RT ("hcVCall"), name);
		Node *a = append_args (g, &out, n->args, n->nfixed);
		aholyc_i_sb_puts (&out, "],[");
		append_args (g, &out, a, -1);
		aholyc_i_sb_puts (&out, "],[");
		for (int i = 0; a; i++, a = a->next) {
			if (i) {
				aholyc_i_sb_putc (&out, ',');
			}
			aholyc_i_sb_putc (&out, is_f (a)? '1': '0');
		}
		aholyc_i_sb_puts (&out, "])");
	} else {
		aholyc_i_sb_printf (&out, "%s(", name);
		append_args (g, &out, n->args, -1);
		aholyc_i_sb_putc (&out, ')');
	}
	return aholyc_i_sb_take (&out);
}

static const char *js_op(NodeKind kind) {
	static const char *const ops[] = {
		[ND_ADD] = "+", [ND_SUB] = "-", [ND_MUL] = "*", [ND_MOD] = "%",
		[ND_AND] = "&", [ND_OR] = "|", [ND_XOR] = "^",
		[ND_SHL] = "<<", [ND_SHR] = ">>", [ND_EQ] = "===",
		[ND_NE] = "!==", [ND_LT] = "<", [ND_LE] = "<=",
	};
	return ops[kind];
}

static char *emit_binary(JsGen *g, Node *n) {
	return aholyc_i_xasprintf (g->cc, "(%s %s %s)", emit_val (g, n->lhs), js_op (n->kind),
		emit_val (g, n->rhs));
}

static char *emit_val(JsGen *g, Node *n) {
	switch (n->kind) {
	case ND_NUM:
		return aholyc_i_xasprintf (g->cc, "%lld", (long long)n->ival);
	case ND_FNUM: {
		char buf[64];
		snprintf (buf, sizeof(buf), "%.17g", n->fval);
		return aholyc_i_xstrdup (g->cc, buf);
	}
	case ND_STR:
		return aholyc_i_xasprintf (g->cc, "%ld", g->str_addr[n->str_id]);
	case ND_VAR: {
		Obj *v = n->var;
		if (native_var (v)) {
			return vname (g, v);
		}
		if (is_agg (v->ty)) {
			return var_addr (g, v);
		}
		return aholyc_i_xasprintf (g->cc, "%s(%s)", ld_fn (g, v->ty, store_size (v)),
			var_addr (g, v));
	}
	case ND_FUNCNAME:
		return aholyc_i_xasprintf (g->cc, "%ld", uid_get (g, n->func->uid));
	case ND_DEREF:
		if (is_agg (n->ty)) {
			return emit_val (g, n->lhs);
		}
		return aholyc_i_xasprintf (g->cc, "%s(%s)", ld_fn (g, n->ty,
			n->ty->size? n->ty->size: 8), emit_val (g, n->lhs));
	case ND_MEMBER:
		if (is_agg (n->ty)) {
			return emit_addr (g, n);
		}
		return aholyc_i_xasprintf (g->cc, "%s(%s)", ld_fn (g, n->ty,
			n->ty->size? n->ty->size: 8), emit_addr (g, n));
	case ND_ADDR:
		return emit_addr (g, n->lhs);
	case ND_ASSIGN: {
		Node *l = n->lhs;
		char *rv = emit_val (g, n->rhs);
		if (l->kind == ND_VAR && native_var (l->var)) {
			return aholyc_i_xasprintf (g->cc, "(%s = %s)", vname (g, l->var), rv);
		}
		if (l->ty && l->ty->kind == TY_CLASS) {
			return aholyc_i_xasprintf (g->cc, "%s(%s,%s,%d)", RT ("MemCpy"),
				emit_addr (g, l), rv, l->ty->size);
		}
		int sz = l->kind == ND_VAR? store_size (l->var):
			(l->ty->size? l->ty->size: 8);
		return aholyc_i_xasprintf (g->cc, "%s(%s,%s)", st_fn (g, l->ty, sz),
			emit_addr (g, l), rv);
	}
	case ND_CAST: {
		Type *to = n->ty, *from = n->lhs->ty;
		char *v = emit_val (g, n->lhs);
		if (to->kind != TY_F64 && from->kind == TY_F64) {
			return aholyc_i_xasprintf (g->cc, "Math.trunc(%s)", v);
		}
		return v;
	}
	case ND_ADD:
	case ND_SUB: {
		Type *lt = n->lhs->ty, *rt = n->rhs->ty;
		bool lp = lt && (lt->kind == TY_PTR || lt->kind == TY_ARRAY);
		bool rp = rt && (rt->kind == TY_PTR || rt->kind == TY_ARRAY);
		char *a = emit_val (g, n->lhs);
		char *b = emit_val (g, n->rhs);
		if (lp && rp && n->kind == ND_SUB) {
			return aholyc_i_xasprintf (g->cc, "Math.trunc((%s - %s) / %d)", a, b,
				elem_size (lt));
		}
		if (lp) {
			return aholyc_i_xasprintf (g->cc, "(%s %s %s * %d)", a, js_op (n->kind), b,
				elem_size (lt));
		}
		return aholyc_i_xasprintf (g->cc, "(%s %s %s)", a, js_op (n->kind), b);
	}
	case ND_MUL:
	case ND_MOD:
	case ND_AND:
	case ND_OR:
	case ND_XOR:
	case ND_SHL:
	case ND_SHR:
	case ND_EQ:
	case ND_NE:
	case ND_LT:
	case ND_LE:
		return emit_binary (g, n);
	case ND_DIV:
		if (n->ty->kind == TY_F64) {
			return aholyc_i_xasprintf (g->cc, "(%s / %s)", emit_val (g, n->lhs),
				emit_val (g, n->rhs));
		}
		return aholyc_i_xasprintf (g->cc, "Math.trunc(%s / %s)",
			emit_val (g, n->lhs), emit_val (g, n->rhs));
	case ND_POW:
		return aholyc_i_xasprintf (g->cc, "(%s ** %s)", emit_val (g, n->lhs),
			emit_val (g, n->rhs));
	case ND_LOGAND:
		return aholyc_i_xasprintf (g->cc, "(%s && %s)",
			emit_val (g, n->lhs), emit_val (g, n->rhs));
	case ND_LOGOR:
		return aholyc_i_xasprintf (g->cc, "(%s || %s)",
			emit_val (g, n->lhs), emit_val (g, n->rhs));
	case ND_LOGXOR:
		return aholyc_i_xasprintf (g->cc, "(Boolean(%s) !== Boolean(%s))",
			emit_val (g, n->lhs), emit_val (g, n->rhs));
	case ND_NOT:
		return aholyc_i_xasprintf (g->cc, "(!%s)", emit_val (g, n->lhs));
	case ND_BITNOT:
		return aholyc_i_xasprintf (g->cc, "(~%s)", emit_val (g, n->lhs));
	case ND_NEG:
		return aholyc_i_xasprintf (g->cc, "(-%s)", emit_val (g, n->lhs));
	case ND_COMMA:
		return aholyc_i_xasprintf (g->cc, "(%s, %s)", emit_val (g, n->lhs),
			emit_val (g, n->rhs));
	case ND_CALL:
		return emit_call (g, n);
	case ND_NOP:
		return aholyc_i_xstrdup (g->cc, "0");
	default:
		aholyc_i_error (g->cc, "js backend: unexpected node kind %d in expression", n->kind);
		return NULL;
	}
}

static void indent(JsGen *g, int n) {
	while (n-- > 0) {
		fputc ('\t', g->out);
	}
}

static bool loop_label(Node *n) {
	if (n->kind != ND_LABEL || !n->label || n->label[0] != '.') {
		return false;
	}
	const char *s = n->label + 1;
	return !strncmp (s, "fend", 4) || !strncmp (s, "wend", 4) ||
		!strncmp (s, "dend", 4);
}

static bool native_stmt(Node *n) {
	switch (n->kind) {
	case ND_NOP:
	case ND_EXPR_STMT:
	case ND_RETURN:
		return true;
	case ND_BLOCK:
		for (Node *s = n->body; s; s = s->next) {
			if (!native_stmt (s)) {
				return false;
			}
		}
		return true;
	case ND_IF:
		return native_stmt (n->then) && (!n->els || native_stmt (n->els));
	case ND_WHILE:
	case ND_DOWHILE:
		return native_stmt (n->then);
	case ND_FOR:
		return (!n->init || native_stmt (n->init)) &&
			(!n->inc || native_stmt (n->inc)) && native_stmt (n->then);
	case ND_TRY:
		return native_stmt (n->then) && native_stmt (n->els);
	case ND_LABEL:
		return loop_label (n);
	default:
		return false;
	}
}

static char *plain_expr(JsGen *g, Node *n) {
	if (n->kind == ND_ASSIGN && n->lhs->kind == ND_VAR && native_var (n->lhs->var)) {
		return aholyc_i_xasprintf (g->cc, "%s = %s", vname (g, n->lhs->var),
			emit_val (g, n->rhs));
	}
	return emit_val (g, n);
}

static char *for_clause(JsGen *g, Node *stmt) {
	if (!stmt || stmt->kind != ND_EXPR_STMT) {
		return "";
	}
	Node *n = stmt->lhs;
	if (n->kind == ND_COMMA && n->lhs->kind == ND_ASSIGN &&
			n->lhs->rhs->kind == ND_VAR && native_var (n->lhs->rhs->var) &&
			n->tok && (!strcmp (n->tok->str, "++") || !strcmp (n->tok->str, "--"))) {
		return aholyc_i_xasprintf (g->cc, "%s%s", vname (g, n->lhs->rhs->var), n->tok->str);
	}
	return plain_expr (g, n);
}

static void emit_native_stmt(JsGen *g, Node *n, int ind) {
	switch (n->kind) {
	case ND_NOP:
	case ND_LABEL:
		break;
	case ND_EXPR_STMT:
		indent (g, ind);
		fprintf (g->out, "%s;\n", plain_expr (g, n->lhs));
		break;
	case ND_BLOCK:
		for (Node *s = n->body; s; s = s->next) {
			emit_native_stmt (g, s, ind);
		}
		break;
	case ND_IF:
		indent (g, ind);
		fprintf (g->out, "if (%s) {\n", emit_val (g, n->cond));
		emit_native_stmt (g, n->then, ind + 1);
		indent (g, ind);
		fprintf (g->out, n->els? "} else {\n": "}\n");
		if (n->els) {
			emit_native_stmt (g, n->els, ind + 1);
			indent (g, ind);
			fprintf (g->out, "}\n");
		}
		break;
	case ND_WHILE:
		indent (g, ind);
		fprintf (g->out, "while (%s) {\n", emit_val (g, n->cond));
		emit_native_stmt (g, n->then, ind + 1);
		indent (g, ind);
		fprintf (g->out, "}\n");
		break;
	case ND_DOWHILE:
		indent (g, ind);
		fprintf (g->out, "do {\n");
		emit_native_stmt (g, n->then, ind + 1);
		indent (g, ind);
		fprintf (g->out, "} while (%s);\n", emit_val (g, n->cond));
		break;
	case ND_FOR:
		indent (g, ind);
		fprintf (g->out, "for (%s; %s; %s) {\n", for_clause (g, n->init),
			n->cond? emit_val (g, n->cond): "", for_clause (g, n->inc));
		emit_native_stmt (g, n->then, ind + 1);
		indent (g, ind);
		fprintf (g->out, "}\n");
		break;
	case ND_RETURN:
		indent (g, ind);
		fprintf (g->out, n->lhs? "return %s;\n": "return 0;\n",
			n->lhs? emit_val (g, n->lhs): "");
		break;
	case ND_TRY:
		indent (g, ind);
		fprintf (g->out, "try {\n");
		emit_native_stmt (g, n->then, ind + 1);
		indent (g, ind);
		fprintf (g->out, "} catch (e) {\n");
		indent (g, ind + 1);
		fprintf (g->out, "if (e !== HCEXC) throw e;\n");
		emit_native_stmt (g, n->els, ind + 1);
		indent (g, ind + 1);
		fprintf (g->out, "if (!ld8(TASK + 8)) %s(ld8(TASK));\n",
			RT ("hcThrowFn"));
		indent (g, ind);
		fprintf (g->out, "}\n");
		break;
	default:
		aholyc_i_error (g->cc, "js backend: cannot emit structured node %d", n->kind);
	}
}

static void jump_to(JsGen *g, int blk) {
	EMIT ("pc=%d;continue;\n", blk);
	g->blocks[g->cur_blk].term = true;
}

static void emit_stmt(JsGen *g, Node *n) {
	if (g->blocks[g->cur_blk].term && n->kind != ND_LABEL) {
		g->cur_blk = new_block (g);
	}
	switch (n->kind) {
	case ND_NOP:
		break;
	case ND_EXPR_STMT: {
		char *v = emit_val (g, n->lhs);
		EMIT ("%s;\n", v);
		break;
	}
	case ND_BLOCK:
		for (Node *s = n->body; s; s = s->next) {
			emit_stmt (g, s);
		}
		break;
	case ND_IF: {
		int tb = new_block (g);
		int eb = n->els? new_block (g): -1;
		int db = new_block (g);
		char *c = emit_val (g, n->cond);
		EMIT ("pc=(%s)?%d:%d;continue;\n", c, tb, n->els? eb: db);
		g->blocks[g->cur_blk].term = true;
		g->cur_blk = tb;
		emit_stmt (g, n->then);
		if (!g->blocks[g->cur_blk].term) {
			jump_to (g, db);
		}
		if (n->els) {
			g->cur_blk = eb;
			emit_stmt (g, n->els);
			if (!g->blocks[g->cur_blk].term) {
				jump_to (g, db);
			}
		}
		g->cur_blk = db;
		break;
	}
	case ND_FOR: {
		if (n->init) {
			emit_stmt (g, n->init);
		}
		int hb = new_block (g), bb = new_block (g), db = new_block (g);
		jump_to (g, hb);
		g->cur_blk = hb;
		if (n->cond) {
			char *c = emit_val (g, n->cond);
			EMIT ("pc=(%s)?%d:%d;continue;\n", c, bb, db);
			g->blocks[g->cur_blk].term = true;
		} else {
			jump_to (g, bb);
		}
		g->cur_blk = bb;
		emit_stmt (g, n->then);
		if (n->inc && !g->blocks[g->cur_blk].term) {
			emit_stmt (g, n->inc);
		}
		if (!g->blocks[g->cur_blk].term) {
			jump_to (g, hb);
		}
		g->cur_blk = db;
		break;
	}
	case ND_RETURN:
		if (n->lhs) {
			char *v = emit_val (g, n->lhs);
			EMIT ("return (%s);\n", v);
		} else {
			EMIT ("return 0;\n");
		}
		g->blocks[g->cur_blk].term = true;
		break;
	case ND_GOTO:
		jump_to (g, label_block (g, n->label));
		break;
	case ND_LABEL: {
		int b = label_block (g, n->label);
		if (!g->blocks[g->cur_blk].term) {
			jump_to (g, b);
		}
		g->cur_blk = b;
		break;
	}
	default: {
		char *v = emit_val (g, n);
		EMIT ("%s;\n", v);
		break;
	}
	}
}

static long align8(long v) { return (v + 7) & ~7L; }

static void emit_func(JsGen *g, Obj *fn) {
	g->nlmap = 0;
	long off = 0;
	for (Obj *p = fn->params; p; p = p->next) {
		if (!native_var (p)) {
			uid_set (g, p->uid, off);
			off += 8;
		}
	}
	for (Obj *v = fn->locals; v; v = v->next) {
		if (!native_var (v)) {
			uid_set (g, v->uid, off);
			off += align8 (v->ty->size? v->ty->size: 8);
		}
	}
	long framesz = off;

	bool native = native_stmt (fn->body);
	int entry = 0;
	if (!native) {
		g->nblocks = 0;
		entry = new_block (g);
		g->cur_blk = entry;
		emit_stmt (g, fn->body);
		if (!g->blocks[g->cur_blk].term) {
			EMIT ("return 0;\n");
		}
	}

	fprintf (g->out, "function %s(", fname (g, fn));
	int i = 0;
	for (Obj *p = fn->params; p; p = p->next, i++) {
		fprintf (g->out, "%s%s", i? ",": "", vname (g, p));
	}
	fprintf (g->out, "){\n");
	for (Obj *v = fn->locals; v; v = v->next) {
		if (native_var (v)) {
			fprintf (g->out, " let %s=0;\n", vname (g, v));
		}
	}
	if (framesz) {
		fprintf (g->out, " const fp=FP;FP+=%ld;\n", framesz);
		fprintf (g->out, " U8A.fill(0,fp,fp+%ld);\n", framesz);
	}
	for (Obj *p = fn->params; p; p = p->next) {
		if (!native_var (p)) {
			fprintf (g->out, " %s(fp+%ld,%s);\n",
				RT (p->ty->kind == TY_F64? "stf": "st8"),
				uid_get (g, p->uid), vname (g, p));
		}
	}
	if (native) {
		if (framesz) {
			fprintf (g->out, " try {\n");
		}
		emit_native_stmt (g, fn->body, framesz? 2: 1);
		Node *last = fn->body->kind == ND_BLOCK? fn->body->body: fn->body;
		while (last && last->next) last = last->next;
		if (!last || last->kind != ND_RETURN) {
			fprintf (g->out, "%sreturn 0;\n", framesz? "  ": " ");
		}
		if (framesz) {
			fprintf (g->out, " } finally { FP=fp; }\n");
		}
		fprintf (g->out, "}\n");
		return;
	}
	fprintf (g->out, " let pc=%d;\n", entry);
	if (framesz) {
		fprintf (g->out, " try {\n");
	}
	fprintf (g->out, " for (;;) switch (pc) {\n");
	for (int i = 0; i < g->nblocks; i++) {
		fprintf (g->out, " case %d:{\n%s }\n", i, g->blocks[i].out.data);
	}
	fprintf (g->out, " default:return 0;\n }\n");
	if (framesz) {
		fprintf (g->out, " } finally { FP=fp; }\n");
	}
	fprintf (g->out, "}\n");
}

static void js_emit(Aholyc *cc, Program *prog, FILE *out,
		bool object_mode, bool ctor_mode) {
	(void)object_mode;
	(void)ctor_mode;
	JsGen *g = aholyc_i_xcalloc (cc, 1, sizeof(*g));
	g->cc = cc;
	g->prog = prog;
	memset (g->umap, -1, sizeof(g->umap));
	parse_rt_chunks (g);

	long addr = 64;
	for (StrLit *s = prog->strings; s; s = s->next) {
		g->str_addr[s->id] = addr;
		addr = align8 (addr + s->len + 1);
	}
	for (Obj *obj = prog->globals; obj; obj = obj->next) {
		if (obj->is_extern || native_var (obj)) {
			continue;
		}
		uid_set (g, obj->uid, addr);
		long sz = obj->ty->size? obj->ty->size: 8;
		if (sz < 8) {
			sz = 8;
		}
		addr = align8 (addr + sz);
	}
	int fidx = 0;
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		uid_set (g, f->uid, ++fidx); /* FT index + 1 */
	}

	char *fbuf = NULL;
	size_t fsize = 0;
	FILE *fo = open_memstream (&fbuf, &fsize);
	if (!fo) {
		aholyc_i_error (cc, "js backend: open_memstream failed");
	}
	MemStream mem = { fo, &fbuf };
	aholyc_i_cleanup_push (cc, cleanup_memstream, &mem);
	g->out = fo;
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		emit_func (g, f);
	}
	emit_func (g, prog->startup);
	fclose (fo);
	mem.file = NULL;

	RT ("chstr");

	g->out = out;
	fprintf (out, "#!/usr/bin/env node\n");
	fwrite (g->core_src, 1, g->core_len, out);
	for (int i = 0; i < g->nchunks; i++) {
		if (g->chunks[i].inc) {
			fwrite (g->chunks[i].src, 1, g->chunks[i].len, out);
		}
	}
	for (Obj *obj = prog->globals; obj; obj = obj->next) {
		if (native_var (obj)) {
			fprintf (out, "let %s=0;\n", vname (g, obj));
		}
	}
	fwrite (fbuf, 1, fsize, out);
	aholyc_i_cleanup_pop (cc);
	free (fbuf);

	fprintf (out, "const FT=[");
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		fprintf (out, "hc_%s,", f->name);
	}
	fprintf (out, "];\n");

	for (StrLit *s = prog->strings; s; s = s->next) {
		fprintf (out, "D(%ld,[", g->str_addr[s->id]);
		for (int i = 0; i < s->len; i++) {
			fprintf (out, "%d,", (unsigned char)s->data[i]);
		}
		fprintf (out, "0]);\n");
	}
	fprintf (out, "setLayout(%ld);\n", addr);

	/* Node has [node, script, ...user] while HolyC startup sees only user
	 * arguments.  Copy strings and their pointer vector into linear memory. */
	fprintf (out, "try{const __hc_args=process.argv.slice(2);"
		"const __hc_argv=HP;HP+=(__hc_args.length+1)*8;"
		"if(HP>HEAP_END)throw new Error('argument vector exceeds memory');"
		"for(let i=0;i<__hc_args.length;i++){"
		"const b=Buffer.from(__hc_args[i],'utf8');"
		"if(HP+b.length+1>HEAP_END)throw new Error('argument data exceeds memory');"
		"st8(__hc_argv+i*8,HP);U8A.set(b,HP);HP+=b.length;U8A[HP++]=0;}"
		"st8(__hc_argv+__hc_args.length*8,0);"
		"const __hc_status=__hc_start(__hc_args.length,__hc_argv);"
		"process.exitCode=((Math.trunc(__hc_status)%%256)+256)%%256;"
		"}catch(e){if(e===HCEXC){"
		"process.stderr.write(\"Unhandled Exception '\"+chstr(ld8(TASK))+\"'\\n\");"
		"process.exit(1);}throw e;}\n");
}

static int js_build(Aholyc *cc, const char *artifact,
		const char *outpath, const char *opt) {
	(void)opt;
	FILE *diag = cc->diagnostics? cc->diagnostics: stderr;
	FILE *in = fopen (artifact, "rb");
	if (!in) {
		aholyc_i_error (cc, "cannot read %s", artifact);
	}
	FILE *outf = fopen (outpath, "wb");
	if (!outf) {
		fclose (in);
		aholyc_i_error (cc, "cannot write %s", outpath);
	}
	char buf[65536];
	size_t n;
	while ((n = fread (buf, 1, sizeof(buf), in)) > 0) {
		fwrite (buf, 1, n, outf);
	}
	fclose (in);
	fclose (outf);
	chmod (outpath, 0755);
	if (cc->verbose) {
		fprintf (diag, "aholyc: wrote node script %s\n", outpath);
	}
	if (!aholyc_i_have_cmd (cc, "node")) {
		fprintf (diag, "aholyc: warning: 'node' not found in PATH; "
			"%s needs a JavaScript runtime\n", outpath);
	}
	return 0;
}

const Backend aholyc_i_backend_js = {
	.name = "js",
	.ext = ".js",
	.descr = "JavaScript for node (linear-memory model)",
	.emit = js_emit,
	.build = js_build,
};
