/* aholyc JavaScript backend. Native JS is used unless a function needs goto. */
#include "aholyc.h"
#include <unistd.h>
#include <sys/stat.h>

typedef struct {
	char *s;
	size_t len;
	FILE *out;
	bool term;
} Blk;

static Blk blocks[1024];
static int nblocks, cur_blk;
static FILE *o;
static Program *cur_prog;

static int new_block(void) {
	if (nblocks >= 1024) {
		error ("js backend: too many blocks");
	}
	memset (&blocks[nblocks], 0, sizeof(Blk));
	blocks[nblocks].out = open_memstream (&blocks[nblocks].s, &blocks[nblocks].len);
	if (!blocks[nblocks].out) {
		error ("js backend: open_memstream failed");
	}
	return nblocks++;
}

#define EMIT(...) fprintf (blocks[cur_blk].out, __VA_ARGS__)

static long umap[65536];

static void uid_set(int uid, long val) {
	if (uid < 0 || uid >= 65536) {
		error ("js backend: uid out of range");
	}
	umap[uid] = val;
}

static long uid_get(int uid) {
	if (uid >= 0 && uid < 65536 && umap[uid] >= 0) {
		return umap[uid];
	}
	error ("js backend: no layout for uid %d", uid);
	return 0;
}

typedef struct { char *name; int blk; } LabMap;
static LabMap lmap[512];
static int nlmap;

static int label_block(const char *name) {
	for (int i = 0; i < nlmap; i++) {
		if (!strcmp (lmap[i].name, name)) {
			return lmap[i].blk;
		}
	}
	if (nlmap >= 512) {
		error ("js backend: too many labels");
	}
	lmap[nlmap].name = xstrdup (name);
	lmap[nlmap].blk = new_block ();
	return lmap[nlmap++].blk;
}

/* rt.js is split into chunks by '//@ name dep...' markers; only chunks
 * transitively referenced by the emitted program are shipped. */
typedef struct {
	char *name;
	char *deps[12];
	int ndeps;
	const char *src;
	size_t len;
	bool inc;
} RtChunk;

static RtChunk chunks[160];
static int nchunks;
static const char *core_src;
static size_t core_len;

static void parse_rt_chunks(void) {
	static bool done;
	if (done) {
		return;
	}
	done = true;
	RtChunk *cur = NULL;
	const char *p = rt_js_src;
	while (*p) {
		const char *eol = strchr (p, '\n');
		size_t n = eol? (size_t)(eol - p) + 1: strlen (p);
		if (!strncmp (p, "//@ ", 4)) {
			if (cur) {
				cur->len = p - cur->src;
			} else {
				core_src = rt_js_src;
				core_len = p - rt_js_src;
			}
			if (nchunks >= 160) {
				error ("js backend: too many runtime chunks");
			}
			cur = &chunks[nchunks++];
			char buf[256];
			size_t m = n < sizeof(buf)? n: sizeof(buf) - 1;
			memcpy (buf, p + 4, m - 4);
			buf[m - 4] = 0;
			char *save = NULL;
			char *t = strtok_r (buf, " \t\r\n", &save);
			cur->name = xstrdup (t? t: "?");
			while ((t = strtok_r (NULL, " \t\r\n", &save)) != NULL) {
				if (cur->ndeps < 12) {
					cur->deps[cur->ndeps++] = xstrdup (t);
				}
			}
			cur->src = p + n;
		}
		p += n;
	}
	if (cur) {
		cur->len = p - cur->src;
	} else {
		core_src = rt_js_src;
		core_len = p - rt_js_src;
	}
}

static void mark_chunk(const char *name) {
	for (int i = 0; i < nchunks; i++) {
		if (!strcmp (chunks[i].name, name)) {
			if (!chunks[i].inc) {
				chunks[i].inc = true;
				for (int d = 0; d < chunks[i].ndeps; d++) {
					mark_chunk (chunks[i].deps[d]);
				}
			}
			return;
		}
	}
}

static const char *RT(const char *name) { mark_chunk (name); return name; }
static bool is_agg(Type *ty) { return ty && (ty->kind == TY_CLASS || ty->kind == TY_ARRAY); }
static bool native_var(Obj *v) { return !v->is_extern && !is_agg (v->ty) && !v->address_taken; }

static char *vname(Obj *v) { return xasprintf ("%c%d_%s", v->is_global? 'g': 'l', v->uid, v->name); }

static int store_size(Obj *v) { return v->is_param? 8: (v->ty->size? v->ty->size: 8); }
static int elem_size(Type *ptrty) {
	return ptrty->base && ptrty->base->size? ptrty->base->size: 1;
}
static const char *extname(Obj *fn) {
	return !strcmp (fn->name, "throw")? "hcThrowFn": fn->name;
}
static char *fname(Obj *fn) {
	if (fn == cur_prog->startup) {
		return xstrdup ("__hc_start");
	}
	if (fn->is_extern) {
		return xstrdup (RT (extname (fn)));
	}
	return xasprintf ("hc_%s", fn->name);
}
static char *var_addr(Obj *v) {
	if (v->is_extern) {
		return xasprintf ("EXT.%s", v->name);
	}
	if (v->is_global) {
		return xasprintf ("%ld", uid_get (v->uid));
	}
	return xasprintf ("(fp+%ld)", uid_get (v->uid));
}

static const char *ld_fn(Type *ty, int size) {
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

static const char *st_fn(Type *ty, int size) {
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

static char *emit_val(Node *n);
static long str_addr[65536];

static char *emit_addr(Node *n) {
	switch (n->kind) {
	case ND_VAR:
		return var_addr (n->var);
	case ND_DEREF:
		return emit_val (n->lhs);
	case ND_MEMBER: {
		char *b = emit_addr (n->lhs);
		if (n->member_ref->offset == 0) {
			return b;
		}
		return xasprintf ("(%s+%d)", b, n->member_ref->offset);
	}
	default:
		error ("js backend: not an lvalue (node kind %d)", n->kind);
		return NULL;
	}
}

static bool is_f(Node *n) { return n->ty && n->ty->kind == TY_F64; }

static void append_arg(char **args, char *value) {
	char *old = *args;
	*args = xasprintf ("%s%s%s", old, *old? ",": "", value);
	free (old);
}

static char *emit_call(Node *n) {
	Obj *fn = n->func;
	if (!fn) {
		char *callee = emit_val (n->lhs);
		char *args = xstrdup ("");
		for (Node *a = n->args; a; a = a->next) {
			append_arg (&args, emit_val (a));
		}
		return xasprintf ("FT[(%s)-1](%s)", callee, args);
	}
	char *nm = fname (fn);
	if (fn->is_variadic) {
		char *fixed = xstrdup ("");
		Node *a = n->args;
		int i = 0;
		for (; a && i < n->nfixed; a = a->next, i++) {
			append_arg (&fixed, emit_val (a));
		}
		char *extras = xstrdup ("");
		char *flags = xstrdup ("");
		for (; a; a = a->next) {
			char *v = emit_val (a);
			char *nf = xasprintf ("%s%s%d", flags, *flags? ",": "", is_f (a)? 1: 0);
			append_arg (&extras, v);
			free (flags);
			flags = nf;
		}
		return xasprintf ("%s(%s,[%s],[%s],[%s])", RT ("hcVCall"),
			nm, fixed, extras, flags);
	}
	char *args = xstrdup ("");
	for (Node *a = n->args; a; a = a->next) {
		append_arg (&args, emit_val (a));
	}
	return xasprintf ("%s(%s)", nm, args);
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

static char *emit_binary(Node *n) {
	return xasprintf ("(%s %s %s)", emit_val (n->lhs), js_op (n->kind),
		emit_val (n->rhs));
}

static char *emit_val(Node *n) {
	switch (n->kind) {
	case ND_NUM:
		return xasprintf ("%lld", (long long)n->ival);
	case ND_FNUM: {
		char buf[64];
		snprintf (buf, sizeof(buf), "%.17g", n->fval);
		return xstrdup (buf);
	}
	case ND_STR:
		return xasprintf ("%ld", str_addr[n->str_id]);
	case ND_VAR: {
		Obj *v = n->var;
		if (native_var (v)) {
			return vname (v);
		}
		if (is_agg (v->ty)) {
			return var_addr (v);
		}
		return xasprintf ("%s(%s)", ld_fn (v->ty, store_size (v)), var_addr (v));
	}
	case ND_FUNCNAME:
		return xasprintf ("%ld", uid_get (n->func->uid));
	case ND_DEREF:
		if (is_agg (n->ty)) {
			return emit_val (n->lhs);
		}
		return xasprintf ("%s(%s)", ld_fn (n->ty, n->ty->size? n->ty->size: 8),
			emit_val (n->lhs));
	case ND_MEMBER:
		if (is_agg (n->ty)) {
			return emit_addr (n);
		}
		return xasprintf ("%s(%s)", ld_fn (n->ty, n->ty->size? n->ty->size: 8),
			emit_addr (n));
	case ND_ADDR:
		return emit_addr (n->lhs);
	case ND_ASSIGN: {
		Node *l = n->lhs;
		char *rv = emit_val (n->rhs);
		if (l->kind == ND_VAR && native_var (l->var)) {
			return xasprintf ("(%s = %s)", vname (l->var), rv);
		}
		if (l->ty && l->ty->kind == TY_CLASS) {
			return xasprintf ("%s(%s,%s,%d)", RT ("MemCpy"),
				emit_addr (l), rv, l->ty->size);
		}
		int sz = l->kind == ND_VAR? store_size (l->var):
			(l->ty->size? l->ty->size: 8);
		return xasprintf ("%s(%s,%s)", st_fn (l->ty, sz), emit_addr (l), rv);
	}
	case ND_CAST: {
		Type *to = n->ty, *from = n->lhs->ty;
		char *v = emit_val (n->lhs);
		if (to->kind != TY_F64 && from->kind == TY_F64) {
			return xasprintf ("Math.trunc(%s)", v);
		}
		return v;
	}
	case ND_ADD:
	case ND_SUB: {
		Type *lt = n->lhs->ty, *rt = n->rhs->ty;
		bool lp = lt && (lt->kind == TY_PTR || lt->kind == TY_ARRAY);
		bool rp = rt && (rt->kind == TY_PTR || rt->kind == TY_ARRAY);
		char *a = emit_val (n->lhs);
		char *b = emit_val (n->rhs);
		if (lp && rp && n->kind == ND_SUB) {
			return xasprintf ("Math.trunc((%s - %s) / %d)", a, b,
				elem_size (lt));
		}
		if (lp) {
			return xasprintf ("(%s %s %s * %d)", a, js_op (n->kind), b,
				elem_size (lt));
		}
		return xasprintf ("(%s %s %s)", a, js_op (n->kind), b);
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
		return emit_binary (n);
	case ND_DIV:
		if (n->ty->kind == TY_F64) {
			return xasprintf ("(%s / %s)", emit_val (n->lhs), emit_val (n->rhs));
		}
		return xasprintf ("Math.trunc(%s / %s)",
			emit_val (n->lhs), emit_val (n->rhs));
	case ND_POW:
		return xasprintf ("(%s ** %s)", emit_val (n->lhs), emit_val (n->rhs));
	case ND_LOGAND:
		return xasprintf ("(%s && %s)",
			emit_val (n->lhs), emit_val (n->rhs));
	case ND_LOGOR:
		return xasprintf ("(%s || %s)",
			emit_val (n->lhs), emit_val (n->rhs));
	case ND_LOGXOR:
		return xasprintf ("(Boolean(%s) !== Boolean(%s))",
			emit_val (n->lhs), emit_val (n->rhs));
	case ND_NOT:
		return xasprintf ("(!%s)", emit_val (n->lhs));
	case ND_BITNOT:
		return xasprintf ("(~%s)", emit_val (n->lhs));
	case ND_NEG:
		return xasprintf ("(-%s)", emit_val (n->lhs));
	case ND_COMMA:
		return xasprintf ("(%s, %s)", emit_val (n->lhs), emit_val (n->rhs));
	case ND_CALL:
		return emit_call (n);
	case ND_NOP:
		return xstrdup ("0");
	default:
		error ("js backend: unexpected node kind %d in expression", n->kind);
		return NULL;
	}
}

static void indent(int n) {
	while (n-- > 0) {
		fputc ('\t', o);
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

static char *plain_expr(Node *n) {
	if (n->kind == ND_ASSIGN && n->lhs->kind == ND_VAR && native_var (n->lhs->var)) {
		return xasprintf ("%s = %s", vname (n->lhs->var), emit_val (n->rhs));
	}
	return emit_val (n);
}

static char *for_clause(Node *stmt) {
	if (!stmt || stmt->kind != ND_EXPR_STMT) {
		return "";
	}
	Node *n = stmt->lhs;
	if (n->kind == ND_COMMA && n->lhs->kind == ND_ASSIGN &&
			n->lhs->rhs->kind == ND_VAR && native_var (n->lhs->rhs->var) &&
			n->tok && (!strcmp (n->tok->str, "++") || !strcmp (n->tok->str, "--"))) {
		return xasprintf ("%s%s", vname (n->lhs->rhs->var), n->tok->str);
	}
	return plain_expr (n);
}

static void emit_native_stmt(Node *n, int ind) {
	switch (n->kind) {
	case ND_NOP:
	case ND_LABEL:
		break;
	case ND_EXPR_STMT:
		indent (ind);
		fprintf (o, "%s;\n", plain_expr (n->lhs));
		break;
	case ND_BLOCK:
		for (Node *s = n->body; s; s = s->next) {
			emit_native_stmt (s, ind);
		}
		break;
	case ND_IF:
		indent (ind);
		fprintf (o, "if (%s) {\n", emit_val (n->cond));
		emit_native_stmt (n->then, ind + 1);
		indent (ind);
		fprintf (o, n->els? "} else {\n": "}\n");
		if (n->els) {
			emit_native_stmt (n->els, ind + 1);
			indent (ind);
			fprintf (o, "}\n");
		}
		break;
	case ND_WHILE:
		indent (ind);
		fprintf (o, "while (%s) {\n", emit_val (n->cond));
		emit_native_stmt (n->then, ind + 1);
		indent (ind);
		fprintf (o, "}\n");
		break;
	case ND_DOWHILE:
		indent (ind);
		fprintf (o, "do {\n");
		emit_native_stmt (n->then, ind + 1);
		indent (ind);
		fprintf (o, "} while (%s);\n", emit_val (n->cond));
		break;
	case ND_FOR:
		indent (ind);
		fprintf (o, "for (%s; %s; %s) {\n", for_clause (n->init),
			n->cond? emit_val (n->cond): "", for_clause (n->inc));
		emit_native_stmt (n->then, ind + 1);
		indent (ind);
		fprintf (o, "}\n");
		break;
	case ND_RETURN:
		indent (ind);
		fprintf (o, n->lhs? "return %s;\n": "return 0;\n",
			n->lhs? emit_val (n->lhs): "");
		break;
	case ND_TRY:
		indent (ind);
		fprintf (o, "try {\n");
		emit_native_stmt (n->then, ind + 1);
		indent (ind);
		fprintf (o, "} catch (e) {\n");
		indent (ind + 1);
		fprintf (o, "if (e !== HCEXC) throw e;\n");
		emit_native_stmt (n->els, ind + 1);
		indent (ind + 1);
		fprintf (o, "if (!ld8(TASK + 8)) %s(ld8(TASK));\n", RT ("hcThrowFn"));
		indent (ind);
		fprintf (o, "}\n");
		break;
	default:
		error ("js backend: cannot emit structured node %d", n->kind);
	}
}

static void jump_to(int blk) {
	EMIT ("pc=%d;continue;\n", blk);
	blocks[cur_blk].term = true;
}

static void emit_stmt(Node *n) {
	if (blocks[cur_blk].term && n->kind != ND_LABEL) {
		cur_blk = new_block ();
	}
	switch (n->kind) {
	case ND_NOP:
		break;
	case ND_EXPR_STMT: {
		char *v = emit_val (n->lhs);
		EMIT ("%s;\n", v);
		break;
	}
	case ND_BLOCK:
		for (Node *s = n->body; s; s = s->next) {
			emit_stmt (s);
		}
		break;
	case ND_IF: {
		int tb = new_block ();
		int eb = n->els? new_block (): -1;
		int db = new_block ();
		char *c = emit_val (n->cond);
		EMIT ("pc=(%s)?%d:%d;continue;\n", c, tb, n->els? eb: db);
		blocks[cur_blk].term = true;
		cur_blk = tb;
		emit_stmt (n->then);
		if (!blocks[cur_blk].term) {
			jump_to (db);
		}
		if (n->els) {
			cur_blk = eb;
			emit_stmt (n->els);
			if (!blocks[cur_blk].term) {
				jump_to (db);
			}
		}
		cur_blk = db;
		break;
	}
	case ND_FOR: {
		if (n->init) {
			emit_stmt (n->init);
		}
		int hb = new_block (), bb = new_block (), db = new_block ();
		jump_to (hb);
		cur_blk = hb;
		if (n->cond) {
			char *c = emit_val (n->cond);
			EMIT ("pc=(%s)?%d:%d;continue;\n", c, bb, db);
			blocks[cur_blk].term = true;
		} else {
			jump_to (bb);
		}
		cur_blk = bb;
		emit_stmt (n->then);
		if (n->inc && !blocks[cur_blk].term) {
			emit_stmt (n->inc);
		}
		if (!blocks[cur_blk].term) {
			jump_to (hb);
		}
		cur_blk = db;
		break;
	}
	case ND_RETURN:
		if (n->lhs) {
			char *v = emit_val (n->lhs);
			EMIT ("return (%s);\n", v);
		} else {
			EMIT ("return 0;\n");
		}
		blocks[cur_blk].term = true;
		break;
	case ND_GOTO:
		jump_to (label_block (n->label));
		break;
	case ND_LABEL: {
		int b = label_block (n->label);
		if (!blocks[cur_blk].term) {
			jump_to (b);
		}
		cur_blk = b;
		break;
	}
	default: {
		char *v = emit_val (n);
		EMIT ("%s;\n", v);
		break;
	}
	}
}

static long align8(long v) { return (v + 7) & ~7L; }

static void emit_func(Obj *fn) {
	long off = 0;
	for (Obj *p = fn->params; p; p = p->next) {
		if (!native_var (p)) {
			uid_set (p->uid, off);
			off += 8;
		}
	}
	for (Obj *v = fn->locals; v; v = v->next) {
		if (!native_var (v)) {
			uid_set (v->uid, off);
			off += align8 (v->ty->size? v->ty->size: 8);
		}
	}
	long framesz = off;

	bool native = native_stmt (fn->body);
	int entry = 0;
	if (!native) {
		nblocks = 0;
		nlmap = 0;
		entry = new_block ();
		cur_blk = entry;
		emit_stmt (fn->body);
		if (!blocks[cur_blk].term) {
			EMIT ("return 0;\n");
		}
	}

	fprintf (o, "function %s(", fname (fn));
	int i = 0;
	for (Obj *p = fn->params; p; p = p->next, i++) {
		fprintf (o, "%s%s", i? ",": "", vname (p));
	}
	fprintf (o, "){\n");
	for (Obj *v = fn->locals; v; v = v->next) {
		if (native_var (v)) {
			fprintf (o, " let %s=0;\n", vname (v));
		}
	}
	if (framesz) {
		fprintf (o, " const fp=FP;FP+=%ld;\n", framesz);
		fprintf (o, " U8A.fill(0,fp,fp+%ld);\n", framesz);
	}
	for (Obj *p = fn->params; p; p = p->next) {
		if (!native_var (p)) {
			fprintf (o, " %s(fp+%ld,%s);\n",
				RT (p->ty->kind == TY_F64? "stf": "st8"),
				uid_get (p->uid), vname (p));
		}
	}
	if (native) {
		if (framesz) {
			fprintf (o, " try {\n");
		}
		emit_native_stmt (fn->body, framesz? 2: 1);
		Node *last = fn->body->kind == ND_BLOCK? fn->body->body: fn->body;
		while (last && last->next) last = last->next;
		if (!last || last->kind != ND_RETURN) {
			fprintf (o, "%sreturn 0;\n", framesz? "  ": " ");
		}
		if (framesz) {
			fprintf (o, " } finally { FP=fp; }\n");
		}
		fprintf (o, "}\n");
		return;
	}
	fprintf (o, " let pc=%d;\n", entry);
	if (framesz) {
		fprintf (o, " try {\n");
	}
	fprintf (o, " for (;;) switch (pc) {\n");
	for (int i = 0; i < nblocks; i++) {
		fclose (blocks[i].out);
		fprintf (o, " case %d:{\n%s }\n", i, blocks[i].s? blocks[i].s: "");
		free (blocks[i].s);
	}
	fprintf (o, " default:return 0;\n }\n");
	if (framesz) {
		fprintf (o, " } finally { FP=fp; }\n");
	}
	fprintf (o, "}\n");
}

static void js_emit(Program *prog, FILE *out) {
	cur_prog = prog;
	memset (umap, -1, sizeof(umap));
	parse_rt_chunks ();

	long addr = 64;
	for (StrLit *s = prog->strings; s; s = s->next) {
		str_addr[s->id] = addr;
		addr = align8 (addr + s->len + 1);
	}
	for (Obj *g = prog->globals; g; g = g->next) {
		if (g->is_extern || native_var (g)) {
			continue;
		}
		uid_set (g->uid, addr);
		long sz = g->ty->size? g->ty->size: 8;
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
		uid_set (f->uid, ++fidx); /* FT index + 1 */
	}

	char *fbuf = NULL;
	size_t fsize = 0;
	FILE *fo = open_memstream (&fbuf, &fsize);
	if (!fo) {
		error ("js backend: open_memstream failed");
	}
	o = fo;
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		emit_func (f);
	}
	emit_func (prog->startup);
	fclose (fo);

	RT ("chstr");

	o = out;
	fprintf (o, "#!/usr/bin/env node\n");
	fwrite (core_src, 1, core_len, o);
	for (int i = 0; i < nchunks; i++) {
		if (chunks[i].inc) {
			fwrite (chunks[i].src, 1, chunks[i].len, o);
		}
	}
	for (Obj *g = prog->globals; g; g = g->next) {
		if (native_var (g)) {
			fprintf (o, "let %s=0;\n", vname (g));
		}
	}
	fwrite (fbuf, 1, fsize, o);
	free (fbuf);

	fprintf (o, "const FT=[");
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		fprintf (o, "hc_%s,", f->name);
	}
	fprintf (o, "];\n");

	for (StrLit *s = prog->strings; s; s = s->next) {
		fprintf (o, "D(%ld,[", str_addr[s->id]);
		for (int i = 0; i < s->len; i++) {
			fprintf (o, "%d,", (unsigned char)s->data[i]);
		}
		fprintf (o, "0]);\n");
	}
	fprintf (o, "setLayout(%ld);\n", addr);

	/* Node has [node, script, ...user] while HolyC startup sees only user
	 * arguments.  Copy strings and their pointer vector into linear memory. */
	fprintf (o, "try{const __hc_args=process.argv.slice(2);"
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

static int js_build(const char *artifact, const char *outpath,
                    const char *opt, bool verbose, bool keep) {
	(void)opt;
	(void)keep;
	FILE *in = fopen (artifact, "rb");
	if (!in) {
		error ("cannot read %s", artifact);
	}
	FILE *outf = fopen (outpath, "wb");
	if (!outf) {
		fclose (in);
		error ("cannot write %s", outpath);
	}
	char buf[65536];
	size_t n;
	while ((n = fread (buf, 1, sizeof(buf), in)) > 0) {
		fwrite (buf, 1, n, outf);
	}
	fclose (in);
	fclose (outf);
	chmod (outpath, 0755);
	if (verbose) {
		fprintf (stderr, "aholyc: wrote node script %s\n", outpath);
	}
	if (!have_cmd ("node")) {
		fprintf (stderr, "aholyc: warning: 'node' not found in PATH; "
			"%s needs a JavaScript runtime\n", outpath);
	}
	return 0;
}

const Backend backend_js = {
	.name = "js",
	.ext = ".js",
	.descr = "JavaScript for node (linear-memory model)",
	.emit = js_emit,
	.build = js_build,
};
